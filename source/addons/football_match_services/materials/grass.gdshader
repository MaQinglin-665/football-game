shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 grass_dark : source_color = vec4(0.105, 0.255, 0.115, 1.0);
uniform vec4 grass_light : source_color = vec4(0.127, 0.285, 0.127, 1.0);
uniform float mowing_band_m = 5.25;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.09;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.92;
varying vec3 world_position;

float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise21(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2(1,0)), f.x),
               mix(hash21(i + vec2(0,1)), hash21(i + vec2(1,1)), f.x), f.y);
}
void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
    vec2 p = world_position.xz;
    float band = mod(floor(p.y / max(mowing_band_m, 0.25)), 2.0);
    vec3 base = mix(grass_dark.rgb, grass_light.rgb, band);
    float macro = noise21(p * 0.65) - 0.5;
    // Short irregular blades instead of long anisotropic noise streaks.
    float micro = noise21(p * vec2(32.0, 22.0)) - 0.5;
    float footprint = length(fwidth(p));
    float detail_lod = 1.0 - smoothstep(0.008, 0.065, footprint);
    float mid = (noise21(p * 4.0) - 0.5) * (1.0 - smoothstep(0.08, 0.4, footprint));
    ALBEDO = base * (1.0 + macro * 0.06 + mid * 0.07 + micro * detail_strength * detail_lod);
    ROUGHNESS = roughness_value;
    SPECULAR = 0.14;
}
