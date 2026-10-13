extends RefCounted
## Explicit visual layer around an existing avatar; never schedules its gait.
## Call update_pose instead of avatar.update_pose, or pair before_pose/after_pose.
## A host foot module can be installed separately with set_foot_overlay().

signal ball_requested(event: Dictionary)

const Solver := preload("res://addons/football_role_actions/pose_solver.gd")
const Gloves := preload("res://addons/football_role_actions/goalkeeper_gloves.gd")
const CONTRACT := "res://addons/football_role_actions/rig_contract.json"
const REQUEST_DURATION := .82
const REQUEST_PEAK := .24
const REQUEST_COOLDOWN := 2.5

var avatar: Node3D
var skeleton: Skeleton3D
var gloves: RefCounted
var foot_overlay: RefCounted
var ready := false
var rig_error := ""
var team := 0
var first_person := false
var goalkeeper := false
var _saved: Dictionary = {}
var _defence_weight := 0.0
var _request_elapsed := -1.0
var _request_cooldown := 0.0
var _request_sequence := 0
var _request_event: Dictionary = {}
var _request_emitted := false
var _busy := false
var _status: Dictionary = {}

func bind(character: Node3D, team_id := 0, local_first_person := false, is_keeper := false) -> bool:
	if ready:
		rig_error = "already_bound"
		return false
	character.ensure_loaded()
	avatar = character
	skeleton = character.get("skeleton") as Skeleton3D
	team = team_id
	first_person = local_first_person
	goalkeeper = is_keeper
	if not _validate_rig():
		return false
	gloves = Gloves.new()
	gloves.bind(skeleton, team, first_person)
	gloves.configure(goalkeeper, first_person)
	ready = true
	return true

func _validate_rig() -> bool:
	if skeleton == null:
		rig_error = "missing_skeleton"
		return false
	var contract: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT))
	var bones: Array = contract.bones
	if skeleton.get_bone_count() != bones.size():
		rig_error = "requires_the_existing_32_bone_rig"
		return false
	for bone: Dictionary in bones:
		var id := skeleton.find_bone(String(bone.name))
		if id < 0:
			rig_error = "missing_bone:" + String(bone.name)
			return false
		var parent := skeleton.get_bone_parent(id)
		var parent_name := String(skeleton.get_bone_name(parent)) if parent >= 0 else ""
		if parent_name != String(bone.parent_name):
			rig_error = "parent_mismatch:" + String(bone.name)
			return false
		var t: Array = bone.translation
		var rest := skeleton.get_bone_rest(id)
		if rest.origin.distance_to(Vector3(t[0], t[1], t[2])) > .00002 or not rest.basis.is_equal_approx(Basis.IDENTITY):
			rig_error = "rest_mismatch:" + String(bone.name)
			return false
	return true

func set_foot_overlay(layer: RefCounted) -> bool:
	if not ready or not layer.bind(avatar, skeleton):
		return false
	foot_overlay = layer
	return true

func update_pose(delta: float, state: Dictionary) -> void:
	if not ready:
		return
	before_pose()
	avatar.update_pose(delta, state)
	after_pose(delta, state)

func before_pose() -> void:
	if not ready:
		return
	# Remove our previous pose before locomotion reads its blend source.
	for id: int in _saved:
		var old: Dictionary = _saved[id]
		skeleton.set_bone_pose_position(id, old.position)
		skeleton.set_bone_pose_rotation(id, old.rotation)
	_saved.clear()
	skeleton.force_update_all_bone_transforms()

func remember_bone(name: String) -> int:
	var id := skeleton.find_bone(name)
	if not _saved.has(id):
		_saved[id] = {"position": skeleton.get_bone_pose_position(id), "rotation": skeleton.get_bone_pose_rotation(id)}
	return id

func remember_leg(side: String) -> void:
	for stem in ["thigh.", "shin.", "foot.", "toe."]:
		remember_bone(stem + side)

func add_rotation(name: String, rotation: Quaternion) -> void:
	var id := remember_bone(name)
	skeleton.set_bone_pose_rotation(id, skeleton.get_bone_pose_rotation(id) * rotation)

func after_pose(delta: float, state: Dictionary) -> void:
	if not ready:
		return
	var dt := maxf(0.0, delta)
	_request_cooldown = maxf(0.0, _request_cooldown - dt)
	var action: Dictionary = state.get("foot_action", {})
	_busy = not action.is_empty() or bool(state.get("upper_body_busy", false))
	if _busy or bool(state.get("owns_ball", false)) or not bool(state.get("active", true)):
		_request_elapsed = -1.0
	if state.has("carrier_id") and (int(state.carrier_id) != int(_request_event.get("carrier_id", -1)) or int(state.get("carrier_team", -1)) != team):
		_request_elapsed = -1.0
	var velocity: Vector3 = state.get("velocity", Vector3.ZERO)
	var speed := Vector2(velocity.x, velocity.z).length()
	var target := 0.0
	if bool(state.get("defending", false)) and not _busy and not bool(state.get("owns_ball", false)) and bool(state.get("grounded", true)):
		target = clampf(float(state.get("defence_strength", 1.0)), 0.0, 1.0) * (1.0 - smoothstep(.8, 3.5, speed))
	_defence_weight = move_toward(_defence_weight, target, dt / .16)
	if _defence_weight < .00001:
		_defence_weight = 0.0
	_status = {"defence_weight": _defence_weight, "request_active": false, "foot_action": {}, "rig_error": rig_error}
	if _defence_weight > 0.0 and not _busy:
		_apply_defence(_defence_weight, speed,float(state.get("contain_side",0.0)))
	if foot_overlay != null:
		_status.foot_action = foot_overlay.apply(action, state, self)
	if _request_elapsed >= 0.0:
		_request_elapsed += dt
		if _request_elapsed < REQUEST_DURATION:
			var weight := smoothstep(0.0, REQUEST_PEAK, _request_elapsed) * (1.0 - smoothstep(.48, REQUEST_DURATION, _request_elapsed))
			_apply_request(weight)
			_status.request_active = true
			if not _request_emitted and _request_elapsed >= REQUEST_PEAK:
				_request_emitted = true
				ball_requested.emit(_request_event.duplicate())
		else:
			_request_elapsed = -1.0
	skeleton.force_update_all_bone_transforms()
	gloves.refresh()
	_status["request_sequence"] = _request_sequence
	_status["request_cooldown"] = _request_cooldown
	_status["gloves_enabled"] = goalkeeper

