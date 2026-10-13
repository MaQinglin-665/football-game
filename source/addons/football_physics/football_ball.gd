class_name FootballPhysicsBall
extends CharacterBody3D

const Forces := preload("ball_forces.gd")
const Contacts := preload("contact_math.gd")

signal physical_contact(collider: Object, point_world: Vector3, impulse_ns: Vector3)
signal contact_budget_exhausted()

@export var profile: FootballPhysicsProfile
@export var auto_step: bool = true
var spin_rads: Vector3 = Vector3.ZERO
var wind_mps: Vector3 = Vector3.ZERO
var previous_position: Vector3 = Vector3.ZERO
var grounded: bool = false
var last_forces: Dictionary = {}
var collision_count: int = 0
var body_collision_count: int = 0
var substep_budget_hits: int = 0
var squeeze_count: int = 0
var last_contact_result: Dictionary = {}
var radius: float:
	get: return profile.ball_radius_m if profile else 0.11
var mass_kg: float:
	get: return profile.ball_mass_kg if profile else 0.43

func _ready() -> void:
	if profile == null:
		profile = FootballPhysicsProfile.playable()
	assert(profile.validate())
	collision_layer = 4
	collision_mask = 3
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	process_physics_priority = 20
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	sphere.margin = profile.sweep_margin_m
	shape.shape = sphere
	shape.name = "PhysicsSphere"
	add_child(shape)
	previous_position = global_position

func _physics_process(dt: float) -> void:
	if auto_step:
		step_physics(dt)

func apply_impulse_ns(j_world: Vector3, offset_world: Vector3 = Vector3.ZERO) -> bool:
	if not j_world.is_finite() or not offset_world.is_finite():
		return false
	velocity += j_world / mass_kg
	spin_rads += offset_world.cross(j_world) / profile.inertia_kgm2()
	_enforce_finite_limits()
	return true

func kick(direction_world: Vector3, power_01: float, lift_degrees: float = 0.0,
		spin_world: Vector3 = Vector3.ZERO, kind: String = "pass", loft_launch_speed: float = -1.0, contact_surface:String="INSTEP") -> Dictionary:
	var horizontal := Vector3(direction_world.x, 0.0, direction_world.z)
	if horizontal.length_squared() < 0.00001 or not direction_world.is_finite() \
			or not spin_world.is_finite() or not is_finite(power_01) or not is_finite(lift_degrees):
		return {"accepted": false, "reason": "invalid_kick"}
	var aim := horizontal.normalized()
	var lift := deg_to_rad(clampf(lift_degrees, -10.0, 65.0))
	var lower := profile.shot_min_speed_mps if kind == "shot" else profile.pass_min_speed_mps
	var upper := profile.shot_max_speed_mps if kind == "shot" else profile.pass_max_speed_mps
	var speed := lerpf(lower, upper, pow(clampf(power_01, 0.0, 1.0), profile.power_curve_exponent))
	if kind=="pass" and lift>.10:speed=profile.loft_pass_speed(power_01)
	if kind=="pass" and lift>.10 and is_finite(loft_launch_speed) and loft_launch_speed>0:
		speed=clampf(loft_launch_speed,profile.loft_pass_min_speed_mps,profile.loft_pass_max_speed_mps)
	var target_roll_distance := -1.0
	if kind == "pass" and absf(lift) < 0.01 and profile.ground_pass_distance_mapping_enabled:
		target_roll_distance = lerpf(profile.ground_pass_min_distance_m, profile.ground_pass_max_distance_m,
			pow(clampf(power_01, 0.0, 1.0), profile.ground_pass_distance_exponent))
		speed = preload("res://addons/football_ground_pass/ground_pass_solution.gd").launch_speed(target_roll_distance,profile)
	if kind=="pass" and contact_surface=="HEEL":
		speed=minf(speed,profile.heel_max_speed_mps);lift=0.0
	var desired := (aim * cos(lift) + Vector3.UP * sin(lift)) * speed
	var j := ((desired - velocity) * mass_kg).limit_length(profile.kick_impulse_limit_ns)
	apply_impulse_ns(j)
	# Contact-supplied angular impulse, separated from linear impulse.
	var angular_impulse := (spin_world - spin_rads) * profile.inertia_kgm2()
	spin_rads += angular_impulse / profile.inertia_kgm2()
	if absf(lift) < 0.01:
		# A ground pass represents a rolling launch; callers may use apply_impulse_ns for toe-slip.
		if kind=="pass":spin_rads=Vector3.UP*spin_rads.y+Vector3.UP.cross(Vector3(velocity.x,0,velocity.z))/radius
		else:spin_rads += Vector3.UP.cross(Vector3(velocity.x, 0.0, velocity.z)) / radius
	_enforce_finite_limits()
	last_contact_result = {"accepted": true, "kind": kind, "impulse_ns": j,
		"angular_impulse_nms": angular_impulse, "speed_mps": velocity.length(),
		"target_roll_distance_m": target_roll_distance}
	return last_contact_result

