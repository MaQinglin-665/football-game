extends SceneTree
const AvatarScene := preload("res://addons/football_character/football_character.tscn")
const Pose := preload("res://scripts/integration_character_pose.gd")
const Foot := preload("res://scripts/foot_action.gd")
var evidence := ""
var checks: Array[Dictionary] = []
var cases: Array[Dictionary] = []
var rows: Array[Dictionary] = []

class FixtureActor extends Node3D:
	var avatar: Node3D
	var facing := Vector3.FORWARD
	var body_facing := Vector3.FORWARD
	var velocity := Vector3.ZERO
	var is_human := true
	var foot: FootballFootAction

class FixtureGame extends Node:
	var tuning: FootballControlTuning = preload("res://config/ball_control.tres")
	var ball: MatchFootball
	func can_foot_action(_actor: Node3D,_kind: String) -> bool:return true
	func is_restart_taker(_actor: Node3D) -> bool:return false

func check(label: String, ok: bool, details: Variant = null) -> void:
	checks.append({"label":label,"passed":ok,"details":details})
	print("PASS " if ok else "FAIL ",label," ",details if details!=null else "")

func vec(v: Vector3) -> Array:return [v.x,v.y,v.z]

func _initialize() -> void:
	evidence = ProjectSettings.globalize_path("res://../verification")
	call_deferred("run")

func minimum_floor(avatar: Node3D,suffix: String) -> float:
	var sk: Skeleton3D = avatar.skeleton
	var pose := sk.global_transform*sk.get_bone_global_pose(sk.find_bone("foot."+suffix))
	return pose.origin.y+float(avatar._minimum_offset(suffix,pose.basis.get_rotation_quaternion()))-avatar.global_position.y

