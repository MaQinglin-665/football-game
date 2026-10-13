shader_type spatial;
render_mode unshaded,cull_disabled,depth_draw_never,fog_disabled;
uniform vec3 sun_direction=vec3(0.0,0.8,0.6);
uniform bool night=false;
varying vec3 ray;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 a=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(a),hash(a+vec2(1,0)),f.x),mix(hash(a+vec2(0,1)),hash(a+vec2(1,1)),f.x),f.y);}
void vertex(){ray=normalize(VERTEX);}
void fragment(){
 vec3 d=normalize(ray);vec2 p=d.xz/max(d.y+0.18,0.08)*2.7;
 float n=noise(p)*0.58+noise(p*2.03+vec2(17,4))*0.28+noise(p*4.07)*0.14;
 float cloud=smoothstep(0.48,0.69,n)*smoothstep(0.015,0.15,d.y);
 float sun=smoothstep(cos(0.016),cos(0.008),dot(d,normalize(sun_direction)))*(night?0.0:1.0);
 float halo=pow(max(dot(d,normalize(sun_direction)),0.0),160.0)*0.14*(night?0.0:1.0);
 vec3 lit=mix(vec3(0.69,0.76,0.84),vec3(0.95,0.95,0.93),smoothstep(0.5,0.8,n));
 ALBEDO=mix(night?vec3(0.10,0.15,0.24):lit,vec3(1.0,0.91,0.70),sun);
 ALPHA=clamp(cloud*(night?0.20:0.68)+sun+halo,0.0,1.0);
}
