shader_type spatial;
render_mode cull_disabled;
varying float tip;
void vertex(){
 vec3 w=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;
 float d=distance(CAMERA_POSITION_WORLD,w);
 float fade=1.-smoothstep(3.5,10.,d);
 VERTEX.y*=fade;tip=UV.y;
}
void fragment(){NORMAL=normalize((VIEW_MATRIX*vec4(0.,1.,0.,0.)).xyz);ALBEDO=mix(vec3(.1,.18,.042),vec3(.16,.24,.060),tip);ROUGHNESS=.94;SPECULAR=.15;}
