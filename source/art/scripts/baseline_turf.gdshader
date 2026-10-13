shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// RGBA linear data: R blade tone, G clump/macro, BA blade normal x/z.
uniform sampler2D detail_texture : repeat_enable, filter_linear_mipmap_anisotropic;
uniform vec4 grass_dark : source_color = vec4(0.155, 0.258, 0.113, 1.0);
uniform vec4 grass_light : source_color = vec4(0.205, 0.323, 0.146, 1.0);
uniform vec4 grass_dry : source_color = vec4(0.260, 0.290, 0.156, 1.0);
uniform float pitch_half_length = 52.5;
uniform float mowing_band_m = 7.5;
uniform float detail_tile_m = 1.15;
uniform float macro_tile_m = 21.0;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.30;
uniform float clump_strength : hint_range(0.0, 1.0) = 0.12;
uniform float macro_strength : hint_range(0.0, 1.0) = 0.12;
uniform float dry_patch_amount : hint_range(0.0, 1.0) = 0.10;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.43;
uniform float detail_fade_start_m = 14.0;
uniform float detail_fade_end_m = 55.0;
// Mowed stripes come from blade lean: brightness follows the view direction.
uniform float stripe_view_dependence : hint_range(0.0, 1.0) = 0.40;
uniform float grazing_sheen : hint_range(0.0, 0.5) = 0.045;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.86;
uniform bool close_detail_enabled = true;
varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
    vec2 p = world_position.xz;
    vec3 to_camera = CAMERA_POSITION_WORLD - world_position;
    float distance_m = length(to_camera);
    float width = max(mowing_band_m, 0.25);
    float phase = fract((p.y + width * 0.5) / (width * 2.0));
    float triangle_band = 1.0 - abs(phase * 2.0 - 1.0);
    float band_filter = max(0.025, fwidth(p.y) / (2.0 * width));
    float band = smoothstep(0.5 - band_filter, 0.5 + band_filter, triangle_band);
    // Looking across the stripes (along x) both lean directions look alike.
    float along = to_camera.z / max(length(to_camera.xz), 1e-3);
    float lean = mix(1.0, along, stripe_view_dependence);
    vec3 albedo = mix(grass_dark.rgb, grass_light.rgb, clamp(0.5 + (band - 0.5) * lean, 0.0, 1.0));
    float rough = roughness_value;
    float occlusion=1.0;
    vec3 n_world = normalize(world_normal);
    // Uniform branch: the low material tier skips the texture reads entirely.
    if (close_detail_enabled) {
        vec2 detail_uv = p / max(detail_tile_m, 0.1);
        vec4 detail = texture(detail_texture, detail_uv);
        // Incommensurate rotated blend prevents one obvious repeating blade stamp.
        mat2 turn = mat2(vec2(0.8,0.6),vec2(-0.6,0.8));
        vec4 secondary = texture(detail_texture,turn*detail_uv*0.731+vec2(0.173,0.417));
        vec2 rotated_normal=transpose(turn)*(secondary.ba*2.0-1.0);
        detail.rg=mix(detail.rg,secondary.rg,0.35);
        detail.ba=mix(detail.ba,rotated_normal*0.5+0.5,0.35);
        // Second read of the same texture, rotated and enlarged, hides the tile period.
        vec2 q = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p / max(macro_tile_m, 1.0);
        float macro = texture(detail_texture, q + vec2(0.37, 0.71)).g;
        float fade = (1.0 - smoothstep(detail_fade_start_m, detail_fade_end_m, distance_m))
            * (1.0-smoothstep(0.004,0.025,max(length(dFdx(p)),length(dFdy(p)))));
        albedo *= 1.0 + (detail.r - 0.5) * detail_strength * fade
            + (detail.g - 0.5) * clump_strength * (0.35+0.65*fade) + (macro - 0.5) * macro_strength * 2.0;
        float wear_lane=exp(-pow(abs(p.x)/5.5,2.0));
        float goal_wear=wear_lane*exp(-pow((abs(p.y)-pitch_half_length+1.5)/4.0,2.0));
        float center_wear=exp(-dot(p/vec2(4.5,5.5),p/vec2(4.5,5.5)));
        float wear=clamp(goal_wear*.32+center_wear*.10,0.0,.4);
        albedo=mix(albedo,grass_dry.rgb,wear*(.65+macro*.35));
        float dry = smoothstep(0.52, 0.80, macro) * dry_patch_amount*(0.8+0.5*wear_lane);
        albedo = mix(albedo, albedo * grass_dry.rgb / max(grass_light.rgb, vec3(0.01)), dry);
        occlusion=mix(1.0,mix(.87,1.0,smoothstep(.08,.70,detail.r)),fade);
        vec2 blade_n = (detail.ba * 2.0 - 1.0) * normal_strength * fade;
        n_world = normalize(n_world + vec3(blade_n.x, 0.0, blade_n.y));
        // Blade tips are slightly glossier than the shaded thatch beneath.
        rough = clamp(roughness_value - (detail.r - 0.5) * 0.23 * fade + wear*.10, 0.0, 1.0);
    }
    float ndv = clamp(dot(normalize(world_normal), to_camera / max(distance_m, 1e-3)), 0.0, 1.0);
    float sheen = pow(1.0 - ndv, 4.0) * grazing_sheen;
    albedo = mix(albedo, vec3(dot(albedo, vec3(0.333))) * 1.35, sheen);
    ALBEDO = albedo;
    NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
    ROUGHNESS = rough;
    SPECULAR = 0.12;
    AO = occlusion;
}