func buffer_contact(contact_point_world: Vector3, receiver_velocity_world: Vector3,
		quality_01: float, dt: float) -> Dictionary:
	if not contact_point_world.is_finite() or not receiver_velocity_world.is_finite() \
			or not is_finite(quality_01) or not is_finite(dt) or dt <= 0.0:
		return {"accepted": false, "reason": "invalid_contact"}
	var offset := contact_point_world - global_position
	if absf(offset.length() - radius) > profile.receiver_contact_tolerance_m:
		return {"accepted": false, "reason": "outside_ball_surface"}
	# Must be called with actual contact duration. Cap a single call at a physics tick.
	var duration := minf(dt, 1.0 / 60.0)
	var quality := clampf(quality_01, 0.0, 1.0)
	var relative := velocity - receiver_velocity_world
	var budget := profile.receiver_force_budget_n * quality * duration
	# Exponential relaxation is gradual at low speed; the separate force cap
	# still limits high-speed contacts. tau<=0 exactly restores the old rule.
	var gain := 1.0 if profile.receiver_relaxation_time_s <= 0.0 else \
		1.0 - exp(-quality * duration / profile.receiver_relaxation_time_s)
	var j := (-relative * mass_kg * gain).limit_length(budget)
	apply_impulse_ns(j)
	var linear_fraction := j.length() / maxf(mass_kg * relative.length(), 0.0000001)
	var support := _support_normal() if profile.receiver_sync_ground_roll else Vector3.ZERO
	if support.length_squared() > 0.5:
		# Preserve the rolling subspace under reception. Independent angular
		# damping can leave a stopped ball storing enough roll spin to relaunch.
		var axial := spin_rads.dot(support) * exp(-profile.receiver_spin_brake_per_second * quality * duration)
		var rolling_target := support.cross(receiver_velocity_world.slide(support)) / radius
		var tangent_spin := spin_rads.slide(support).lerp(rolling_target, clampf(linear_fraction, 0.0, 1.0))
		spin_rads = tangent_spin + support * axial
	else:
		spin_rads *= exp(-profile.receiver_spin_brake_per_second * quality * duration)
	last_contact_result = {"accepted": true, "impulse_ns": j,
		"relative_before_mps": relative.length(), "relative_after_mps": (velocity - receiver_velocity_world).length(),
		"duration_s": duration, "position_changed": false, "relaxation_gain": gain,
		"force_n": j.length() / duration, "rolling_sync": support.length_squared() > 0.5}
	return last_contact_result

func step_physics(dt: float) -> void:
	if not is_finite(dt) or dt <= 0.0:
		return
	previous_position = global_position
	# No discarded accumulator time and no variable-size final remainder.
	var count := maxi(1, int(ceil(dt / profile.internal_step_seconds - 0.000001)))
	var h := dt / count
	for _i in range(count):
		_substep(h)
	_enforce_finite_limits()

