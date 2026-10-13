shader_type spatial;
uniform vec4 panel_color : source_color = vec4(0.92, 0.93, 0.89, 1.0);
uniform float roughness_value : hint_range(0.0, 1.0) = 0.56;
varying vec3 local_position;

float hash31(vec3 p) {
    return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}
void vertex() {
    local_position = VERTEX;
}
void fragment() {
    // No UV assumptions: works on the baseline's separate polygon surfaces.
    float pebble = hash31(floor(local_position * 1900.0));
    float close_detail = 1.0 - smoothstep(0.0006, 0.007, length(fwidth(local_position)));
    // Keep panel boundaries supplied by the mesh; radial thresholds create false rings.
    ALBEDO = panel_color.rgb * (1.0 - pebble * 0.055 * close_detail);
    ROUGHNESS = roughness_value + pebble * 0.075 * close_detail;
    SPECULAR = 0.24;
}
