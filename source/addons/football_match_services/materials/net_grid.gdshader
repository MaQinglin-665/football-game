shader_type spatial;
render_mode cull_disabled;
uniform vec4 cord_color : source_color = vec4(0.82, 0.85, 0.85, 1.0);
uniform vec2 cell_count = vec2(45.0, 18.0);
uniform float cord_fraction = 0.035;
void fragment() {
    vec2 grid = abs(fract(UV * cell_count) - 0.5);
    float near_edge = max(grid.x, grid.y);
    float width = max(fwidth(UV.x * cell_count.x), fwidth(UV.y * cell_count.y));
    float alpha = smoothstep(0.5 - cord_fraction - width, 0.5 - cord_fraction, near_edge);
    if (alpha < 0.45) { discard; }
    ALBEDO = cord_color.rgb;
    ROUGHNESS = 0.87;
}
