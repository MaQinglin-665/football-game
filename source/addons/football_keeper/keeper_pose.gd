extends RefCounted
## Rotation-only arm overlay for the unchanged identity-rest, 32-bone rig.
## Never writes hips, clavicles, legs, feet, contact bones or actor transforms.
const CONTRACT := "res://addons/football_role_actions/rig_contract.json"
const REACH_EPSILON := 0.006
const SIDES := ["L", "R"]
var skeleton: Skeleton3D
var bound := false
var bind_error := "not_bound"
var _saved: Dictionary = {}
var _debug: Dictionary = {"bound": false, "reachable": false, "hand_errors": {}, "phase": "IDLE", "sequence": 0}

func bind(rig: Skeleton3D) -> bool:
	restore()
	bound = false
	skeleton = rig
	if not is_instance_valid(rig) or rig.get_bone_count() != 32:
		bind_error = "requires_exact_32_bones"
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT))
	if not parsed is Dictionary:
		bind_error = "invalid_rig_contract"
		return false
	var bones: Array = parsed.get("bones", [])
	if bones.size() != 32:
		bind_error = "invalid_contract_count"
		return false
	for i in bones.size():
		var expected: Dictionary = bones[i]
		# Godot may reorder imported bones. Validate each named bone's actual rest.
		var bone_id: int = rig.find_bone(String(expected.get("name", "")))
		if bone_id < 0:
			bind_error = "bone_name_mismatch_at_%d" % i
			return false
		var parent := rig.get_bone_parent(bone_id)
		var parent_name := String(rig.get_bone_name(parent)) if parent >= 0 else ""
		if parent_name != String(expected.get("parent_name", "")):
			bind_error = "bone_parent_mismatch_at_%d" % i
			return false
		var translation: Array = expected.get("translation", [])
		if translation.size() != 3:
			bind_error = "invalid_contract_rest_at_%d" % i
			return false
		var rest := rig.get_bone_rest(bone_id)
		var expected_origin := Vector3(float(translation[0]), float(translation[1]), float(translation[2]))
		if rest.origin.distance_to(expected_origin) > 0.00001 or not rest.basis.is_equal_approx(Basis.IDENTITY):
			bind_error = "bone_rest_mismatch_at_%d" % i
			return false
	bound = true
	bind_error = ""
	clear_debug({})
	return true

func restore() -> void:
	if is_instance_valid(skeleton):
		for bone_id in _saved:
			skeleton.set_bone_pose_rotation(int(bone_id), _saved[bone_id])
		if not _saved.is_empty():
			skeleton.force_update_all_bone_transforms()
	_saved.clear()

func clear_debug(action: Dictionary) -> void:
	_debug = {"bound": bound, "reachable": false, "hand_errors": {}, "phase": String(action.get("phase", "IDLE")).to_upper(), "sequence": int(action.get("sequence", 0)), "bind_error": bind_error}

func apply(action: Dictionary, origin_world: Vector3, body_basis: Basis) -> void:
	clear_debug(action)
	if not bound or not is_instance_valid(skeleton):
		return
	var phase: String = _debug.phase
	if phase == "IDLE":
		return
	if not phase in ["READY", "PREPARE", "CONTACT", "HOLD", "RELEASE", "RECOVER"]:
		_debug["reason"] = "unsupported_phase"
		return
	var weight := clampf(float(action.get("weight", 1.0)), 0.0, 1.0)
	if not is_finite(weight):
		_debug["reason"] = "non_finite_weight"
		return
	var ready := origin_world + body_basis * Vector3(0.0, 1.10, -0.35)
	var centre: Vector3 = ready
	if phase in ["PREPARE", "CONTACT"]:
		centre = action.get("target_world", ready)
	elif phase == "HOLD":
		centre = action.get("hold_world", action.get("target_world", ready))
	elif phase == "RELEASE":
		centre = action.get("target_world", action.get("hold_world", ready))
	elif phase == "RECOVER":
		centre = action.get("target_world", ready)
	if not centre.is_finite():
		_debug["reason"] = "non_finite_target"
		return
	var ball_radius := float(action.get("ball_radius", 0.1121))
	if not is_finite(ball_radius) or ball_radius <= 0.0:
		_debug["reason"] = "invalid_ball_radius"
		return
	var hand_mode := String(action.get("hand_mode", "catch")).to_lower()
	if not hand_mode in ["catch", "parry"]:
		_debug["reason"] = "unsupported_hand_mode"
		return
	# HOLD always encloses the ball. Parry presents the original palm -Z face.
	var parry := hand_mode == "parry" and phase in ["PREPARE", "CONTACT", "RECOVER"]
	var lateral_spacing := 0.07 if parry else ball_radius + 0.039 - 0.0001
	var reachable := true
	var errors: Dictionary = {}
	for side in SIDES:
		var sign_side := -1.0 if side == "L" else 1.0
		var hand_rotation := body_basis if parry else body_basis * Basis(Quaternion(Vector3.UP, sign_side * PI / 2.0))
		var box_centre := centre + body_basis.x * sign_side * lateral_spacing
		var glove_offset := Vector3(sign_side * 0.004, -0.061, -0.009)
		var wrist_world := box_centre - hand_rotation * glove_offset
		var solution := _solve_arm(side, wrist_world, hand_rotation, body_basis, weight)
		var hand_id := skeleton.find_bone("hand." + side)
		var hand_world := skeleton.global_transform * skeleton.get_bone_global_pose(hand_id)
		var actual_centre := hand_world * glove_offset
		var error_m := actual_centre.distance_to(box_centre)
		var wrist_error := hand_world.origin.distance_to(wrist_world)
		var valid := bool(solution.get("within_reach", false)) and error_m < REACH_EPSILON and wrist_error < REACH_EPSILON
		errors[side] = {"error_m": error_m, "wrist_error_m": wrist_error, "within_reach": solution.get("within_reach", false), "valid": valid, "target_centre_world": box_centre, "actual_centre_world": actual_centre, "requested_wrist_world": wrist_world, "solved_wrist_world": hand_world.origin, "clamped_wrist_world": solution.get("clamped_wrist_world", wrist_world)}
		reachable = reachable and valid
	_debug["hand_errors"] = errors
	_debug["reachable"] = reachable
	_debug["weight"] = weight
	_debug["centre_world"] = centre
	_debug["hand_mode"] = "parry" if parry else "catch"
	_debug["ball_radius"] = ball_radius

