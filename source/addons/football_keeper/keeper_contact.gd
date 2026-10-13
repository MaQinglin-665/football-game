extends RefCounted
## Pure geometry; all positions, sizes and radii are in metres.
## The host owns legal catch policy and must test both hands at one shared time.

const NUMERIC_SKIN_M: float = 0.0003
const MAX_ADVANCES: int = 32
const INVALID_GAP_M: float = 1.0e30


static func sphere_box(ball_center: Vector3, radius: float, box: Transform3D, size: Vector3) -> Dictionary:
	if not ball_center.is_finite() or not _valid_radius(radius) or not _valid_box(box, size):
		return {"touching": false, "valid": false, "gap_m": INVALID_GAP_M, "point": Vector3.ZERO, "normal": Vector3.UP}
	var sample: Dictionary = _sample(ball_center, radius, _rotation_box(box), size)
	if not is_finite(float(sample["gap_m"])) or not (sample["point"] as Vector3).is_finite() or not (sample["normal"] as Vector3).is_finite():
		return {"touching": false, "valid": false, "gap_m": INVALID_GAP_M, "point": Vector3.ZERO, "normal": Vector3.UP}
	return {"touching": float(sample["gap_m"]) <= NUMERIC_SKIN_M, "valid": true,
		"gap_m": sample["gap_m"], "point": sample["point"], "normal": sample["normal"]}


static func sweep_sphere_box(ball_from: Vector3, ball_to: Vector3, radius: float,
		from_box: Transform3D, to_box: Transform3D, box_size: Vector3) -> Dictionary:
	var miss: Dictionary = {"hit": false, "valid": false, "fraction": 1.0,
		"point": Vector3.ZERO, "normal": Vector3.UP, "gap_m": INVALID_GAP_M,
		"iterations": 0, "converged": false}
	if not ball_from.is_finite() or not ball_to.is_finite() or not _valid_radius(radius):
		return miss
	if not _valid_box(from_box, box_size) or not _valid_box(to_box, box_size):
		return miss
	var first: Transform3D = _rotation_box(from_box)
	var last: Transform3D = _rotation_box(to_box)
	var qa: Quaternion = first.basis.get_rotation_quaternion().normalized()
	var qb: Quaternion = last.basis.get_rotation_quaternion().normalized()
	# Shortest quaternion slerp; angular travel and corner radius bound distance
	# variation over the FULL sweep, so gap / speed_bound is a fraction step.
	var angular_travel: float = 2.0 * acos(clampf(absf(qa.dot(qb)), 0.0, 1.0))
	var corner_bound: float = (box_size * 0.5).length()
	var speed_bound: float = ball_from.distance_to(ball_to) + first.origin.distance_to(last.origin) + angular_travel * corner_bound
	if not is_finite(speed_bound):
		return miss
	miss["valid"] = true
	var fraction: float = 0.0
	var min_gap: float = INVALID_GAP_M
	for iteration in range(MAX_ADVANCES):
		var center: Vector3 = ball_from.lerp(ball_to, fraction)
		var box: Transform3D = Transform3D(Basis(qa.slerp(qb, fraction)), first.origin.lerp(last.origin, fraction))
		var sample: Dictionary = _sample(center, radius, box, box_size)
		var gap: float = float(sample["gap_m"])
		miss["iterations"] = iteration + 1
		if not is_finite(gap) or not (sample["point"] as Vector3).is_finite() or not (sample["normal"] as Vector3).is_finite():
			miss["valid"] = false
			return miss
		min_gap = minf(min_gap, gap)
		miss["gap_m"] = min_gap
		miss["point"] = sample["point"]
		miss["normal"] = sample["normal"]
		if gap <= NUMERIC_SKIN_M:
			return {"hit": true, "valid": true, "fraction": fraction, "point": sample["point"],
				"normal": sample["normal"], "gap_m": gap, "iterations": iteration + 1, "converged": true}
		if fraction >= 1.0 or speed_bound <= 0.0:
			miss["converged"] = true
			return miss
		# Exact signed OBB distance is Lipschitz. No enlarged-AABB corner test.
		var next_fraction: float = minf(1.0, fraction + gap / speed_bound)
		if next_fraction <= fraction:
			return miss
		fraction = next_fraction
	# Explicitly expose the iteration cap; the host must not infer a catch.
	return miss


static func point_obb(center: Vector3, box: Transform3D, size: Vector3) -> Dictionary:
	# Internal helper expects validated rigid transforms and positive sizes.
	var local: Vector3 = box.basis.transposed() * (center - box.origin)
	var half: Vector3 = size * 0.5
	var closest: Vector3 = Vector3(clampf(local.x, -half.x, half.x), clampf(local.y, -half.y, half.y), clampf(local.z, -half.z, half.z))
	var delta: Vector3 = local - closest
	var distance: float = delta.length()
	var normal: Vector3
	if distance > 0.0:
		normal = delta / distance
	else:
		# Inside/on the box: deterministic nearest-face outward normal.
		var clearance: Vector3 = half - local.abs()
		var axis: int = 0
		if clearance.y < clearance.x:
			axis = 1
		if clearance.z < clearance[axis]:
			axis = 2
		normal = Vector3.ZERO
		normal[axis] = 1.0 if local[axis] >= 0.0 else -1.0
		closest[axis] = normal[axis] * half[axis]
		distance = -clearance[axis]
	return {"distance_m": distance, "closest": box * closest, "normal": (box.basis * normal).normalized()}


static func _sample(center: Vector3, radius: float, box: Transform3D, size: Vector3) -> Dictionary:
	var closest: Dictionary = point_obb(center, box, size)
	var normal: Vector3 = closest["normal"]
	return {"gap_m": float(closest["distance_m"]) - radius, "normal": normal, "point": center - normal * radius}


static func _valid_radius(radius: float) -> bool:
	return is_finite(radius) and radius >= 0.0


static func _valid_box(box: Transform3D, size: Vector3) -> bool:
	if not box.origin.is_finite() or not size.is_finite() or size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
		return false
	var b: Basis = box.basis
	if not b.x.is_finite() or not b.y.is_finite() or not b.z.is_finite():
		return false
	# Scaling, shear and reflection are not rigid glove rotations.
	return absf(b.x.length_squared() - 1.0) <= 0.001 and absf(b.y.length_squared() - 1.0) <= 0.001 and absf(b.z.length_squared() - 1.0) <= 0.001 and absf(b.x.dot(b.y)) <= 0.001 and absf(b.x.dot(b.z)) <= 0.001 and absf(b.y.dot(b.z)) <= 0.001 and absf(b.determinant() - 1.0) <= 0.003


static func _rotation_box(box: Transform3D) -> Transform3D:
	return Transform3D(box.basis.orthonormalized(), box.origin)
