shader_type spatial;
render_mode diffuse_burley;
varying vec4 person;
varying float eye_distance;
void vertex(){
 person=INSTANCE_CUSTOM;
 float upper=max(VERTEX.y-.40,0.);
 VERTEX.y+=upper*mix(-.20,.15,person.w);
 VERTEX.z+=upper*mix(-.10,.075,person.z);
 float angle=mix(-.16,.16,person.y)*smoothstep(.4,.9,VERTEX.y);
 mat2 turn=mat2(vec2(cos(angle),sin(angle)),vec2(-sin(angle),cos(angle)));
 VERTEX.xz=turn*VERTEX.xz;NORMAL.xz=turn*NORMAL.xz;
 eye_distance=length((MODELVIEW_MATRIX*vec4(VERTEX,1.0)).xyz);
}
void fragment(){
 float part=UV.x;
 // Muted supporter clothes: blue, slate, burgundy, sand and warm off-white.
 vec3 shirt=vec3(.055,.09,.16);
 if(person.x>.20)shirt=vec3(.16,.20,.25);
 if(person.x>.40)shirt=vec3(.19,.075,.07);
 if(person.x>.52)shirt=vec3(.25,.21,.155);
 if(person.x>.67)shirt=vec3(.24,.235,.22);
 if(person.x>.86)shirt=vec3(.10,.15,.225);
 shirt*=mix(.85,1.08,person.z);
 // Suppress distant black/white flecks without emissive or unshaded people.
 float far_mix=smoothstep(22.,85.,eye_distance)*.48;
 shirt=mix(shirt,vec3(.15,.165,.18),far_mix);
 vec3 skin=mix(vec3(.12,.066,.035),vec3(.29,.205,.145),person.y);
 vec3 c=shirt;
 if(part>.5&&part<1.5)c=skin;
 if(part>1.5&&part<2.5)c=mix(vec3(.033,.042,.06),vec3(.10,.115,.14),person.z);
 if(part>2.5&&part<3.5)c=mix(vec3(.024,.018,.014),vec3(.105,.069,.038),person.w);
 if(part>3.5&&part<4.5)c=shirt*.65;
 if(part>4.5&&part<5.5)c=vec3(.03,.035,.042);
 if(part>5.5)c=vec3(.13,.14,.15);
 c=mix(c,mix(shirt,skin,.13),smoothstep(40.,110.,eye_distance)*.35);
 ALBEDO=c;ROUGHNESS=.88;SPECULAR=.03;
}
