class_name FootballPhysicsWorld
extends Node
## Recommended scheduler: all actor accelerations, pair contacts, then ball, per substep.
## Input/foot animations still belong to the host. They issue impulses before this node.
@export var profile: FootballPhysicsProfile
@export var auto_step: bool = true
var actors: Array[FootballPlayerMotor] = []
var balls: Array[FootballPhysicsBall] = []
var step_serial: int = 0
var body_contact_budget_hits: int = 0

func _ready() -> void:
	if profile == null:
		profile = FootballPhysicsProfile.playable()
	process_physics_priority = 20

func register_actor(actor: FootballPlayerMotor) -> void:
	if not actors.has(actor):
		actors.append(actor)
	actor.auto_step = false

func register_ball(ball: FootballPhysicsBall) -> void:
	if not balls.has(ball):
		balls.append(ball)
	ball.auto_step = false

func _physics_process(dt: float) -> void:
	if auto_step:
		var began:int=Time.get_ticks_usec()
		step_physics(dt)
		preload("res://scripts/frame_spike_watch.gd").world_us+=Time.get_ticks_usec()-began

func step_physics(dt: float) -> void:
	if not is_finite(dt) or dt <= 0.0:
		return
	var count := maxi(1, int(ceil(dt / profile.internal_step_seconds - 0.000001)))
	var h := dt / count
	for ball in balls:
		if is_instance_valid(ball):
			ball.previous_position = ball.global_position
	for _i in range(count):
		step_serial += 1
		var pairs := {}
		for actor in actors:
			if is_instance_valid(actor):
				actor.advance_motor(h)
		var relative_rows:Dictionary={}
		for ball in balls:
			if is_instance_valid(ball) and "held" in ball:
				relative_rows[ball.get_instance_id()]={"from":ball.global_position,"count":ball.collision_count,"rows":preload("res://scripts/relative_boot_block.gd").snapshot(actors,ball,h)}
		_move_actor_group(h, pairs)
		for ball in balls:
			if is_instance_valid(ball):
				ball._substep(h)
				var row:Dictionary=relative_rows.get(ball.get_instance_id(),{})
				if not row.is_empty():preload("res://scripts/relative_boot_block.gd").settle(ball,row.rows,row.from,int(row.count),h)
	for ball in balls:
		if is_instance_valid(ball):
			ball._enforce_finite_limits()

func _move_actor_group(dt: float, pairs: Dictionary) -> void:
	var remaining := dt
	var candidates := _candidate_pairs(dt)
	for _contact_iteration in range(profile.max_body_pairs_per_substep):
		var next := _earliest_pair(remaining, pairs, candidates)
		if next.is_empty():
			for actor in actors:
				if is_instance_valid(actor):
					actor.move_swept(remaining, pairs)
			return
		var a: FootballPlayerMotor = next.a
		var b: FootballPlayerMotor = next.b
		var normal: Vector3 = next.normal
		var key: String = next.key
		var travel_time: float = next.time
		pairs[key] = true
		# Advance to the actual continuous contact before changing momentum.
		if travel_time > 0.0000001:
			for actor in actors:
				if is_instance_valid(actor):
					actor.move_swept(travel_time, pairs)
		remaining -= travel_time
		var j := FootballContactMath.body_pair_impulse(a.velocity, b.velocity, normal,
			a.physics_mass_kg(), b.physics_mass_kg(), profile.shoulder_restitution,
			profile.shoulder_friction_coefficient)
		a.receive_body_impulse_ns(j)
		b.receive_body_impulse_ns(-j)
		if j.length_squared() > 0.0000001:
			a.body_contact.emit(b, normal, j)
			b.body_contact.emit(a, -normal, -j)
		if remaining <= 0.0000001:
			return
	# Crowded contacts stay at the safe swept positions rather than applying leftover
	# overlapping motion. Next fixed substep resumes normally.
	body_contact_budget_hits += 1

func _candidate_pairs(dt: float) -> Array:
	var candidates: Array = []
	# No actor mutation occurs while enumerating this broad phase. Read the
	# same current substep state once per valid actor, preserving roster order.
	var live: Array[FootballPlayerMotor] = []
	var positions := PackedVector3Array()
	var radii := PackedFloat64Array()
	var speeds := PackedFloat64Array()
	for actor in actors:
		if not is_instance_valid(actor): continue
		live.append(actor)
		positions.append(actor.global_position)
		radii.append(actor.profile.player_radius_m)
		speeds.append(maxf(actor.velocity.length(), actor.profile.sprint_speed_mps))
	for i in range(live.size()):
		for k in range(i + 1, live.size()):
			var offset := positions[i] - positions[k]
			offset.y = 0.0
			var radius_sum := radii[i] + radii[k]
			var speed_sum := speeds[i] + speeds[k]
			# Identical conservative bound: impact may redistribute speeds.
			var reach := radius_sum + speed_sum * dt * 2.0
			if offset.length_squared() > reach * reach: continue
			var a := live[i]
			var b := live[k]
			var key := "%s:%s" % [mini(a.get_instance_id(), b.get_instance_id()), maxi(a.get_instance_id(), b.get_instance_id())]
			candidates.append([a, b, key])
	return candidates

func _earliest_pair(dt: float, pairs: Dictionary, candidates: Array) -> Dictionary:
	# Engine shape sweeps see each other body at its current PhysicsServer transform.
	# This relative-motion sweep also catches two bodies moving into the same gap
	# within one substep. It applies velocity impulses, never position corrections.
	var earliest := {}
	var earliest_time := dt + 0.0000001
	for candidate in candidates:
			var a: FootballPlayerMotor = candidate[0]
			var b: FootballPlayerMotor = candidate[1]
			var key: String = candidate[2]
			if pairs.has(key):
				continue
			var a_bounds := _vertical_bounds(a)
			var b_bounds := _vertical_bounds(b)
			if minf(a_bounds.y,b_bounds.y) < maxf(a_bounds.x,b_bounds.x):
				continue
			var offset := a.global_position - b.global_position
			offset.y = 0.0
			var relative := a.velocity - b.velocity
			relative.y = 0.0
			var combined_radius := a.profile.player_radius_m + b.profile.player_radius_m
			var c := offset.length_squared() - combined_radius * combined_radius
			var impact_time := 0.0
			if c > 0.0:
				var aa := relative.length_squared()
				var bb := 2.0 * offset.dot(relative)
				if aa < 0.0000001 or bb >= 0.0:
					continue
				var discriminant := bb * bb - 4.0 * aa * c
				if discriminant < 0.0:
					continue
				impact_time = (-bb - sqrt(discriminant)) / (2.0 * aa)
				if impact_time < 0.0 or impact_time > dt:
					continue
			var normal := (offset + relative * impact_time).normalized()
			if relative.dot(normal) >= -0.00001:
				continue
			if impact_time < earliest_time:
				earliest_time = impact_time
				earliest = {"a": a, "b": b, "time": impact_time, "normal": normal, "key": key}
	return earliest

func _vertical_bounds(actor: FootballPlayerMotor) -> Vector2:
	if actor.has_method("interaction_vertical_bounds"): return actor.call("interaction_vertical_bounds")
	return Vector2(actor.global_position.y,actor.global_position.y+actor.profile.player_height_m)
