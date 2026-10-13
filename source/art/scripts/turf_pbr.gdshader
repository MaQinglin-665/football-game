shader_type spatial;
render_mode diffuse_burley;
uniform sampler2D grass : source_color,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D grass_normal : hint_normal,filter_linear_mipmap_anisotropic,repeat_enable;
// Linear RG8: R=roughness, G=ambient occlusion; same texels, one filtered fetch.
uniform sampler2D grass_surface : filter_linear_mipmap_anisotropic,repeat_enable;
uniform float stripe_width=7.5;
varying vec3 world;
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 vec2 p=world.xz/1.05;
 float dist=distance(CAMERA_POSITION_WORLD,world);
 vec3 a=texture(grass,p).rgb;
 vec3 b=texture(grass,mat2(vec2(.8,.6),vec2(-.6,.8))*p*.917+vec2(7.73,13.19)).rgb;
 vec3 color=mix(a,b,.23);
 vec3 broad=textureLod(grass,world.xz/7.7+vec2(3.21,1.73),5.).rgb;
 float macro=clamp(broad.g/(OUTPUT_IS_SRGB?.49:.205),.78,1.22);
 float mow=sin(world.z*3.14159265/stripe_width);
 float stripe=smoothstep(-.15,.15,mow)*2.-1.;
 vec3 eye=normalize(CAMERA_POSITION_WORLD-world);
 vec3 tint=OUTPUT_IS_SRGB?vec3(.63,.72,.73):vec3(.28,.40,.85);
 ALBEDO=color*tint*(.40+.60*macro)*(1.+stripe*.07*eye.z);
 vec2 surface_data=texture(grass_surface,p).rg;
 ROUGHNESS=clamp(surface_data.r,.67,.93);SPECULAR=.22;
 AO=mix(1.,surface_data.g,.32);AO_LIGHT_AFFECT=.12;
 vec2 n=(texture(grass_normal,p).rg*2.-1.)*.55;
 n*=1.-smoothstep(18.,55.,dist);n+=(texture(grass_normal,p*.32+vec2(4.1,6.7)).rg*2.-1.)*.10*(1.-smoothstep(28.,75.,dist));n.y+=stripe*.045;
 NORMAL=normalize((VIEW_MATRIX*vec4(normalize(vec3(n.x,1.,n.y)),0.)).xyz);
}
