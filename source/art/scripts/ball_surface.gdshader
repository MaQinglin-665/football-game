shader_type spatial;
render_mode cull_disabled;
uniform vec4 panel_color:source_color=vec4(.94,.92,.87,1.);
void fragment(){
 vec2 p=UV*130.;
 float fade=1.-smoothstep(.25,.9,max(length(dFdx(p)),length(dFdy(p))));
 float g=sin(p.x*6.283)*sin(p.y*6.283);
 // Original concentric panel graphics. Printed ink shares the embossed cover.
 float r=length(UV);float aa=max(fwidth(r),.001);
 float ring=smoothstep(.155-aa,.155+aa,r)*(1.-smoothstep(.182-aa,.182+aa,r));
 float accent=smoothstep(.188-aa,.188+aa,r)*(1.-smoothstep(.205-aa,.205+aa,r));
 vec3 base=panel_color.rgb;
 if(panel_color.r>.5){base=mix(base,vec3(.015,.07,.16),ring);base=mix(base,vec3(.72,.19,.025),accent);}
 ALBEDO=base*(1.+g*.018*fade);ROUGHNESS=.51+g*.025*fade;SPECULAR=.32;
 NORMAL_MAP=vec3(.5+cos(p.x*6.283)*sin(p.y*6.283)*.08*fade,.5+sin(p.x*6.283)*cos(p.y*6.283)*.08*fade,1.);NORMAL_MAP_DEPTH=.4;
}
