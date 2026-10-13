extends RefCounted
## Original, fixed-length pose, sampled before the host's final contact sockets.
## No target IK, transform motion, force or clock is owned by this adapter.
static func apply(skeleton: Skeleton3D, _clip: String, _action: Dictionary, state: Dictionary, _delta: float) -> void:
	var low: Dictionary = state.get("interaction", {})
	var weight: float = float(low.get("low_weight", 0.0))
	if weight <= 0.0: return
	var angle := 1.30 * weight
	_rotate_rest(skeleton, "root", 0.0)
	var root: int = skeleton.find_bone("root")
	skeleton.set_bone_pose_position(root, skeleton.get_bone_rest(root).origin + Vector3.DOWN*.70*weight)
	_rotate_rest(skeleton, "hips", angle)
	for bone in ["chest", "neck", "head"]: _rotate_rest(skeleton, bone, 0.0)
	for side in ["L", "R"]:
		_rotate_rest(skeleton, "thigh."+side, 0.0)
		_rotate_rest(skeleton, "shin."+side, .06*weight)
		_rotate_rest(skeleton, "foot."+side, -angle-.06*weight)
		_rotate_rest(skeleton, "upper_arm."+side, -.60*weight)
		_rotate_rest(skeleton, "forearm."+side, -.50*weight)
	# Keep the actual, fixed-length boots above turf throughout the blend. A
	# constant pelvis drop otherwise buries feet during intermediate hip angles.
	skeleton.force_update_all_bone_transforms()
	var boot_low := INF
	for side in ["L","R"]:
		var foot: Transform3D = skeleton.get_bone_global_pose(skeleton.find_bone("foot."+side))
		boot_low = minf(boot_low,(foot.origin+foot.basis*Vector3(0,-.050,-.080)).y)
	if boot_low<.075:
		skeleton.set_bone_pose_position(root,skeleton.get_bone_pose_position(root)+Vector3.UP*(.075-boot_low))

static func _rotate_rest(skeleton: Skeleton3D, name: String, angle: float) -> void:
	var index: int = skeleton.find_bone(name)
	if index < 0: return
	skeleton.set_bone_pose_position(index, skeleton.get_bone_rest(index).origin)
	skeleton.set_bone_pose_rotation(index, Quaternion(Vector3.RIGHT, angle))
