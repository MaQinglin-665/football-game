shader_type spatial;
render_mode cull_disabled;
varying float tip;
void vertex(){
 vec3 w=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;
 float d=distance(CAMERA_POSITION_WORLD,w);
 float fade=1.-smoothstep(2.5,5.5,d);
 VERTEX.y*=fade;tip=UV.y;
}
void fragment(){NORMAL=normalize((VIEW_MATRIX*vec4(0.,1.,0.,0.)).xyz);ALBEDO=mix(vec3(.055,.105,.028),vec3(.10,.18,.05),tip);ROUGHNESS=.94;SPECULAR=.15;}
