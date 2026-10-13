extends RefCounted
const Curves=preload("res://scripts/motion_curves.gd")
var bone_ids:Dictionary={}
func weight(action:Dictionary)->float:
	if float(action.get("tackle_body_weight",-1))>=0:return float(action.tackle_body_weight)
	var t:float=float(action.get("normalized_time",0))
	return smoothstep(0,.40,t)*(1.0-smoothstep(.65,1.0,t))
func shift(action:Dictionary,state:Dictionary,root:Vector3)->Vector3:
	var forward:Vector3=state.get("forward",Vector3.FORWARD)
	var reach:Vector3=action.world_target-root;reach.y=0
	var right:Vector3=Vector3(-forward.z,0,forward.x)
	return (reach.limit_length(.08)-right*float(action.side)*.045+Vector3.DOWN*.04)*weight(action)
func sample_body(sk:Skeleton3D,action:Dictionary)->void:
	var t:float=float(action.get("normalized_time",0))
	var w:float=weight(action)
	var side:float=float(action.side)
	rotate(sk,"hips",Vector3(-.025,side*.06,side*.035)*w)
	rotate(sk,"spine",Vector3(-.065,-side*.045,-side*.03)*w)
	rotate(sk,"chest",Vector3(-.045,-side*.05,0)*w)
	rotate(sk,"head",Vector3(.065,side*.025,0)*w)
	for suffix in ["L","R"]:
		var sign_side:float=-1.0 if suffix=="L" else 1.0
		rotate(sk,"upper_arm."+suffix,Vector3(.16 if sign_side!=side else -.08,0,sign_side*.25)*w)
		rotate(sk,"forearm."+suffix,Vector3(.35 if sign_side!=side else .20,0,0)*w)
	sk.force_update_all_bone_transforms()
func rotate(sk:Skeleton3D,name:String,angles:Vector3)->void:
	if not bone_ids.has(name):bone_ids[name]=sk.find_bone(name)
	var id:int=int(bone_ids[name])
	if id>=0:sk.set_bone_pose_rotation(id,Quaternion.from_euler(angles)*sk.get_bone_pose_rotation(id))
func support_target(action:Dictionary,root:Vector3,ground:float)->Vector3:
	var start:Vector3=action.get("support_origin",root)
	var drift:Vector3=root-(action.get("root_origin",root) as Vector3);drift.y=0
	var t:float=float(action.get("normalized_time",0))
	# The support step follows root travel before impact, then releases continuously.
	var target:Vector3=start+drift*smoothstep(0,.48,t)
	target.y=ground+.006
	return target