func _solve_arm(side: String, wrist_world: Vector3, hand_world_basis: Basis, body_basis: Basis, weight: float) -> Dictionary:
	var upper_id := skeleton.find_bone("upper_arm." + side)
	var lower_id := skeleton.find_bone("forearm." + side)
	var hand_id := skeleton.find_bone("hand." + side)
	for bone_id in [upper_id, lower_id, hand_id]:
		if not _saved.has(bone_id):
			_saved[bone_id] = skeleton.get_bone_pose_rotation(bone_id)
	# Use the sampled shoulder origin, preserving clavicle and torso motion.
	var shoulder := skeleton.get_bone_global_pose(upper_id).origin
	# Imported pose translations already contain the local rest offsets.
	var upper_offset := skeleton.get_bone_pose_position(lower_id)
	var lower_offset := skeleton.get_bone_pose_position(hand_id)
	var a := upper_offset.length()
	var b := lower_offset.length()
	var desired := skeleton.global_transform.affine_inverse() * wrist_world
	var delta := desired - shoulder
	var distance := delta.length()
	if a < 0.00001 or b < 0.00001:
		return {"within_reach": false}
	var minimum := absf(a - b) + 0.00001
	var maximum := a + b - 0.00001
	var within_reach := distance >= minimum and distance <= maximum
	var axis := delta / distance if distance > 0.00001 else Vector3.FORWARD
	var solved_distance := clampf(distance, minimum, maximum)
	var wrist := shoulder + axis * solved_distance
	var sign_side := -1.0 if side == "L" else 1.0
	var pole_world := body_basis * Vector3(sign_side * 0.45, -1.0, 0.25)
	var pole := skeleton.global_transform.basis.inverse() * pole_world
	pole -= axis * pole.dot(axis)
	if pole.length_squared() < 0.00001:
		pole = Vector3.UP - axis * Vector3.UP.dot(axis)
	if pole.length_squared() < 0.00001:
		pole = Vector3.RIGHT - axis * Vector3.RIGHT.dot(axis)
	pole = pole.normalized()
	var along := (a * a - b * b + solved_distance * solved_distance) / (2.0 * solved_distance)
	var elbow := shoulder + axis * along + pole * sqrt(maxf(0.0, a * a - along * along))
	var upper_rotation := Quaternion(upper_offset.normalized(), (elbow - shoulder).normalized())
	var lower_rotation := Quaternion(lower_offset.normalized(), (wrist - elbow).normalized())
	var parent_rotation := skeleton.get_bone_global_pose(skeleton.get_bone_parent(upper_id)).basis.get_rotation_quaternion()
	var hand_rotation := skeleton.global_transform.basis.orthonormalized().get_rotation_quaternion().inverse() * hand_world_basis.get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(upper_id, (_saved[upper_id] as Quaternion).slerp(parent_rotation.inverse() * upper_rotation, weight))
	skeleton.set_bone_pose_rotation(lower_id, (_saved[lower_id] as Quaternion).slerp(upper_rotation.inverse() * lower_rotation, weight))
	skeleton.set_bone_pose_rotation(hand_id, (_saved[hand_id] as Quaternion).slerp(lower_rotation.inverse() * hand_rotation, weight))
	skeleton.force_update_all_bone_transforms()
	return {"within_reach": within_reach, "clamped_wrist_world": skeleton.global_transform * wrist}

func debug() -> Dictionary:
	var result := _debug.duplicate(true)
	result["bound"] = bound
	result["bind_error"] = bind_error
	return result
