extends RefCounted
# Pre-support articulation; the original active-foot and plant IK remain authoritative.
const Curves=preload("res://scripts/motion_curves.gd")
static func apply(avatar,action:Dictionary)->void:
 if action.get("kind","")!="PASS":return
 var sk:Skeleton3D=avatar.skeleton
 var t:float=clampf(float(action.get("normalized_time",0)),0,1)
 var side:float=float(action.get("side",1))
 var power:float=clampf(float(action.get("power",.3)),0,1)
 var actor=avatar.get_parent()
 var loft:bool=bool(actor.foot.pass_choice.get("loft",false))
 var heel:bool=action.get("surface","")=="HEEL"
 var envelope:float=Curves.envelope(t,.20,.66)
 var hip_stroke:float=Curves.ramp(.16,.55,t)
 var chest_stroke:float=Curves.ramp(.23,.63,t)
 var reach:float=lerpf(.70,1.12,power)*(.90 if heel else 1.15 if loft else 1.)
 var turn:float=side*lerpf(-.10,.16,hip_stroke)*envelope*reach
 for name in ["hips","spine","chest","head","clavicle.L","clavicle.R","upper_arm.L","upper_arm.R","forearm.L","forearm.R","hand.L","hand.R"]:
  var id:int=avatar.cached_bone_id(name)
  if id<0:continue
  var change:Vector3=Vector3.ZERO
  if name=="hips":change=Vector3(-.045 if heel else -.025,turn/maxf(envelope,.001),-side*.022)*envelope
  elif name=="spine":change=Vector3(lerpf(.025,-.07,chest_stroke) if loft else -.04,-side*lerpf(-.08,.10,chest_stroke)*reach,side*.012)*envelope
  elif name=="chest":change=Vector3(-.025*chest_stroke,-side*lerpf(-.035,.05,chest_stroke)*reach,0)*envelope
  elif name=="head":change=Vector3(.018,side*.025,0)*envelope
  else:
   var sign_side:float=-1. if name.ends_with("L") else 1.
   var support_arm:bool=sign_side!=side
   if name.begins_with("clavicle"):change=Vector3(0,-side*.04,sign_side*.045)*envelope*reach
   elif name.begins_with("upper_arm"):
    var opening:float=(.38+.12*power+.10*float(loft)) if support_arm else .16
    change=Vector3(-sign_side*side*lerpf(.18,-.23,chest_stroke),side*.03,sign_side*opening)*envelope*reach
   elif name.begins_with("forearm"):change=Vector3(.16+.12*(1.-chest_stroke),0,0)*envelope
   else:change=Vector3(-.025,0,-sign_side*.025)*envelope
  sk.set_bone_pose_rotation(id,Quaternion.from_euler(change)*sk.get_bone_pose_rotation(id))
