class_name FootballContactMath
extends RefCounted

static func sphere_response(ball_velocity: Vector3, ball_spin: Vector3,
		body_velocity: Vector3, normal: Vector3, body_mass: float, restitution: float,
		friction: float, p: FootballPhysicsProfile, ground_body_contact: bool = false) -> Dictionary:
	var n := normal.normalized()
	var offset := -n * p.ball_radius_m
	var relative := ball_velocity + ball_spin.cross(offset) - body_velocity
	var closing := relative.dot(n)
	if closing >= 0.0:
		return {"velocity": ball_velocity, "spin": ball_spin, "impulse_ns": Vector3.ZERO, "closing_mps": closing}
	var inverse_body_mass := 0.0 if body_mass <= 0.0 else 1.0 / body_mass
	var inverse_normal_mass := 1.0 / p.ball_mass_kg + inverse_body_mass
	var jn := -(1.0 + restitution) * closing / inverse_normal_mass
	var tangential := relative.slide(n)
	if ground_body_contact:
		tangential.y = 0.0
	var j := n * jn
	if tangential.length() > 0.0001:
		var inverse_tangent_mass := inverse_normal_mass + p.ball_radius_m * p.ball_radius_m / p.inertia_kgm2()
		j -= tangential.normalized() * minf(tangential.length() / inverse_tangent_mass, friction * jn)
	return {"velocity": ball_velocity + j / p.ball_mass_kg,
		"spin": ball_spin + offset.cross(j) / p.inertia_kgm2(),
		"impulse_ns": j, "closing_mps": closing}

static func body_pair_impulse(v_a: Vector3, v_b: Vector3, normal_to_a: Vector3,
		mass_a: float, mass_b: float, restitution: float, friction: float) -> Vector3:
	var n := Vector3(normal_to_a.x, 0.0, normal_to_a.z).normalized()
	if n.length_squared() < 0.5:
		return Vector3.ZERO
	var relative := Vector3(v_a.x - v_b.x, 0.0, v_a.z - v_b.z)
	var closing := relative.dot(n)
	if closing >= 0.0:
		return Vector3.ZERO
	var inverse_mass := 1.0 / mass_a + 1.0 / mass_b
	var jn := -(1.0 + restitution) * closing / inverse_mass
	var j := n * jn
	var tangent := relative.slide(n)
	if tangent.length() > 0.0001:
		j -= tangent.normalized() * minf(tangent.length() / inverse_mass, friction * jn)
	return j
