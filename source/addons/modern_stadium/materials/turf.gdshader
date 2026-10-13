shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
uniform vec4 base_color : source_color = vec4(0.10,0.30,0.15,1.0);
uniform float stripe_width = 7.5;
uniform float stripe_contrast : hint_range(0.0,0.2) = 0.065;
varying vec3 ground_pos;
void vertex() { ground_pos = VERTEX; }
void fragment() {
    float stripe = mod(floor((ground_pos.z + 52.5) / stripe_width), 2.0);
    float micro = sin(ground_pos.x * 5.0) * sin(ground_pos.z*7.0) * 0.003;
    ALBEDO = base_color.rgb * (1.0 + stripe * stripe_contrast + micro);
    ROUGHNESS = 1.0;
}
