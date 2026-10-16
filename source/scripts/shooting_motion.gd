extends RefCounted
const Curves=preload("res://scripts/motion_curves.gd")
## Optional SHOT layer for the existing 32-bone rig. Visual only, no ball forces.
## Body/arms first, fixed-length active/support IK last. No time at delta=0.
var sequence := -1
var support_anchor := Vector3.ZERO
var support_rotation := Quaternion.IDENTITY
var last_ankle := Vector3.ZERO # Avatar local, independent of the shifting visual root.
var last_rotation := Quaternion.IDENTITY
var shift := Vector3.ZERO
var active_contact: Dictionary = {}
var support_contact: Dictionary = {}
var debug: Dictionary = {}
var support_goal := Vector3.ZERO
var support_from := Vector3.ZERO
var support_age := 0.0
var support_planted := true
var support_releasing := false

func reset() -> void:
	sequence = -1
	shift = Vector3.ZERO
	active_contact.clear()
	support_contact.clear()
	debug.clear()

func prepare(avatar: Node3D, action: Dictionary, state: Dictionary = {}) -> void:
	if sequence==int(action.get("sequence",0)): return
	sequence = int(action.get("sequence",0))
	shift = Vector3.ZERO
	var side := int(action.side)
	var sk: Skeleton3D = avatar.skeleton
	var active := avatar.side_suffix(side) as String
	var support := avatar.side_suffix(-side) as String
	var a := sk.global_transform*sk.get_bone_global_pose(sk.find_bone("foot."+active))
	var b := sk.global_transform*sk.get_bone_global_pose(sk.find_bone("foot."+support))
	last_ankle = avatar.to_local(a.origin)
	last_rotation = a.basis.get_rotation_quaternion()
	support_rotation = b.basis.get_rotation_quaternion()
	var socket: Vector3 = sk.get_bone_global_rest(sk.find_bone("contact_sole."+support)).origin-sk.get_bone_global_rest(sk.find_bone("foot."+support)).origin
	support_anchor = b.origin+support_rotation*socket
	support_from = support_anchor
	support_goal = support_anchor
	support_age = 0
	support_releasing = false
	var velocity: Vector3 = state.get("velocity",Vector3.ZERO)
	velocity.y = 0
	support_planted = velocity.length()<=.4
	if not support_planted:
		# A moving carry/chase shot plants during its windup with a finite
		# step. Even an ordinary dribble can still be braking below2.4m/s;
		# locking that old rear footprint overextends the support leg.
		var forward: Vector3 = state.get("forward",Vector3.FORWARD)
		forward.y = 0
		forward = forward.normalized()
		var right := Vector3(-forward.z,0,forward.x)
		var ankle := avatar.global_position+velocity*.16+right*(-side*.145)-forward*.025
		support_rotation = Quaternion(Vector3.UP,atan2(-forward.x,-forward.z))
		support_goal = ankle+support_rotation*socket

func rotate_bone(sk: Skeleton3D, name: String, rotation: Vector3) -> void:
	var id := sk.find_bone(name)
	if id>=0: sk.set_bone_pose_rotation(id,Quaternion.from_euler(rotation)*sk.get_bone_pose_rotation(id))

func sample_body(sk: Skeleton3D, action: Dictionary) -> void:
	# May also be called at the animation task's action_pose_sampled hook.
	# The caller must sample the base pose first; this method owns no clock.
	var side := int(action.side)
	var suffix := "L" if side<=0 else "R"
	var full := String(action.get("shot_style","compact"))=="full"
	var t := clampf(float(action.get("normalized_time",0)),0,1)
	var load := Curves.ramp(0,.30,t)
	var strike := Curves.ramp(.30,.58,t)
	var release := 1.0-Curves.ramp(.65,1,t)
	var balance := load*release
	var chest_strike:float=Curves.ramp(.34,.66,t)
	var power := clampf(float(action.get("power",.3)),0,1)
	var amplitude := (1.20 if full else .35)*(.75+.25*power)
	# Counterrotation unwinds from the loaded hip through spine/chest; arms
	# spread independently to balance the grounded opposite foot.
	rotate_bone(sk,"hips",Vector3(-.035*balance*amplitude,side*(-.12+.26*strike)*balance*amplitude,0))
	rotate_bone(sk,"spine",Vector3(-.16*balance*amplitude,side*(.08-.18*chest_strike)*balance*amplitude,0))
	rotate_bone(sk,"chest",Vector3(-.09*balance*amplitude,-side*lerpf(.08,-.07,chest_strike)*balance*amplitude,0))
	for arm in ["L","R"]:
		var sign_arm := -1.0 if arm=="L" else 1.0
		var counter := -1.0 if arm==suffix else 1.0
		rotate_bone(sk,"clavicle."+arm,Vector3(0,counter*.10*balance*amplitude,sign_arm*.08*balance*amplitude))
		rotate_bone(sk,"upper_arm."+arm,Vector3(counter*(.18-.34*strike)*balance*amplitude,0,sign_arm*(.64 if arm!=suffix else .23)*balance*amplitude))
		rotate_bone(sk,"forearm."+arm,Vector3(counter*.22*balance*amplitude,0,0))
	rotate_bone(sk,"head",Vector3(.08*balance*amplitude,side*.025*balance,0))
	sk.force_update_all_bone_transforms()

