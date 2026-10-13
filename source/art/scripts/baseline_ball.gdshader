shader_type spatial;
render_mode cull_disabled, shadows_disabled;
uniform vec4 panel_color:source_color=vec4(0.94,0.92,0.87,1.0);
uniform float roughness_value=0.62;
void fragment(){
 vec2 grid=UV*185.0;
 float fade=1.0-smoothstep(0.3,1.1,max(length(dFdx(grid)),length(dFdy(grid))));
 float grain=sin(grid.x*6.283)*sin(grid.y*6.283);
 float trim=1.0-smoothstep(0.006,0.016,abs(length(UV)-0.17));
 float mark=trim*step(0.15,UV.x)*step(UV.x,0.21);
 ALBEDO=panel_color.rgb*(1.0+grain*0.025*fade);
 ALBEDO=mix(ALBEDO,vec3(0.08,0.25,0.39),mark*0.55);
 ROUGHNESS=roughness_value+grain*0.06*fade;SPECULAR=0.38;
 NORMAL_MAP=vec3(0.5+cos(grid.x*6.283)*sin(grid.y*6.283)*0.07*fade,0.5+sin(grid.x*6.283)*cos(grid.y*6.283)*0.07*fade,1.0);
 NORMAL_MAP_DEPTH=0.32;
}
