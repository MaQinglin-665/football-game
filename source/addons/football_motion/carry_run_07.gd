extends RefCounted
## Additive medium/high-speed carrying body pose; released feet stay authoritative.
const ARM_BONES:=["upper_arm.L","forearm.L","hand.L","upper_arm.R","forearm.R","hand.R"]
const SAVED_BONES:=["hips","spine","chest","neck","thigh.L","shin.L","foot.L","toe.L","thigh.R","shin.R","foot.R","toe.R","upper_arm.L","forearm.L","hand.L","upper_arm.R","forearm.R","hand.R"]
var ids:Dictionary={}
var _restore:Dictionary={}
var _eligible:=false
var _weight:=0.0
var _speed:=0.0
var _drive:=0.0
var _brake:=0.0
var _pitch:=0.0
var _sprint:=0.0
var _push:=0.0
var _debug:Dictionary={}

func restore(avatar)->void:
	if _restore.is_empty():return
	var sk:Skeleton3D=avatar.skeleton
	sk.set_bone_pose_position(int(ids.hips),_restore.hip_position)
	for id in _restore.rotations:sk.set_bone_pose_rotation(int(id),_restore.rotations[id])
	_restore.clear()

func update(delta:float,state:Dictionary,action:Dictionary)->void:
	var velocity:Vector3=state.get("velocity",Vector3.ZERO)
	_speed=Vector2(velocity.x,velocity.z).length()
	var tier:String=String(state.get("control_tier","FREE")).to_upper()
	var kind:String=String(action.get("kind","")).to_upper()
	var surface:String=String(action.get("surface","")).to_upper()
	var interaction:Dictionary=state.get("interaction",{})
	var interaction_busy:bool=bool(interaction.get("mobility_busy",false)) or bool(interaction.get("airborne",false)) or float(interaction.get("crouch",0.0))>0 or float(interaction.get("header_weight",0.0))>0
	_eligible=not interaction_busy and bool(state.get("grounded",true)) and tier in ["CLOSE","CRUISE","KNOCK_CHASE"] and (action.is_empty() or kind in ["CARRY","CLOSE","TURN","SPRINT"] and surface in ["INSIDE","OUTSIDE","INSTEP"])
	# The released low-control boundary remains exact, even while scalar states fade.
	_weight=smoothstep(2.10,3.10,_speed) if _eligible else 0.0
	if delta<=0:return
	var forward:Vector3=state.get("forward",Vector3.FORWARD)
	forward.y=0
	if forward.length_squared()<.00001:forward=Vector3.FORWARD
	forward=forward.normalized()
	var acceleration:Vector3=state.get("acceleration",Vector3.ZERO)
	var longitudinal:float=clampf(acceleration.dot(forward)/9.0,-1,1)
	var response:float=1.0-exp(-8.0*delta)
	_drive=lerpf(_drive,maxf(0,longitudinal) if _eligible else 0.0,response)
	_brake=lerpf(_brake,maxf(0,-longitudinal) if _eligible else 0.0,response)
	_sprint=lerpf(_sprint,smoothstep(4.4,6.4,_speed) if _eligible else 0.0,response)
	var target:float=lerpf(-.060,-.100,_sprint)-.030*_drive+.040*_brake if _eligible else 0.0
	_pitch=lerpf(_pitch,clampf(target,-.140,.040),response)
	if _weight<=0:_push=0.0

func _sample_arms(avatar,clip:String)->Dictionary:
	# Existing licensed Jog/Sprint donor rotations, existing gait phase and clock.
	var frames:Array=avatar._body.loops[clip].frames
	var value:float=fposmod(float(avatar._phase),1.0)*frames.size()
	var index:int=int(floor(value))
	var a:Dictionary=frames[index%frames.size()]
	var b:Dictionary=frames[(index+1)%frames.size()]
	var result:Dictionary={}
	for name in ARM_BONES:result[name]=(a[name] as Quaternion).slerp(b[name],value-index)
	return result

