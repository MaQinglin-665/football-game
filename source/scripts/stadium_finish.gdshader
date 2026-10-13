shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec4 base_color : source_color = vec4(.43,.44,.42,1.0);
uniform int kind = 0;
uniform bool detail_enabled = true;
varying vec3 world;
varying vec3 local;
varying vec3 normal_world;
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;local=VERTEX;normal_world=normalize((MODEL_MATRIX*vec4(NORMAL,0.0)).xyz);}
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise2(vec2 p){vec2 i=floor(p);vec2 f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void fragment(){
 vec3 tint=base_color.rgb;float rough=.89;float ao=1.0;float spec=.16;
 float dist=distance(CAMERA_POSITION_WORLD,world);float fade=1.0-smoothstep(20.0,65.0,dist);
 vec2 p=abs(normal_world.y)>.65?world.xz:vec2(abs(normal_world.x)>.65?world.z:world.x,world.y);
 if(kind==1){tint*=mix(vec3(.72),vec3(1.0),COLOR.rgb);rough=.57;spec=.28;ao=mix(.76,1.0,smoothstep(.10,.35,local.y));tint*=.94+.06*smoothstep(.05,.52,local.y);}
 else if(kind==2){rough=.43;spec=.45;METALLIC=.58;}
 else if(kind==3){rough=.95;spec=.10;}
 if(detail_enabled){
  float grain=noise2(p*(kind==3?38.0:kind==1?85.0:25.0));
  // Filter each material by its own noise frequency (plastic is 85 cells/metre).
  float frequency=kind==3?38.0:kind==1?85.0:25.0;
  float footprint=max(length(dFdx(p)),length(dFdy(p)))*frequency;
  float resolved=fade*(1.0-smoothstep(.35,1.0,footprint));
  tint*=1.0+(grain-.5)*(kind==1?.045:.14)*resolved;
  rough=clamp(rough+(grain-.5)*.12*resolved,.2,1.0);
  if(kind==4){
   vec2 roof_grid=abs(fract(p/vec2(2.4,6.0))-.5)*vec2(2.4,6.0);
   float joint=min(1.2-roof_grid.x,3.0-roof_grid.y);
   tint*=mix(.72,1.0,smoothstep(.014,.014+max(length(fwidth(p)),.009),joint));rough=.69;spec=.25;
  }
  if(kind==0 || kind==3){
   tint*=.95+.10*noise2(p*.38);
   vec2 grid=abs(fract(p/vec2(3.0,1.5))-.5)*vec2(3.0,1.5);
   vec2 edge=vec2(1.5,.75)-grid;float seam=min(edge.x,edge.y);
   float aa=max(length(fwidth(p)),.008);
   tint*=mix(.79,1.0,smoothstep(.009,.009+aa,seam));
  }
 }
 ALBEDO=tint;ROUGHNESS=rough;SPECULAR=spec;AO=ao;
}
