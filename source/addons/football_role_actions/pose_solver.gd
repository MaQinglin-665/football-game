extends RefCounted
## Fixed-length pose helpers for the existing 32-bone rig. No collision/ball work.

static func solve_leg(skeleton: Skeleton3D, side: String, ankle: Vector3, rotation: Quaternion, direction: Vector3) -> bool:
	var thigh := skeleton.find_bone("thigh." + side)
	var shin := skeleton.find_bone("shin." + side)
	var foot := skeleton.find_bone("foot." + side)
	var hip := skeleton.get_bone_global_pose(thigh).origin
	var upper_rest := skeleton.get_bone_rest(shin).origin
	var lower_rest := skeleton.get_bone_rest(foot).origin
	var a := upper_rest.length()
	var b := lower_rest.length()
	var vector := ankle - hip
	var distance := vector.length()
	if not ankle.is_finite() or distance > a + b - .00001 or distance < absf(a - b) + .025:
		return false
	var axis := vector / distance
	direction.y = 0.0
	if direction.length_squared() < .00001:
		direction = Vector3.FORWARD
	var pole := direction.normalized() - axis * direction.normalized().dot(axis)
	if pole.length_squared() < .00001:
		pole = Vector3.RIGHT - axis * Vector3.RIGHT.dot(axis)
	pole = pole.normalized()
	var along := (a * a - b * b + distance * distance) / (2.0 * distance)
	var knee := hip + axis * along + pole * sqrt(maxf(0.0, a * a - along * along))
	var upper := Quaternion(upper_rest.normalized(), (knee - hip).normalized())
	var lower := Quaternion(lower_rest.normalized(), (ankle - knee).normalized())
	var parent := skeleton.get_bone_global_pose(skeleton.get_bone_parent(thigh)).basis.get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(thigh, parent.inverse() * upper)
	skeleton.set_bone_pose_rotation(shin, upper.inverse() * lower)
	skeleton.set_bone_pose_rotation(foot, lower.inverse() * rotation)
	skeleton.force_update_all_bone_transforms()
	return true
