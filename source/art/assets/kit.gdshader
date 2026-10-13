shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec4 team : source_color = vec4(.12,.28,.43,1);
uniform sampler2D jersey_digits : filter_linear_mipmap, repeat_disable;
uniform int jersey_number = -1;
uniform int part = 0; // torso, arms, legs, head, boot upper, sole, studs, laces, accent
uniform bool inset = false;
uniform bool authored_rest=false;
varying vec3 rest;
void vertex(){rest=authored_rest?vec3(UV2.x,COLOR.r*2.0,UV2.y):VERTEX;}
void fragment(){
 vec3 ink=vec3(.145,.17,.205);
 vec3 ivory=vec3(.73,.74,.72);
 vec3 skin=vec3(.57,.36,.23);
 vec3 c=team.rgb;
 float cloth=1.0; float leather=0.0;
 float h=rest.y;
 if(part==0){
   float side=smoothstep(.142,.192,abs(rest.x));
   c=mix(c,ink,side*.35);
   float chest=(1.0-smoothstep(.006,.012,abs(h-1.365)));
   c=mix(c,ivory,chest*.8);
   if(h>1.492)c=ink;
   if(h<1.12)c=ink;
   if(inset)c*=.76;
 }else if(part==1){
   if(h<1.29){c=skin;cloth=0.0;}
   else if(h<1.318)c=ivory;
 }else if(part==2){
   if(h>.74)c=ink;
   else if(h>.51){c=skin;cloth=0.0;}
   else {c=ivory; if(h>.464 || (h>.425 && h<.435))c=team.rgb;}
 }else if(part==3){
   c=skin;cloth=0.0;
 }else{
   cloth=0.0;leather=1.0;c=ink;
   if(part==5)c=vec3(.13,.145,.16);
   if(part==6)c=vec3(.27,.29,.29);
   if(part==7)c=ivory;
   if(part==8)c=mix(team.rgb,ivory,.3);
 }
 // Rest-space detail follows skinning. Screen derivatives suppress subpixel weave.
 vec2 uv=vec2(rest.x+rest.z*.73,rest.y);
 float footprint=max(length(dFdx(uv)),length(dFdy(uv)));
 float visible=1.0-smoothstep(.0009,.004,footprint);
 float weave=sin(uv.x*2600.0)*sin(uv.y*1950.0);
 float stitch=sin(uv.x*360.0+sin(uv.y*430.0))*sin(uv.y*390.0);
 float grain=mix(stitch,weave,cloth)*visible;
 c*=1.0+grain*(.035+cloth*.045);
 // Broad knitted panels remain legible beyond the micro-detail range.

 // Original broad ventilation panels and raised seam shading; no geometry/rig changes.
 float side_seam=(1.0-smoothstep(.002,.008,abs(abs(rest.x)-.158)))*step(1.13,h)*step(h,1.47);
 float vent=(0.5+0.5*sin(h*240.0))*smoothstep(.10,.18,abs(rest.x));
 if(part==0){c*=1.0-vent*.045;c=mix(c,ivory,side_seam*.25);}
 if(part==4){float boot_seam=1.0-smoothstep(.002,.007,abs(rest.z+.11));c=mix(c,ivory,boot_seam*.12);}
 if(part==0 && jersey_number>=0){
  bool front=rest.z<0.0;
  vec2 size=front?vec2(.105,.145):vec2(.205,.285);
  vec2 at=vec2(front?-rest.x:rest.x,rest.y-(front?1.385:1.29));
  vec2 uvn=vec2(at.x/size.x+.5,.5-at.y/size.y);
  if(abs(rest.z)>.06 && all(greaterThanEqual(uvn,vec2(0))) && all(lessThanEqual(uvn,vec2(1)))){
   bool two=jersey_number>=10;float cell=two?uvn.x*2.0:uvn.x;
   int digit=two && cell<1.0?jersey_number/10:jersey_number%10;
   float ink_number=texture(jersey_digits,vec2((float(digit)+fract(cell))*.1,uvn.y)).a;
   c=mix(c,vec3(.88,.90,.88),ink_number);
  }
 }
 ALBEDO=c;
 ROUGHNESS=clamp(mix(.62,.72,cloth)-leather*.10+grain*.045,.38,.98);
 METALLIC=part==6?.18:0.0;
 SPECULAR=mix(.30,.32,cloth);
 float bump=grain*(cloth>.5?.000055:.000025);
 vec3 dpdx=dFdx(VERTEX),dpdy=dFdy(VERTEX);
 vec3 r1=cross(dpdy,NORMAL),r2=cross(NORMAL,dpdx);
 float det=dot(dpdx,r1);
 vec3 grad=sign(det)*(dFdx(bump)*r1+dFdy(bump)*r2);
 NORMAL=normalize(max(abs(det),.0000000001)*NORMAL-grad);
}
