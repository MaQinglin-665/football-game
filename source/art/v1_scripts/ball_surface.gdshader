shader_type spatial;
render_mode cull_disabled;
uniform vec4 panel_color:source_color=vec4(.94,.92,.87,1.);
void fragment(){
 vec2 p=UV*130.;
 float fade=1.-smoothstep(.25,.9,max(length(dFdx(p)),length(dFdy(p))));
 float g=sin(p.x*6.283)*sin(p.y*6.283);
 ALBEDO=panel_color.rgb*(1.+g*.022*fade);ROUGHNESS=.43+g*.04*fade;SPECULAR=.43;
 NORMAL_MAP=vec3(.5+cos(p.x*6.283)*sin(p.y*6.283)*.08*fade,.5+sin(p.x*6.283)*cos(p.y*6.283)*.08*fade,1.);NORMAL_MAP_DEPTH=.4;
}
