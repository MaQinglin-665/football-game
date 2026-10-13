shader_type spatial;
render_mode cull_disabled,diffuse_burley;
uniform vec4 color : source_color=vec4(.03,.14,.6,1);
uniform int kind=0;
uniform sampler2D fabric : hint_normal,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D digits : filter_linear_mipmap,repeat_disable;
uniform float number=7.;
varying vec3 rest;
void vertex(){rest=vec3(UV2.x,UV.y*.5,UV2.y);}
void fragment(){
 vec3 c=color.rgb;float rough=.83;
 if(kind==0){
   float side=smoothstep(.15,.20,abs(rest.x)); c=mix(c,c*.86,side*.35);
   float pin=1.-smoothstep(.001,.0025,abs(mod(rest.x+.018,.036)-.018));
   c=mix(c,c*1.04,pin*.15);
   float edge=max(fwidth(rest.y),.0005);
   float stripe=smoothstep(1.29-edge,1.29+edge,rest.y)*(1.-smoothstep(1.34-edge,1.34+edge,rest.y))*(1.-smoothstep(-.073,-.067,rest.z));
   c=mix(c,vec3(.64,.67,.65),stripe*.92);
   // Small original shield on the chest; no licensed team marks.
   vec2 badge=vec2((rest.x+.093)/.021,(rest.y-1.402)/.027);
   if(dot(badge,badge)<1.&&rest.z<-.08)c=vec3(.96,.77,.27);
   if(rest.z>.07&&rest.y>1.15&&rest.y<1.38&&abs(rest.x)<.07){
      vec2 q=vec2((rest.x+.07)/.14,(1.38-rest.y)/.23);
      float digit=number;
      if(number>=10.){digit=q.x<.5?floor(number/10.):mod(number,10.);q.x=fract(q.x*2.);}
      float ink=texture(digits,vec2((digit+q.x)/10.,q.y)).r;
      c=mix(c,vec3(.93,.94,.88),ink);
   }
 }else if(kind==1){rough=.68;}
 else if(kind==2){rough=.86;}
 else if(kind==3){rough=.38;}
 float fade=1.-smoothstep(.001,.006,max(length(dFdx(rest)),length(dFdy(rest))));
 if(kind==0||kind==2){
   vec3 n=texture(fabric,UV*2.5).rgb;
   NORMAL_MAP=mix(vec3(.5,.5,1.),n,.28*fade);NORMAL_MAP_DEPTH=.4;
 }
 ALBEDO=c;ROUGHNESS=rough;SPECULAR=kind==1?.22:.18;
}
