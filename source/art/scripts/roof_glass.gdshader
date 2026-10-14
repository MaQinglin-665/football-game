shader_type spatial;
render_mode blend_mix,cull_disabled,depth_draw_never,unshaded;
// Thin central glazing transmits the actual sky. Outer canopy is a separate opaque mesh.
// Neutral transmission avoids per-triangle light accumulation on huge transparent wedges.
void fragment(){
 float fresnel=pow(1.0-clamp(abs(dot(normalize(NORMAL),normalize(VIEW))),0.,1.),5.);
 ALBEDO=mix(vec3(.12,.17,.20),vec3(.28,.34,.38),fresnel);
 ALPHA=.028+fresnel*.06;
}
