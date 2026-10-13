shader_type sky;
// One radiance source for the visible sky, ambient light and reflections.
uniform vec4 zenith : source_color = vec4(.45,.61,.74,1.0);
uniform vec4 horizon : source_color = vec4(.78,.84,.87,1.0);
uniform vec4 ground : source_color = vec4(.44,.50,.42,1.0);
uniform vec4 sun_color : source_color = vec4(1.0,.94,.85,1.0);
uniform vec3 sun_direction = vec3(0.0,.8,.6);
uniform bool night = false;
float hash2(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise2(vec2 p){vec2 a=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash2(a),hash2(a+vec2(1,0)),f.x),mix(hash2(a+vec2(0,1)),hash2(a+vec2(1,1)),f.x),f.y);}
void sky(){
 vec3 d=normalize(EYEDIR);
 vec3 base=mix(horizon.rgb,zenith.rgb,pow(max(d.y,0.0),.55));
 base=mix(base,ground.rgb,smoothstep(0.0,.45,-d.y));
 vec2 p=d.xz/max(d.y+.18,.08)*2.7;
 float n=noise2(p)*.58+noise2(p*2.03+vec2(17,4))*.28+noise2(p*4.07)*.14;
 float cloud=smoothstep(.48,.69,n)*smoothstep(.015,.15,d.y);
 vec3 cloud_color=mix(horizon.rgb,sun_color.rgb,.40+smoothstep(.50,.80,n)*.30);
 base=mix(base,cloud_color,cloud*(night?.13:.62));
 float alignment=max(dot(d,normalize(sun_direction)),0.0);
 float disk=smoothstep(cos(.010),cos(.0045),alignment);
 base+=sun_color.rgb*(disk*1.5+pow(alignment,128.0)*.07)*(night?0.0:1.0);
 COLOR=base;
}