func apply(avatar: Node3D, delta: float, state: Dictionary, action: Dictionary, body_already_sampled := false) -> void:
	var dt := maxf(delta,0)
	var sk: Skeleton3D = avatar.skeleton
	var side := int(action.side)
	var suffix := avatar.side_suffix(side) as String
	var opposite := avatar.side_suffix(-side) as String
	var full := String(action.get("shot_style","compact"))=="full"
	var t := clampf(float(action.get("normalized_time",0)),0,1)
	var load := smoothstep(0,.30,t)
	var release := 1.0-smoothstep(.65,1,t)
	if not body_already_sampled: sample_body(sk,action)
	var forward: Vector3 = action.get("direction",state.get("forward",Vector3.FORWARD))
	forward.y = 0
	forward = forward.normalized()
	var rotation := Quaternion(Vector3.UP,atan2(-forward.x,-forward.z))*Quaternion(Vector3.RIGHT,-.03)
	var surface:String=String(action.get("surface","INSTEP"))
	if surface in ["INSIDE","OUTSIDE"]:
		rotation=rotation*Quaternion(Vector3.UP,float(side)*(-1.05 if surface=="INSIDE" else .55))
	var foot_id := sk.find_bone("foot."+suffix)
	var socket_name:String="contact_"+String(avatar.SURFACES.get(surface,"instep"))+"."+suffix
	var socket_id := sk.find_bone(socket_name)
	var offset := sk.get_bone_global_rest(socket_id).origin-sk.get_bone_global_rest(foot_id).origin
	var maximum := sk.get_bone_rest(sk.find_bone("shin."+suffix)).origin.length()+sk.get_bone_rest(foot_id).origin.length()-.012
	var contact_goal: Vector3 = action.get("strike_target",action.world_target)
	var ankle_goal := contact_goal-rotation*offset
	ankle_goal.y = maxf(ankle_goal.y,avatar.global_position.y+.005-float(avatar._minimum_offset(suffix,rotation)))
	var hip := sk.to_global(sk.get_bone_global_pose(sk.find_bone("thigh."+suffix)).origin)
	var vector := ankle_goal-hip
	var right := Vector3(-forward.z,0,forward.x)
	var lateral := vector.dot(right)
	var wanted_side := clampf(lateral*.12,-.035,.035)
	var down := .12 if full else .075
	var allowed := sqrt(maxf(0,maximum*maximum-pow(vector.y+down,2)-pow(lateral-wanted_side,2)))
	var transfer := clampf(vector.dot(forward)-allowed+.025,.055,.24)
	var wanted := (forward*transfer+right*wanted_side+Vector3.DOWN*down)*load*release
	shift = shift.move_toward(wanted,4.5*dt)
	avatar.visual.position = avatar.global_basis.inverse()*shift
	sk.force_update_all_bone_transforms()
	# A single support anchor is retained through this strike. Its exact
	# footprint is floor corrected using the existing boot support cloud.
	var sole_offset: Vector3 = sk.get_bone_global_rest(sk.find_bone("contact_sole."+opposite)).origin-sk.get_bone_global_rest(sk.find_bone("foot."+opposite)).origin
	var floor_height := avatar.global_position.y+.005-float(avatar._minimum_offset(opposite,support_rotation))+(support_rotation*sole_offset).y
	support_goal.y = floor_height
	if not support_planted:
		support_age += dt
		var step := clampf(support_age/.12,0,1)
		var step_target := support_goal+Vector3.UP*sin(PI*step)*.045
		support_anchor = support_anchor.move_toward(step_target,9.0*dt)
		if step>=1 and support_anchor.distance_to(support_goal)<.025:
			support_planted = true
	else: support_anchor.y = floor_height
	var support_ankle := sk.to_local(support_anchor-support_rotation*sole_offset)
	var support_ok: bool = avatar._solve_leg(opposite,support_ankle,sk.global_basis.get_rotation_quaternion().inverse()*support_rotation,sk.global_basis.inverse()*forward)
	if not support_ok:
		# Keep real fixed lengths and the mesh above the ground even after
		# a fast follow-through carries the body off this footprint. A new
		# step/release is visible and remains invalid until it actually lands.
		var support_hip := sk.get_bone_global_pose(sk.find_bone("thigh."+opposite)).origin
		var support_maximum := sk.get_bone_rest(sk.find_bone("shin."+opposite)).origin.length()+sk.get_bone_rest(sk.find_bone("foot."+opposite)).origin.length()-.012
		var projected_support := support_hip+(support_ankle-support_hip).limit_length(support_maximum)
		avatar._solve_leg(opposite,projected_support,sk.global_basis.get_rotation_quaternion().inverse()*support_rotation,sk.global_basis.inverse()*forward)
		if support_planted and (bool(action.get("contact_confirmed",false)) or String(action.phase)=="RECOVER"):
			support_releasing = true
			support_planted = false
			support_age = 0
			var ankle := avatar.global_position+right*(-side*.145)+forward*.08
			support_goal = ankle+support_rotation*sole_offset
	avatar._correct_floor(opposite,forward)
	var support_pose := sk.global_transform*sk.get_bone_global_pose(sk.find_bone("contact_sole."+opposite))
	support_contact = {"valid":support_planted and support_ok and support_pose.origin.distance_to(support_anchor)<.035,"point":support_pose.origin,"target":support_anchor,"surface":"SOLE","planted":support_planted,"releasing":support_releasing,"step_age":support_age}
	# The foot pursues a real target with finite translation/rotation speed.
	# Unreachable targets get the nearest fixed-length pose, never valid=true.
	var target: Vector3 = action.world_target
	var desired_ankle := target-rotation*offset
	desired_ankle.y = maxf(desired_ankle.y,avatar.global_position.y+.005-float(avatar._minimum_offset(suffix,rotation)))
	var wanted_local := avatar.to_local(desired_ankle)
	var previous_local := last_ankle
	last_ankle = last_ankle.move_toward(wanted_local,(12.0 if full else 9.0)*dt)
	var angle := last_rotation.angle_to(rotation)
	if angle>.000001: last_rotation = last_rotation.slerp(rotation,minf(1,18.0*dt/angle))
	var actual_ankle := sk.to_local(avatar.to_global(last_ankle))
	var active_hip := sk.get_bone_global_pose(sk.find_bone("thigh."+suffix)).origin
	var radial := actual_ankle-active_hip
	var projected := active_hip+radial.limit_length(maximum)
	var leg_ok: bool = avatar._solve_leg(suffix,projected,sk.global_basis.get_rotation_quaternion().inverse()*last_rotation,sk.global_basis.inverse()*forward)
	avatar._correct_floor(suffix,forward)
	var socket_pose := sk.get_bone_global_pose(socket_id)
	var point := sk.to_global(socket_pose.origin)
	var error := point.distance_to(target)
	avatar._unreachable = not leg_ok or error>.035
	avatar._reach_error = error
	var source_normal: Vector3 = avatar._socket_normals.get(socket_name,Vector3.FORWARD)
	var foot_pose := sk.get_bone_global_pose(foot_id)
	active_contact = {"valid":not avatar._unreachable,"point":point,"normal":(sk.global_basis*socket_pose.basis*source_normal).normalized(),"boot_center":sk.to_global(foot_pose.origin+foot_pose.basis*Vector3(0,-.050,-.080)),"surface":surface,"reach_error":error}
	# Record the actual ankle after projection/floor correction, not the request.
	last_ankle = avatar.to_local(sk.to_global(foot_pose.origin))
	last_rotation = (sk.global_basis*foot_pose.basis).get_rotation_quaternion()
	debug = {"sequence":sequence,"style":"full" if full else "compact","normalized_time":t,"shift":shift,"support":support_contact.duplicate(),"contact":active_contact.duplicate(),"ankle_step_m":last_ankle.distance_to(previous_local),"delta":dt,"body_sampled_by_hook":body_already_sampled,"body_amplitude":(1.0 if full else .25)*(.75+.25*clampf(float(action.get("power",.3)),0,1))*load*release}
