extends RefCounted
## Sample once after the base pose and before leg support IK. No root motion.
static func rotate(avatar,name:String,v:Vector3)->void:
	var id:int=avatar.cached_bone_id(name)
	if id>=0:avatar.skeleton.set_bone_pose_rotation(id,Quaternion.from_euler(v)*avatar.skeleton.get_bone_pose_rotation(id))

static func apply(avatar,state:Dictionary,action:Dictionary)->void:
	var actor=avatar.get_parent()
	if not state.get("interaction",{}).is_empty():return
	var kind:String=String(action.get("kind",""))
	if actor.is_human:
		var view_yaw:float=actor.rotation.y
		var hips_yaw:float=avatar.visual.global_rotation.y
		var look:float=angle_difference(hips_yaw,view_yaw)
		var chest:float=clampf(look*.38,-.55,.55)
		# Camera stays independent when a fast mouse sweep exceeds anatomy.
		rotate(avatar,"chest",Vector3(0,chest,0))
		rotate(avatar,"head",Vector3(clampf(actor.head.rotation.x*.35,-.30,.25),clampf(look-chest,-1.05,1.05),0))
		if actor.call_weight>.001:
			avatar.ai_body_presentation._raise_call_arm(avatar,actor.call_weight)
	if kind in ["PASS","SHOT","TACKLE"]:return
	if actor.is_human and kind in ["","CARRY","CLOSE","SHIELD","TURN","SPRINT"]:
		var velocity:Vector3=state.get("velocity",Vector3.ZERO)
		var speed:float=Vector2(velocity.x,velocity.z).length()
		var run:float=smoothstep(1.6,5.2,speed)
		var forward:Vector3=state.get("forward",Vector3.FORWARD)
		var right:Vector3=Vector3(-forward.z,0,forward.x)
		var acceleration:Vector3=state.get("acceleration",Vector3.ZERO)
		var lateral:float=clampf(acceleration.dot(right)/12.,-1.,1.)
		# Small upper-body counterbalance; the motor and final leg IK are untouched.
		rotate(avatar,"chest",Vector3(-.025*run,-.035*lateral,-.018*lateral))
		for suffix in ["L","R"]:
			var side:float=-1. if suffix=="L" else 1.
			var wave:float=-side*sin(TAU*avatar._phase-.16)
			rotate(avatar,"upper_arm."+suffix,Vector3(wave*.10*run,0,side*.025*run))
			rotate(avatar,"forearm."+suffix,Vector3((.10+.045*wave)*run,0,0))
	if kind=="RECEIVE":
		var t:float=float(action.get("normalized_time",0))
		var absorb:float=smoothstep(0,.45,t)*(1-smoothstep(.65,1,t))*lerpf(.6,1.5,clampf(float(action.get("receive_speed",0))/14.0,0,1))
		rotate(avatar,"spine",Vector3(-.045,0,0)*absorb)
		rotate(avatar,"upper_arm.L",Vector3(0,0,-.10)*absorb)
		rotate(avatar,"upper_arm.R",Vector3(0,0,.10)*absorb)
