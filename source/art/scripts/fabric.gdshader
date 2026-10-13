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
   // Tailored side ventilation panels and a tonal woven chevron, filtered in screen space.
   float side=smoothstep(.135,.172,abs(rest.x))*(1.-smoothstep(.21,.25,abs(rest.x)));
   c=mix(c,c*.48,side*.8);
   float weave=abs(fract((rest.y+abs(rest.x)*.65)*35.)-.5);
   float feather=max(fwidth(rest.y)*35.,.08);
   float jacquard=1.-smoothstep(.12,.12+feather,weave);
   c*=1.+jacquard*.022;
   float edge=max(fwidth(rest.y),.0005);
   float chest_y=rest.y+abs(rest.x)*.20;
   float stripe=smoothstep(1.347-edge,1.347+edge,chest_y)*(1.-smoothstep(1.354-edge,1.354+edge,chest_y))*(1.-smoothstep(-.073,-.067,rest.z));
   c=mix(c,vec3(.80,.83,.81),stripe*.75);
   // Original shield: border, two fields and a central stripe; no commercial club logo.
   vec2 badge=vec2((rest.x+.093)/.019,(rest.y-1.403)/.026);
   float shield=max(abs(badge.x),-badge.y+abs(badge.x)*.50);
   if(shield<1.&&badge.y<1.&&rest.z<-.08){
     c=vec3(.78,.68,.38);
     if(shield<.78&&badge.y<.78)c=abs(badge.x)<.13?vec3(.86,.87,.81):color.rgb*.35;
   }
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