func apply(avatar,delta:float,state:Dictionary)->void:
	_debug={"revision":"carry_run_07","eligible":_eligible,"weight":_weight,"speed_mps":_speed,"bone_writes":false}
	if _weight<=0 or not String(avatar._base_clip) in ["DribbleJog","Run"]:return
	var sk:Skeleton3D=avatar.skeleton
	if ids.is_empty():
		for name in SAVED_BONES+["head"]:ids[name]=sk.find_bone(name)
		var missing:=false
		for name in ids:
			if int(ids[name])<0:missing=true
		if missing:ids.clear();return
	var forward:Vector3=sk.global_basis.inverse()*(state.get("forward",Vector3.FORWARD) as Vector3)
	forward.y=0
	if forward.length_squared()<.00001:forward=Vector3.FORWARD
	forward=forward.normalized()
	var hip_goal:Vector3=sk.get_bone_pose_position(int(ids.hips))
	var head_goal:Vector3=sk.get_bone_global_pose(int(ids.head)).origin
	var goals:Dictionary={}
	var rotations:Dictionary={}
	for name in SAVED_BONES:rotations[int(ids[name])]=sk.get_bone_pose_rotation(int(ids[name]))
	var push_target:=0.0
	var support:Dictionary={}
	for side in ["L","R"]:
		var foot:Transform3D=sk.get_bone_global_pose(int(ids["foot."+side]))
		goals[side]=foot
		var plant:Dictionary=avatar._plants.get(side,{})
		var world_rotation:Quaternion=sk.global_basis.get_rotation_quaternion()*foot.basis.get_rotation_quaternion()
		var sole_y:float=sk.to_global(foot.origin).y+avatar._minimum_offset(side,world_rotation)
		var planted:bool=not plant.is_empty() and not bool(plant.get("releasing",false)) and sole_y-float(avatar._ground_y)<=.012
		var thigh:Vector3=sk.get_bone_global_pose(int(ids["thigh."+side])).origin
		var leg_length:float=sk.get_bone_rest(int(ids["shin."+side])).origin.length()+sk.get_bone_rest(int(ids["foot."+side])).origin.length()
		var extension:float=clampf((thigh-foot.origin).dot(forward)/maxf(.001,leg_length*.35),0,1) if planted else 0.0
		push_target=maxf(push_target,extension)
		support[side]={"actual_planted_near_ground":planted,"rear_support_extension":extension}
	if delta>0:_push=lerpf(_push,push_target,1.0-exp(-8.0*delta))
	var pitch:float=_pitch*_weight
	var offset:Vector3=(forward*(.020+.015*_sprint+.012*_drive+.012*_push-.018*_brake)+Vector3.DOWN*(.006+.010*_drive+.006*_sprint))*_weight
	var parent:int=sk.get_bone_parent(int(ids.hips))
	var parent_basis:Basis=sk.get_bone_global_pose(parent).basis if parent>=0 else Basis.IDENTITY
	var local_offset:Vector3=parent_basis.inverse()*offset
	var jog:Dictionary=_sample_arms(avatar,"Jog_Fwd_Loop")
	var sprint:Dictionary=_sample_arms(avatar,"Sprint_Loop")
	var arm_mix:float=.20+.80*_sprint
	var accepted:=false
	var strength:=1.0
	var head_delta:=Vector3.ZERO
	for attempt in 4:
		sk.set_bone_pose_position(int(ids.hips),hip_goal+local_offset*strength)
		for name in ["hips","spine","chest","neck"]:
			var fraction:float=.60 if name=="hips" else .25 if name=="spine" else .15 if name=="chest" else -.95
			sk.set_bone_pose_rotation(int(ids[name]),Quaternion(Vector3.RIGHT,pitch*fraction*strength)*(rotations[int(ids[name])] as Quaternion))
		for name in ARM_BONES:
			if not avatar.get_parent().is_human:continue # Shared AI arm chain remains authoritative during carry.
			var target:Quaternion=(jog[name] as Quaternion).slerp(sprint[name],arm_mix)
			if name.begins_with("upper_arm"):
				var side_sign:float=1.0 if name.ends_with("L") else -1.0
				target=Quaternion(Vector3.FORWARD,side_sign*(absf(float(avatar._body.bank))*.20+absf(float(avatar._body.contact_balance))*.20))*target
			# Chest/hips own the tilt. Arms change gait character, not phase rate.
			sk.set_bone_pose_rotation(int(ids[name]),(rotations[int(ids[name])] as Quaternion).slerp(target,_weight*strength))
		head_delta=sk.get_bone_global_pose(int(ids.head)).origin-head_goal
		# Existing eye origin follows the head. Bound additional translation;
		# camera rotation/FOV/input, foot phase and ankle parameters stay untouched.
		var head_scale:float=minf(1.0,minf(.060/maxf(head_delta.length(),.000001),.025/maxf(absf(head_delta.y),.000001)))
		var safe:bool=head_scale>=1.0
		for side in ["L","R"]:
			var thigh:Vector3=sk.get_bone_global_pose(int(ids["thigh."+side])).origin
			var a:float=sk.get_bone_rest(int(ids["shin."+side])).origin.length()
			var b:float=sk.get_bone_rest(int(ids["foot."+side])).origin.length()
			var distance:float=thigh.distance_to((goals[side] as Transform3D).origin)
			if distance>a+b-.0001 or distance<absf(a-b)+.025:safe=false
		if safe:
			accepted=true
			for side in ["L","R"]:
				var goal:Transform3D=goals[side]
				if not avatar._solve_leg(side,goal.origin,goal.basis.get_rotation_quaternion(),forward):accepted=false
				sk.set_bone_pose_rotation(int(ids["toe."+side]),rotations[int(ids["toe."+side])])
			for side in ["L","R"]:
				var actual:Transform3D=sk.get_bone_global_pose(int(ids["foot."+side]))
				var goal:Transform3D=goals[side]
				var q:Quaternion=actual.basis.get_rotation_quaternion()
				var original:Quaternion=goal.basis.get_rotation_quaternion()
				if q.dot(original)<0:original=Quaternion(-original.x,-original.y,-original.z,-original.w)
				if actual.origin.distance_to(goal.origin)>.00001 or maxf(maxf(absf(q.x-original.x),absf(q.y-original.y)),maxf(absf(q.z-original.z),absf(q.w-original.w)))>.00001:accepted=false
			if accepted:break
		sk.set_bone_pose_position(int(ids.hips),hip_goal)
		for id in rotations:sk.set_bone_pose_rotation(int(id),rotations[id])
		# Camera-follow budget changes continuously, rather than halving at a
		# speed threshold. An IK failure retains its separate geometric fallback.
		strength*=head_scale*.99 if head_scale<1.0 else .5
	if accepted:_restore={"hip_position":hip_goal,"rotations":rotations}
	_debug.merge({"bone_writes":accepted,"accepted_strength":strength if accepted else 0.0,"added_pitch_rad":pitch*strength if accepted else 0.0,"pelvis_offset_m":offset*strength if accepted else Vector3.ZERO,"head_offset_m":head_delta if accepted else Vector3.ZERO,"jog_sprint_blend":arm_mix,"speed_sprint_blend":_sprint,"acceleration_drive":_drive,"braking":_brake,"push_phase":_push,"support":support},true)

func debug()->Dictionary:return _debug.duplicate(true)
