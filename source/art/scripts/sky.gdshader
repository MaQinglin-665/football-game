shader_type sky;
uniform sampler2D panorama:source_color,filter_linear_mipmap,repeat_enable;
uniform mat3 source_rotation=mat3(1.0);
uniform bool night=false;
uniform bool linear_render=false;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise2(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);}
float cloud(vec2 p){
 float sum=0.;float amplitude=.55;
 mat2 turn=mat2(vec2(.8,.6),vec2(-.6,.8));
 for(int i=0;i<5;i++){sum+=noise2(p)*amplitude;p=turn*p*2.07+vec2(9.1,3.7);amplitude*=.48;}
 return sum;
}
void sky(){
 vec3 d=normalize(source_rotation*EYEDIR);
 vec2 uv=vec2(atan(d.x,d.z)/6.2831853+.5,acos(clamp(d.y,-1.,1.))/3.14159265);
 vec3 s=texture(panorama,uv).rgb;
 if(night){
  vec3 ray=normalize(EYEDIR);
  vec3 moon_dir=normalize(vec3(-.20,.83,-.52));
  float angle=acos(clamp(dot(ray,moon_dir),-1.,1.));
  float disc=1.-smoothstep(.010,.011,angle);
  float halo=exp(-angle*angle/ .0035);
  vec2 cp=ray.xz/max(ray.y+.22,.08)*2.3+vec2(3.7,1.2);
  float density=smoothstep(.39,.70,cloud(cp))*smoothstep(-.04,.24,ray.y);
  vec3 base=mix(vec3(.045,.070,.12),vec3(.11,.15,.21),pow(1.-max(ray.y,0.),3.));
  vec3 clouds=mix(vec3(.15,.19,.25),vec3(.26,.29,.34),clamp(dot(ray,moon_dir),0.,1.));
  vec3 c=mix(base,clouds,density*.86);
  float crater=.87+.13*noise2(ray.xz*900.);
  c+=vec3(.78,.79,.74)*disc*crater*(1.-density*.88)+vec3(.14,.18,.23)*halo*(1.-density);
  COLOR=linear_render?pow(c,vec3(2.2)):c;
 }else{COLOR=pow(s/(s+vec3(.8)),vec3(.72));}
}
