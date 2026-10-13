shader_type spatial;
render_mode diffuse_burley;
uniform sampler2D grass : source_color,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D grass_normal : hint_normal,filter_linear_mipmap_anisotropic,repeat_enable;
uniform bool before=false;
varying vec3 world;
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 vec2 p=world.xz;
 float dist=length(VERTEX);
 vec3 a=texture(grass,p).rgb;
 vec3 b=texture(grass,p*.713+vec2(17.32,8.19)).rgb;
 float patch=sin(p.x*.39+sin(p.y*.17))*sin(p.y*.24)*.025;
 float mow=sin(p.y*3.14159265/5.0);
 float strip=smoothstep(-.12,.12,mow)*2.0-1.0;
 vec3 c=vec3(.10,.185,.043)*(1.0+patch);
 // Compatibility's LDR target samples source_color in sRGB; Forward+ is linear.
 float mean=OUTPUT_IS_SRGB?.356:.105;
 c*=clamp((a.g*.75+b.g*.25)/mean,.62,1.45);
 vec3 to_eye=normalize(CAMERA_POSITION_WORLD-world);
 c*=1.+strip*.07*to_eye.z;
 ALBEDO=c;
 ROUGHNESS=.91;SPECULAR=.22;
 vec3 norm=texture(grass_normal,p).rgb;
 vec2 n=(norm.rg*2.-1.)*(1.-smoothstep(7.,24.,dist))*.24;
 n.y+=strip*.025;
 NORMAL=normalize((VIEW_MATRIX*vec4(normalize(vec3(n.x,1.,n.y)),0.)).xyz);
}