func _support_normal() -> Vector3:
	# Only environment layer 1 can supply turf support. A capsule/cylinder recovery
	# normal must not masquerade as ground when a ball is squeezed between players.
	var query := PhysicsRayQueryParameters3D.create(global_position,
		global_position + Vector3.DOWN * (radius + profile.ground_probe_m), 1, [get_rid()])
	var probe := get_world_3d().direct_space_state.intersect_ray(query)
	if not probe.is_empty() and probe.normal.y >= 0.70:
		var n: Vector3 = probe.normal
		var normal_speed := velocity.dot(n)
		var gap := (global_position - (probe.position as Vector3)).dot(n) - radius
		# Physics support_ready: proximity is not a swept impact. Preserve rising
		# and descending momentum until actual turf contact.
		if normal_speed <= 0.000001 and normal_speed >= -profile.rest_speed_mps \
				and gap <= 2.0 * profile.sweep_margin_m + 0.000001:
			return n
	return Vector3.ZERO

func _substep(dt: float) -> void:
	var support := _support_normal()
	grounded = support.length_squared() > 0.5
	var integration: Dictionary
	if grounded:
		integration = Forces.rolling_step(velocity, spin_rads, support, dt, wind_mps, profile)
	else:
		integration = Forces.airborne_step(velocity, spin_rads, dt, wind_mps, profile)
	velocity = integration.velocity
	spin_rads = integration.spin
	last_forces = integration.forces
	var motion: Vector3 = integration.motion
	var time_remaining := dt
	var body_contacts_seen: Array = []
	for contact_index in range(profile.max_contacts_per_substep):
		if motion.length_squared() < 0.000000000001:
			break
		var hit := move_and_collide(motion, false, profile.sweep_margin_m, false)
		if hit == null:
			break
		collision_count += 1
		var fraction := clampf(hit.get_travel().length() / maxf(motion.length(), 0.000001), 0.0, 1.0)
		time_remaining *= 1.0 - fraction
		var n := hit.get_normal()
		var collider := hit.get_collider()
		var body_velocity := hit.get_collider_velocity()
		var body_mass := 0.0
		var e := profile.wall_restitution
		var mu := profile.bounce_friction_coefficient
		var is_lower_contact := collider!=null and collider.has_method("get_ball_contact_owner")
		var is_player := collider is CharacterBody3D or is_lower_contact
		var contact_actor: CharacterBody3D = collider.get_ball_contact_owner() if is_lower_contact else collider if collider is CharacterBody3D else null
		if is_player:
			if is_lower_contact and collider.has_method("resolve_foot_ball_contact") and collider.resolve_foot_ball_contact(self,hit.get_position(),n,dt):
				motion=velocity*time_remaining
				continue
			if is_instance_valid(contact_actor) and contact_actor.has_method("resolve_interaction_ball_contact") and contact_actor.resolve_interaction_ball_contact(self,hit.get_position()):
				motion = velocity * time_remaining
				continue
			body_collision_count += 1
			body_velocity = collider.ball_contact_velocity(hit.get_position()) if is_lower_contact else collider.velocity
			body_mass = profile.player_mass_kg
			if collider.has_method("physics_mass_kg"):
				body_mass = collider.physics_mass_kg()
			e = profile.body_restitution
			mu = profile.body_friction_coefficient
			# A ground ball meets the legs horizontally; capsule foot curvature cannot launch it.
			if global_position.y <= contact_actor.global_position.y + radius + profile.ground_probe_m * 2.0:
				var flat_normal := Vector3(n.x, 0.0, n.z)
				if flat_normal.length_squared() > 0.000001:
					n = flat_normal.normalized()
			if grounded:
				var opposed: CharacterBody3D = null
				for seen in body_contacts_seen:
					if is_instance_valid(seen.body) and seen.body != contact_actor and seen.normal.dot(n) < -0.80:
						opposed = seen.body
						break
				if opposed and opposed.has_method("receive_body_impulse_ns") and contact_actor.has_method("receive_body_impulse_ns"):
					_settle_squeeze(opposed, contact_actor, n)
					squeeze_count += 1
					# Both normal constraints are active. Advance only the unconstrained
					# tangent; no repeated ball/body ping-pong and no possession change.
					motion = (velocity * time_remaining).slide(n)
					if motion.length_squared() < 0.000000000001:
						break
					continue
				body_contacts_seen.append({"body": contact_actor, "normal": n})
		elif n.y >= 0.70:
			e = profile.turf_restitution if -velocity.dot(n) > profile.low_bounce_cutoff_mps else 0.0
		var response := Contacts.sphere_response(velocity, spin_rads, body_velocity, n, body_mass, e, mu, profile, is_player and grounded)
		velocity = response.velocity
		spin_rads = response.spin
		if is_player and collider.has_method("receive_body_impulse_ns"):
			collider.receive_body_impulse_ns(-response.impulse_ns)
		if not is_player and n.y >= 0.70 and velocity.dot(n) <= profile.rest_speed_mps:
			velocity = velocity.slide(n)
			grounded = true
		physical_contact.emit(contact_actor if is_lower_contact else collider, hit.get_position(), response.impulse_ns)
		# Recompute the full vector from reflected velocity and unconsumed physical time.
		# Sliding/bouncing the old remainder would use stale pre-collision velocity.
		motion = velocity * time_remaining
		if fraction < 0.00001 and response.impulse_ns.length_squared() < 0.00000001:
			motion = motion.slide(n)
		if contact_index == profile.max_contacts_per_substep - 1:
			substep_budget_hits += 1
			contact_budget_exhausted.emit()
			# Stay at the safe swept position; never tunnel by applying leftover motion.

