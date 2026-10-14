shader_type spatial;
render_mode cull_disabled;
varying float tip;
void vertex(){
 vec3 w=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;
 float d=distance(CAMERA_POSITION_WORLD,w);
 float fade=1.-smoothstep(2.5,5.5,d);
 VERTEX.y*=fade;
 // Collapse the bent tip onto the base line too: no flat opaque triangles left on turf.
 VERTEX.xz*=mix(1.,fade,UV.y);tip=UV.y;
}
void fragment(){NORMAL=normalize((VIEW_MATRIX*vec4(0.,1.,0.,0.)).xyz);ALBEDO=mix(vec3(.045,.13,.038),vec3(.085,.20,.052),tip);ROUGHNESS=.94;SPECULAR=.15;}