func _apply_defence(weight: float, speed: float, contain_side:float=0.0) -> void:
	var feet := {}
	for side in ["L", "R"]:
		feet[side] = skeleton.get_bone_global_pose(skeleton.find_bone("foot." + side))
	var hips := remember_bone("hips")
	skeleton.set_bone_pose_position(hips, skeleton.get_bone_pose_position(hips) + Vector3(0, -.026, -.012) * weight)
	add_rotation("hips", Quaternion(Vector3.RIGHT, -.025 * weight))
	add_rotation("spine", Quaternion(Vector3.RIGHT, -.035 * weight))
	add_rotation("chest", Quaternion(Vector3.RIGHT, -.025 * weight))
	# Shoulder/hip presentation for actual near-ball body pressure. Feet remain
	# at their pre-overlay anchors; input and camera orientation are unchanged.
	if contain_side!=0:
		add_rotation("hips",Quaternion(Vector3.UP,contain_side*.32*weight))
		add_rotation("spine",Quaternion(Vector3.UP,-contain_side*.12*weight))
		add_rotation("chest",Quaternion(Vector3.UP,contain_side*.08*weight))
	skeleton.force_update_all_bone_transforms()
	var solved := true
	for side in ["L", "R"]:
		var pose: Transform3D = feet[side]
		if speed < .08:
			pose.origin.x = lerpf(pose.origin.x, -.18 if side == "L" else .18, weight)
		remember_leg(side)
		solved = Solver.solve_leg(skeleton, side, pose.origin, pose.basis.get_rotation_quaternion(), Vector3.FORWARD) and solved
	if not solved:
		# Reject the pose, preserving the complete base pose and real contact.
		before_pose()
		_status["defence_rejected"] = true
		return
	for side in ["L", "R"]:
		var sign_side := -1.0 if side == "L" else 1.0
		add_rotation("upper_arm." + side, Quaternion(Vector3.BACK, sign_side * .18 * weight) * Quaternion(Vector3.RIGHT, .22 * weight))
		add_rotation("forearm." + side, Quaternion(Vector3.RIGHT, .35 * weight))

func request_ball(actor_id: int, carrier_id: int, carrier_team: int, side := 1) -> bool:
	if not ready or _busy or _request_elapsed >= 0.0 or _request_cooldown > 0.0:
		return false
	if actor_id <= 0 or carrier_id <= 0 or actor_id == carrier_id or carrier_team != team:
		return false
	_request_sequence += 1
	_request_elapsed = 0.0
	_request_cooldown = REQUEST_COOLDOWN
	_request_emitted = false
	_request_event = {"kind": "BALL_REQUEST", "actor_id": actor_id, "team": team, "carrier_id": carrier_id, "sequence": _request_sequence, "side": -1 if side <= 0 else 1, "ttl_s": 1.25}
	return true

func _apply_request(weight: float) -> void:
	var sign_side := float(_request_event.side)
	var side := "L" if sign_side < 0 else "R"
	var upper := remember_bone("upper_arm." + side)
	var elbow := remember_bone("forearm." + side)
	var hand := remember_bone("hand." + side)
	var upper_target := Quaternion(Vector3.BACK, sign_side * 2.23) * Quaternion(Vector3.RIGHT, -.14)
	var elbow_target := Quaternion(Vector3.BACK, sign_side * .22) * Quaternion(Vector3.RIGHT, .16)
	skeleton.set_bone_pose_rotation(upper, skeleton.get_bone_pose_rotation(upper).slerp(upper_target, weight))
	skeleton.set_bone_pose_rotation(elbow, skeleton.get_bone_pose_rotation(elbow).slerp(elbow_target, weight))
	skeleton.set_bone_pose_rotation(hand, skeleton.get_bone_pose_rotation(hand).slerp(Quaternion(Vector3.RIGHT, -.18), weight))

func configure_keeper(enabled: bool, local_first_person: bool) -> void:
	goalkeeper = enabled
	first_person = local_first_person
	if gloves != null:
		gloves.configure(enabled, local_first_person)

func get_state() -> Dictionary:
	return _status.duplicate(true)

func get_hand_geometry() -> Dictionary:
	return gloves.get_geometry() if ready else {}

func detach() -> void:
	before_pose()
	if gloves != null:
		gloves.detach()
	ready = false
