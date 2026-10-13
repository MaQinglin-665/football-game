class_name FootballBallForces
extends RefCounted
## Separate aerodynamic forces. Magnus is perpendicular to relative air velocity.

static func drag_coefficient(speed: float, p: FootballPhysicsProfile) -> float:
	var t := smoothstep(p.drag_transition_start_mps, p.drag_transition_end_mps, speed)
	return lerpf(p.cd_low_speed, p.cd_high_speed, t)

static func rolling_deceleration_mps2(speed: float, p: FootballPhysicsProfile) -> float:
	# Supported, no-slip rolling only. The slip branch retains its own friction.
	# This optional game-design curve does not claim a measured turf coefficient.
	if p.low_speed_roll_extra_mps2 <= 0.0:
		return p.roll_deceleration_mps2
	var weight := 1.0 - smoothstep(p.low_speed_roll_full_mps, p.low_speed_roll_end_mps, speed)
	return p.roll_deceleration_mps2 + p.low_speed_roll_extra_mps2 * weight

static func rolling_distance_for_speed(speed: float, p: FootballPhysicsProfile) -> float:
	# For level, windless, pure rolling: dx/dv = v / (a_roll + k(v)*v^2).
	# Composite Simpson quadrature follows this profile's Cd curve, not a fixed
	# distance table. It is an aim-assistance estimate, not a FIFA roll test.
	if not is_finite(speed):
		return 0.0
	var v := maxf(0.0, speed)
	if v <= p.rest_speed_mps:
		return 0.0
	var n := 64
	var low := maxf(0.000001, p.rest_speed_mps)
	var h := (v - low) / n
	var sum := 0.0
	var k_base := 0.5 * p.air_density_kgpm3 * PI * p.ball_radius_m * p.ball_radius_m / p.ball_mass_kg
	for i in range(n + 1):
		var s := low + h * i
		var k := k_base * drag_coefficient(s, p) if p.drag_enabled else 0.0
		var deceleration := rolling_deceleration_mps2(s, p) + k * s * s
		if deceleration <= 0.00000001:
			return INF
		var weight := 1.0 if i == 0 or i == n else 4.0 if i % 2 == 1 else 2.0
		sum += weight * s / deceleration
	return sum * h / 3.0

static func speed_for_rolling_distance(distance: float, p: FootballPhysicsProfile) -> float:
	if not is_finite(distance) or distance <= 0.0:
		return 0.0
	var low := 0.0
	var high := p.pass_max_speed_mps
	for _i in range(18):
		var mid := (low + high) * 0.5
		if rolling_distance_for_speed(mid, p) < distance:
			low = mid
		else:
			high = mid
	return (low + high) * 0.5

static func aerodynamic_forces(velocity: Vector3, spin: Vector3, wind: Vector3,
		p: FootballPhysicsProfile) -> Dictionary:
	var u := velocity - wind
	var speed := u.length()
	var drag := Vector3.ZERO
	var magnus := Vector3.ZERO
	var cd := drag_coefficient(speed, p)
	var cl := 0.0
	if speed > 0.0001:
		var area := PI * p.ball_radius_m * p.ball_radius_m
		var q_area := 0.5 * p.air_density_kgpm3 * area * speed * speed
		if p.drag_enabled:
			drag = -u / speed * q_area * cd
		if p.magnus_enabled:
			var spin_perpendicular := spin - u * (spin.dot(u) / (speed * speed))
			var spin_parameter := p.ball_radius_m * spin_perpendicular.length() / speed
			# Smooth saturation, odd in spin, zero for axial spin or no translation.
			cl = p.lift_coefficient_cap * tanh(p.lift_slope * spin_parameter / maxf(p.lift_coefficient_cap, 0.001))
			var lift_axis := spin_perpendicular.cross(u)
			if lift_axis.length_squared() > 0.00000001:
				magnus = lift_axis.normalized() * q_area * cl
	return {"drag_n": drag, "magnus_n": magnus, "cd": cd, "cl": cl,
		"reynolds": p.air_density_kgpm3 * speed * (2.0 * p.ball_radius_m) / p.air_viscosity_pas}

static func airborne_step(v: Vector3, w: Vector3, dt: float, wind: Vector3,
		p: FootballPhysicsProfile) -> Dictionary:
	# Midpoint update substantially reduces the dt dependence of quadratic drag.
	var initial := aerodynamic_forces(v, w, wind, p)
	var a0: Vector3 = (initial.drag_n + initial.magnus_n) / p.ball_mass_kg + Vector3.DOWN * p.gravity_mps2
	var vm := v + a0 * (0.5 * dt)
	var wm := w * exp(-p.air_spin_decay_per_second * dt * 0.5)
	var mid := aerodynamic_forces(vm, wm, wind, p)
	var acceleration: Vector3 = (mid.drag_n + mid.magnus_n) / p.ball_mass_kg + Vector3.DOWN * p.gravity_mps2
	var after := v + acceleration * dt
	return {"velocity": after, "spin": w * exp(-p.air_spin_decay_per_second * dt),
		"motion": vm * dt, "forces": mid}

static func rolling_step(v: Vector3, w: Vector3, normal: Vector3, dt: float,
		wind: Vector3, p: FootballPhysicsProfile) -> Dictionary:
	var n := normal.normalized()
	var tangent_v := v.slide(n)
	var radius := p.ball_radius_m
	var offset := -n * radius
	var slip := (tangent_v + w.cross(offset)).slide(n)
	var axial_spin := w.dot(n) * exp(-p.ground_axial_spin_decay_per_second * dt)
	var aerodynamic := aerodynamic_forces(tangent_v, w, wind, p)
	# On turf, no lift is applied while in persistent support contact.
	var drag_acceleration: Vector3 = aerodynamic.drag_n.slide(n) / p.ball_mass_kg
	if slip.length() > 0.015:
		# Contact slip friction replaces rolling resistance until no-slip is reached.
		var inverse_effective_mass := 1.0 / p.ball_mass_kg + radius * radius / p.inertia_kgm2()
		var slip_impulse := minf(slip.length() / inverse_effective_mass,
			p.sliding_friction_coefficient * p.ball_mass_kg * p.gravity_mps2 * dt)
		var j := -slip.normalized() * slip_impulse
		tangent_v += j / p.ball_mass_kg
		w += offset.cross(j) / p.inertia_kgm2()
		# Drag acts once, even during slip. Wind-relative drag cannot be a second damping.
		tangent_v += drag_acceleration * dt
		w += n * (axial_spin - w.dot(n))
	else:
		var before_drag := tangent_v
		tangent_v += drag_acceleration * dt
		if tangent_v.dot(before_drag) < 0.0 and wind.length_squared() < 0.0000001:
			tangent_v = Vector3.ZERO
		tangent_v = tangent_v.move_toward(Vector3.ZERO, rolling_deceleration_mps2(before_drag.length(), p) * dt)
		# move_toward reaches rest continuously under the friction budget;
		# no extra 2.5cm/s velocity discontinuity at an arbitrary threshold.
		w = n.cross(tangent_v) / radius + n * axial_spin
	# Gravity's tangential component handles inclined surfaces without snapping.
	tangent_v += (Vector3.DOWN * p.gravity_mps2).slide(n) * dt
	return {"velocity": tangent_v, "spin": w, "motion": (v.slide(n) + tangent_v) * 0.5 * dt,
		"forces": aerodynamic, "slip_mps": slip.length()}
