shader_type sky;
uniform sampler2D panorama:source_color,filter_linear_mipmap,repeat_enable;
uniform mat3 source_rotation=mat3(1.0);
uniform bool night=false;
void sky(){
 vec3 d=normalize(source_rotation*EYEDIR);
 vec2 uv=vec2(atan(d.x,d.z)/6.2831853+.5,acos(clamp(d.y,-1.,1.))/3.14159265);
 vec3 s=texture(panorama,uv).rgb;
 if(night){float cloud=clamp(dot(s,vec3(.2126,.7152,.0722))*.15,0.,.5);COLOR=mix(vec3(.027,.040,.074),vec3(.07,.095,.16),pow(1.-max(EYEDIR.y,0.),3.))+cloud*vec3(.018,.025,.045);}
 else{COLOR=pow(s/(s+vec3(.8)),vec3(.72));}
}
