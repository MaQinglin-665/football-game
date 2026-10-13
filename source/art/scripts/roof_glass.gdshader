shader_type spatial;
render_mode blend_mix,cull_disabled,depth_draw_never;
void fragment(){
 float fresnel=pow(1.0-clamp(abs(dot(normalize(NORMAL),normalize(VIEW))),0.0,1.0),4.0);
 ALBEDO=vec3(.08,.14,.18);ROUGHNESS=.20;METALLIC=.0;SPECULAR=.25;
 ALPHA=.035+fresnel*.12;
}
