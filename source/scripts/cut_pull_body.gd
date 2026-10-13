extends RefCounted
# One bounded balance overlay before the existing support/contact IK.
static func apply(avatar,action:Dictionary)->void:
	var kind:String=String(action.get("kind",""))
	var cut:bool=not String(action.get("cut_style","")).is_empty()
	if not cut and kind not in ["STOP","SETTLE","PULL"]:return
	var t:float=float(action.get("normalized_time",0))
	var weight:float=smoothstep(0,.35,t)*(1-smoothstep(.65,1,t))
	var side:float=float(action.get("side",1))
	var turn:float=side*(-.065 if action.get("surface","")=="INSIDE" else .055) if cut else 0.0
	var sk:Skeleton3D=avatar.skeleton
	for name in ["hips","chest","upper_arm.L","upper_arm.R"]:
		var id:int=avatar.cached_bone_id(name)
		var rotation:Vector3=Vector3.ZERO
		if name=="hips":rotation=Vector3(-.02,turn,side*.018)
		elif name=="chest":rotation=Vector3(.01,-turn*.5,0)
		else:rotation=Vector3(.015,0,-.09 if name.ends_with("L") else .09)
		if id>=0:sk.set_bone_pose_rotation(id,Quaternion.from_euler(rotation*weight)*sk.get_bone_pose_rotation(id))