func _settle_squeeze(a: CharacterBody3D, b: CharacterBody3D, normal: Vector3) -> void:
	# Inelastic three-body normal constraint. All three share the mass-weighted
	# normal velocity, conserving momentum and removing trapped-contact energy.
	var n := Vector3(normal.x, 0.0, normal.z).normalized()
	var ma: float = a.physics_mass_kg() if a.has_method("physics_mass_kg") else profile.player_mass_kg
	var mb: float = b.physics_mass_kg() if b.has_method("physics_mass_kg") else profile.player_mass_kg
	var vb := velocity.dot(n)
	var va := a.velocity.dot(n)
	var vc := b.velocity.dot(n)
	var common := (mass_kg * vb + ma * va + mb * vc) / (mass_kg + ma + mb)
	velocity += n * (common - vb)
	var ja := n * (ma * (common - va))
	var jb := n * (mb * (common - vc))
	a.receive_body_impulse_ns(ja)
	b.receive_body_impulse_ns(jb)
	physical_contact.emit(a, global_position - n * radius, -ja)
	physical_contact.emit(b, global_position + n * radius, -jb)

func _enforce_finite_limits() -> void:
	if not velocity.is_finite() or not spin_rads.is_finite():
		push_error("Non-finite football state rejected")
		velocity = Vector3.ZERO
		spin_rads = Vector3.ZERO
	velocity = velocity.limit_length(profile.safety_max_speed_mps)
	spin_rads = spin_rads.limit_length(profile.safety_max_spin_rads)

func predict_free_flight(seconds: float, sample_dt: float = 1.0 / 120.0) -> PackedVector3Array:
	var points := PackedVector3Array([global_position])
	if not is_finite(seconds) or not is_finite(sample_dt) or seconds <= 0.0 or sample_dt <= 0.0:
		return points
	var pos := global_position
	var v := velocity
	var w := spin_rads
	var elapsed := 0.0
	while elapsed < seconds:
		var h := minf(profile.internal_step_seconds, seconds - elapsed)
		var state := Forces.airborne_step(v, w, h, wind_mps, profile)
		pos += state.motion
		v = state.velocity
		w = state.spin
		elapsed += h
		if elapsed >= points.size() * sample_dt or elapsed >= seconds:
			points.append(pos)
	return points
