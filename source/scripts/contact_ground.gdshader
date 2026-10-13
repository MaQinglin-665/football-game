shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;
varying vec4 tint;
void vertex(){ tint=COLOR; }
void fragment(){
    float r=length((UV-vec2(0.5))*2.0);
    ALBEDO=vec3(0.015,0.020,0.025);
    ALPHA=((1.0-smoothstep(0.0,1.0,r))*.65+(1.0-smoothstep(0.0,.38,r))*.35)*tint.a;
}