func geometry_case(spec: Dictionary) -> void:
	var game := FixtureGame.new()
	root.add_child(game)
	# This isolated fixture measures geometry only; no input, AI or new
	# physical contact/impulse is asserted here. Full World tests are separate.
	game.ball = MatchFootball.new()
	game.ball.profile = FootballPhysicsProfile.playable()
	var actor := FixtureActor.new()
	game.add_child(actor)
	actor.rotation.y = float(spec.get("yaw",0))
	actor.facing = -actor.global_basis.z
	actor.body_facing = actor.facing
	actor.avatar = AvatarScene.instantiate()
	actor.avatar.set_script(Pose)
	actor.add_child(actor.avatar)
	actor.avatar.setup(0,10,false)
	actor.avatar.update_pose(.008333333,{"velocity":Vector3.ZERO,"forward":actor.facing,"grounded":true,"locomotion":"idle"})
	game.ball.position = actor.to_global(Vector3(float(spec.get("x",0)),.111,-float(spec.z)))
	game.ball.velocity = actor.facing*float(spec.get("vz",0))
	actor.foot = Foot.new(actor,game)
	actor.foot.next_side = int(spec.get("side",1))
	actor.foot.request_semantic_kick({"action":"shoot_straight","direction":actor.facing,"power":float(spec.get("power",.7))})
	var max_length_error := 0.0
	var minimum := INF
	var max_zero_step := 0.0
	var max_step := 0.0
	var max_support_slide := 0.0
	var valid_contact_ticks := 0
	var invalid_support_ticks := 0
	var initial_support := Vector3.ZERO
	var peaks: Dictionary = {}
	var thigh_rotations: Array[float] = []
	var shin_rotations: Array[float] = []
	for tick in 64:
		var dt := 1.0/120
		var f: FootballFootAction = actor.foot
		f.elapsed += dt
		f.phase = f.Phase.PREPARE if f.elapsed<f.windup else f.Phase.CONTACT if f.elapsed<f.windup+f.window else f.Phase.RECOVER
		f.elapsed = minf(f.elapsed,f.windup+f.window+f.recovery)
		actor.avatar.set_foot_action(f.pose_request())
		actor.avatar.update_pose(dt,{"velocity":Vector3.ZERO,"forward":actor.facing,"grounded":true,"locomotion":"idle"})
		var sk: Skeleton3D = actor.avatar.skeleton
		var active := actor.avatar.get_foot_contact(f.side,"INSTEP") as Dictionary
		if f.phase==f.Phase.CONTACT and active.valid: valid_contact_ticks+=1
		# Counterfactual success permits inspection of follow-through only.
		# It is labelled geometry and is not added to World shooting success rates.
		if f.phase==f.Phase.CONTACT and not f.hit and active.valid:
			f.hit = true
			f.contact_elapsed = f.elapsed
			f.contact_target = active.point
		var debug: Dictionary = actor.avatar.shooting_motion.debug
		max_step = maxf(max_step,float(debug.get("ankle_step_m",0)))
		var support: Dictionary = actor.avatar.planted_support.duplicate()
		if f.phase==f.Phase.CONTACT and not support.valid: invalid_support_ticks+=1
		if tick==0: initial_support = support.point
		var displacement: Vector3 = support.point-initial_support
		max_support_slide = maxf(max_support_slide,Vector2(displacement.x,displacement.z).length())
		for suffix in ["L","R"]:
			var hip := sk.get_bone_global_pose(sk.find_bone("thigh."+suffix)).origin
			var knee := sk.get_bone_global_pose(sk.find_bone("shin."+suffix)).origin
			var ankle := sk.get_bone_global_pose(sk.find_bone("foot."+suffix)).origin
			max_length_error = maxf(max_length_error,absf(hip.distance_to(knee)-sk.get_bone_rest(sk.find_bone("shin."+suffix)).origin.length()))
			max_length_error = maxf(max_length_error,absf(knee.distance_to(ankle)-sk.get_bone_rest(sk.find_bone("foot."+suffix)).origin.length()))
			minimum = minf(minimum,minimum_floor(actor.avatar,suffix))
		for name in ["hips","spine","chest","upper_arm.L","upper_arm.R","thigh."+actor.avatar.side_suffix(f.side),"shin."+actor.avatar.side_suffix(f.side)]:
			var rotation := sk.get_bone_pose_rotation(sk.find_bone(name))
			peaks[name] = maxf(float(peaks.get(name,0)),Quaternion.IDENTITY.angle_to(rotation))
		var before: Vector3 = sk.to_global(sk.get_bone_global_pose(sk.find_bone("foot."+actor.avatar.side_suffix(f.side))).origin)
		actor.avatar.update_pose(0,{"velocity":Vector3.ZERO,"forward":actor.facing,"grounded":true,"locomotion":"idle"})
		var after: Vector3 = sk.to_global(sk.get_bone_global_pose(sk.find_bone("foot."+actor.avatar.side_suffix(f.side))).origin)
		max_zero_step = maxf(max_zero_step,before.distance_to(after))
		rows.append({"id":spec.id,"tick":tick,"phase":f.Phase.keys()[f.phase],"normalized":f.pose_request().normalized_time,"active":vec(active.point),"valid":active.valid,"support":vec(support.point),"shift":vec(actor.avatar.weight_shift),"zero_step":before.distance_to(after),"peaks":peaks.duplicate()})
	cases.append({"id":spec.id,"style":actor.foot.shot_style,"valid_contact_ticks":valid_contact_ticks,"length_error_m":max_length_error,"floor_min_m":minimum,"zero_delta_step_m":max_zero_step,"max_ankle_step_m":max_step,"support_slide_m":max_support_slide,"bone_peak_angle_rad":peaks})
	check(spec.id+" fixed lengths/floor/zero-delta",max_length_error<.00001 and minimum>=.0049 and max_zero_step<.00001,cases.back())
	check(spec.id+" planted support",max_support_slide<.00001)
	check(spec.id+" support valid in contact",invalid_support_ticks==0,invalid_support_ticks)
	check(spec.id+" finite real foot speed",max_step<(.10001 if actor.foot.shot_style=="full" else .07501),max_step)
	check(spec.id+" expected finite reach",valid_contact_ticks>0 if spec.get("reachable",true) else valid_contact_ticks==0,valid_contact_ticks)
	actor.avatar.clear_foot_action()
	game.ball.free()
	game.queue_free()
	await process_frame

func run() -> void:
	var specs := [
		{"id":"compact_center_R","z":.38,"side":1},
		{"id":"compact_center_L","z":.58,"side":-1},
		{"id":"compact_left","z":.58,"x":-.28},
		{"id":"compact_right","z":.58,"x":.28},
		{"id":"compact_yaw","z":.58,"yaw":.6},
		{"id":"full_forward_R","z":.82,"side":1},
		{"id":"full_forward_L","z":.82,"side":-1},
		{"id":"full_rolling","z":.60,"vz":2.3},
		{"id":"far_rejected","z":1.60,"reachable":false},
		{"id":"wide_rejected","z":.58,"x":.85,"reachable":false}
	]
	for spec in specs: await geometry_case(spec)
	var passed: int = checks.filter(func(x):return x.passed).size()
	FileAccess.open(evidence.path_join("shooting_geometry.json"),FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"total":checks.size(),"checks":checks,"cases":cases,"rows":rows,"scope":"Isolated 32-bone actual transforms, full mesh support cloud, 120Hz and zero-delta. Counterfactual hit for follow-through geometry only, no ball/World/input success implied. Physical shooting measured by separate actual-input B tests."},"\t"))
	print("SHOOT_GEOMETRY ",passed,"/",checks.size())
	quit(0 if checks.size()==50 and passed==checks.size() else 1)
