extends RefCounted
# Visible balance only; never writes roots, ball, camera or input.
var load:=Vector3.ZERO
var cue:=Vector3.ZERO
func step(actor:Node3D,delta:float,owned:bool)->void:
	var velocity:Vector3=actor.velocity;velocity.y=0
	var forward:Vector3=actor.body_facing
	var right:=Vector3(-forward.z,0,forward.x)
	var accel:Vector3=actor.motion_acceleration;accel.y=0
	var allowed:bool=owned and actor.position.y<.08 and actor.foot.kind in ["","CARRY","CLOSE","SHIELD","TURN","SPRINT"] and not actor.foot.touch_plan.has("cut_style")
	var target:=Vector3.ZERO
	if allowed:
		var active:float=smoothstep(.05,.45,velocity.length())
		var brake:float=maxf(0,-accel.dot(velocity.normalized()))/10.0 if velocity.length()>.1 else 0.0
		target=Vector3(clampf(accel.dot(forward)/9.0,-1,1),clampf(accel.dot(right)/9.0,-1,1),clampf(brake,0,1))*active
	load=load.lerp(target,1-exp(-14.0*maxf(0,delta)))
	cue=(right*load.y*.14+forward*load.x*.08) if allowed else Vector3.ZERO
static func rotate(avatar,name:String,v:Vector3)->void:
	var id:int=avatar.cached_bone_id(name)
	if id>=0:avatar.skeleton.set_bone_pose_rotation(id,Quaternion.from_euler(v)*avatar.skeleton.get_bone_pose_rotation(id))
static func apply(avatar,value:Vector3)->void:
	rotate(avatar,"hips",Vector3(-value.x*.025,0,-value.y*.035))
	rotate(avatar,"chest",Vector3(-value.x*.045-value.z*.035,-value.y*.09,-value.y*.075))
	rotate(avatar,"upper_arm.L",Vector3(value.z*.06,0,-maxf(0,value.y)*.13-value.z*.04))
	rotate(avatar,"upper_arm.R",Vector3(value.z*.06,0,maxf(0,-value.y)*.13+value.z*.04))
