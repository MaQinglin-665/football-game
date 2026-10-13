extends RefCounted
# C2 action envelopes, sampled exclusively from the existing foot-action clock.
static func ramp(a:float,b:float,t:float)->float:
 var u:float=clampf((t-a)/maxf(b-a,.0001),0.,1.)
 return u*u*u*(u*(u*6.-15.)+10.)
static func envelope(t:float,rise:float,fall:float)->float:
 return ramp(0.,rise,t)*(1.-ramp(fall,1.,t))
