extends RefCounted
## Original project code. Runs after animation sampling and before foot/support IK.
## Uses host state only; never advances a clock, changes bone lengths or touches a ball.

static func apply(skeleton: Skeleton3D, _clip: String, _action: Dictionary, state: Dictionary, _delta: float) -> void:
	var pose: Dictionary = state.get("interaction", {})
	if pose.is_empty(): return
	var crouch: float = float(pose.get("crouch", 0.0))
	var airborne: bool = bool(pose.get("airborne", false))
	if crouch > 0.0:
		var root: int = skeleton.find_bone("root")
		skeleton.set_bone_pose_position(root, Vector3.DOWN * float(pose.get("crouch_drop", 0.62)) * crouch)
		for side in ["L", "R"]:
			_rotate(skeleton, "thigh." + side, -.80 * crouch)
			_rotate(skeleton, "shin." + side, 1.60 * crouch)
			_rotate(skeleton, "foot." + side, -.80 * crouch)
	if airborne:
		for side in ["L", "R"]:
			_rotate(skeleton, "upper_arm." + side, -.38)
			_rotate(skeleton, "forearm." + side, -.28)
		var weight: float = float(pose.get("header_weight", 0.0))
		_rotate(skeleton, "chest", -.10 * weight)
		_rotate(skeleton, "neck", .10 * weight)

static func _rotate(skeleton: Skeleton3D, bone: String, angle: float) -> void:
	var index: int = skeleton.find_bone(bone)
	if index >= 0:
		skeleton.set_bone_pose_rotation(index, skeleton.get_bone_pose_rotation(index) * Quaternion(Vector3.RIGHT, angle))
