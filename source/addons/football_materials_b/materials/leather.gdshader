shader_type spatial;
uniform vec4 panel_color : source_color = vec4(0.92, 0.93, 0.89, 1.0);
uniform float roughness_value : hint_range(0.0, 1.0) = 0.56;
uniform float pebble_scale = 900.0;
uniform float bump_strength : hint_range(0.0, 2.0) = 0.9;
uniform float wear_amount : hint_range(0.0, 0.2) = 0.05;
// The ball mesh is a sphere around its origin: shade it round instead of faceted.
uniform bool sphere_normals = true;
varying vec3 local_position;
varying vec3 sphere_normal;

float hash31(vec3 p) {
    return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}
float value_noise(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash31(i), hash31(i + vec3(1, 0, 0)), f.x),
                   mix(hash31(i + vec3(0, 1, 0)), hash31(i + vec3(1, 1, 0)), f.x), f.y),
               mix(mix(hash31(i + vec3(0, 0, 1)), hash31(i + vec3(1, 0, 1)), f.x),
                   mix(hash31(i + vec3(0, 1, 1)), hash31(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
void vertex() {
    local_position = VERTEX;
    sphere_normal = (MODELVIEW_MATRIX * vec4(VERTEX, 0.0)).xyz;
}
void fragment() {
    // No UV assumptions: works on the baseline's separate polygon surfaces.
    float close_detail = 1.0 - smoothstep(0.0003, 0.0016, length(fwidth(local_position)));
    // Rounded pebbles: smooth noise with sharpened crowns, not hard voxel cells.
    float pebble = smoothstep(0.25, 0.85, value_noise(local_position * pebble_scale));
    if (sphere_normals) {
        NORMAL = normalize(sphere_normal);
    }
    // Screen-derivative bump (surface gradient), so no tangents or UVs are needed.
    vec3 dpdx = dFdx(VERTEX);
    vec3 dpdy = dFdy(VERTEX);
    // Height in metres (about 0.12 mm), matching VERTEX units for the gradient.
    float h = pebble * close_detail * bump_strength * 0.00012;
    vec3 r1 = cross(dpdy, NORMAL);
    vec3 r2 = cross(NORMAL, dpdx);
    float det = dot(dpdx, r1);
    vec3 surface_grad = sign(det) * (dFdx(h) * r1 + dFdy(h) * r2);
    NORMAL = normalize(abs(det) * NORMAL - surface_grad);
    // Broad scuffs keep the white panels from reading as flat plastic.
    float wear = value_noise(local_position * 45.0);
    vec3 color = panel_color.rgb * (1.0 - (1.0 - pebble) * 0.05 * close_detail);
    color *= 1.0 - smoothstep(0.55, 0.95, wear) * wear_amount;
    ALBEDO = color;
    // Pebble crowns are polished, the grooves between them stay matte.
    ROUGHNESS = clamp(roughness_value + (0.5 - pebble) * 0.16 * close_detail + wear * 0.04, 0.0, 1.0);
    SPECULAR = 0.32;
}
