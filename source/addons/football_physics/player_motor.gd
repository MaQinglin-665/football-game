class_name FootballPlayerMotor
extends CharacterBody3D

signal body_contact(other: CharacterBody3D, normal_to_self: Vector3, impulse_ns: Vector3)

const Contacts := preload("contact_math.gd")
@export var profile: FootballPhysicsProfile
@export var auto_step: bool = true
var move_intent: Vector3 = Vector3.ZERO
var sprint_intent: float = 0.0
var shield_intent: float = 0.0
var collision_count: int = 0

func _ready() -> void:
	if profile == null:
		profile = FootballPhysicsProfile.playable()
	assert(profile.validate())
	collision_layer = 2
	collision_mask = 7 # Also sweep stationary balls; only closing contacts can exchange momentum.
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	process_physics_priority = 10
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = profile.player_radius_m
	capsule.height = profile.player_height_m
	collision.shape = capsule
	collision.position.y = profile.player_height_m * 0.5
	add_child(collision)
	# An upright lower-body volume complements the capsule. Its vertical sides
	# prevent the rounded capsule bottom from climbing a ball on the turf.
	var lower_collision := CollisionShape3D.new()
	var lower_body := CylinderShape3D.new()
	lower_body.radius = profile.player_radius_m - 0.01
	lower_body.height = minf(0.95, profile.player_height_m - profile.player_radius_m)
	lower_body.margin = profile.sweep_margin_m
	lower_collision.name = "LowerBodyContact"
	lower_collision.shape = lower_body
	lower_collision.position.y = lower_body.height * 0.5
	add_child(lower_collision)

func _physics_process(dt: float) -> void:
	if auto_step:
		step_physics(dt)

func physics_mass_kg() -> float:
	return profile.player_mass_kg

func set_move_intent(direction_world: Vector3, sprint_01: float = 0.0, shield_01: float = 0.0) -> void:
	if not direction_world.is_finite() or not is_finite(sprint_01) or not is_finite(shield_01):
		move_intent = Vector3.ZERO
		return
	move_intent = Vector3(direction_world.x, 0.0, direction_world.z).limit_length(1.0)
	sprint_intent = clampf(sprint_01, 0.0, 1.0)
	shield_intent = clampf(shield_01, 0.0, 1.0)

func receive_body_impulse_ns(j_world: Vector3) -> void:
	if j_world.is_finite():
		# Shoulder/ball impacts have no vertical launch channel.
		velocity += Vector3(j_world.x, 0.0, j_world.z) / physics_mass_kg()

func step_physics(dt: float) -> void:
	if not is_finite(dt) or dt <= 0.0:
		return
	var count := maxi(1, int(ceil(dt / profile.internal_step_seconds - 0.000001)))
	for _i in range(count):
		_substep(dt / count)

func _substep(dt: float) -> void:
	advance_motor(dt)
	move_swept(dt)

func advance_motor(dt: float) -> void:
	var max_speed := motor_speed_limit(sprint_intent)
	max_speed = lerpf(max_speed, profile.shield_move_speed_mps, shield_intent)
	var desired := move_intent * max_speed
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var guard:bool=bool(get_meta("motor_guard",false))
	# Only the planted tackle phase commits direction; braking and recovery remain available.
	var foot_action=get("foot") if "foot" in self else null
	if foot_action!=null and foot_action.kind=="TACKLE" and not foot_action.idle() and foot_action.phase!=foot_action.Phase.RECOVER and not bool(foot_action.touch_plan.get("automatic",false)):
		var axis:Vector3=foot_action.direction
		desired=axis*maxf(0,desired.dot(axis))
	var after:=integrate_horizontal(flat,desired,dt,guard)
	velocity.x = after.x
	velocity.z = after.z
	velocity.y -= profile.gravity_mps2 * dt

func motor_speed_limit(sprint:float)->float:
	return lerpf(profile.jog_speed_mps,profile.sprint_speed_mps,sprint)

func integrate_horizontal(flat:Vector3,desired:Vector3,dt:float,guard:bool)->Vector3:
	var after:Vector3
	var hm=get("human_motion")
	if hm!=null and bool(get("is_human")) and bool(get("human_motion_enabled")) and not guard:
		after=hm.step(flat,desired,sprint_intent,dt) # R004 human-only curve
	else:
		after=preload("res://scripts/movement_inertia.gd").step(flat,desired,profile,sprint_intent,dt,guard)
	return after

func move_swept(dt: float, resolved_pairs: Dictionary = {}) -> void:
	var motion := velocity * dt
	var remaining := dt
	for _contact in range(profile.max_contacts_per_substep):
		if motion.length_squared() < 0.000000000001:
			break
		var hit := move_and_collide(motion, false, profile.sweep_margin_m, false)
		if hit == null:
			break
		collision_count += 1
		var fraction := clampf(hit.get_travel().length() / maxf(motion.length(), 0.000001), 0.0, 1.0)
		remaining *= 1.0 - fraction
		var collider := hit.get_collider()
		var n := hit.get_normal()
		if collider is FootballPhysicsBall:
			var ball_normal := -n
			var ground_ball: bool = collider.velocity.y <= 0.08 and collider.global_position.y <= global_position.y + collider.radius + profile.ground_probe_m * 2.0
			if ground_ball:
				ball_normal = Vector3(ball_normal.x, 0.0, ball_normal.z).normalized()
				n = -ball_normal
			var response := Contacts.sphere_response(collider.velocity, collider.spin_rads,
				velocity, ball_normal, physics_mass_kg(), profile.body_restitution,
				profile.body_friction_coefficient, collider.profile, ground_ball)
			collider.velocity = response.velocity
			collider.spin_rads = response.spin
			receive_body_impulse_ns(-response.impulse_ns)
			if response.impulse_ns.length_squared() > 0.0000001:
				collider.body_collision_count += 1
				collider.physical_contact.emit(self, hit.get_position(), response.impulse_ns)
			# The ball is advanced later in the same substep. Stop at this safe contact
			# while it moves away; do not chase a static snapshot through its shape.
			motion = (velocity * remaining).slide(n)
			if motion.length_squared() < 0.000000000001:
				break
			continue
		elif collider is FootballPlayerMotor:
			var pair_key := "%s:%s" % [mini(get_instance_id(), collider.get_instance_id()), maxi(get_instance_id(), collider.get_instance_id())]
			if not resolved_pairs.has(pair_key):
				var j := Contacts.body_pair_impulse(velocity, collider.velocity, n,
					physics_mass_kg(), collider.physics_mass_kg(), profile.shoulder_restitution,
					profile.shoulder_friction_coefficient)
				receive_body_impulse_ns(j)
				collider.receive_body_impulse_ns(-j)
				resolved_pairs[pair_key] = true
				if j.length_squared() > 0.0000001:
					body_contact.emit(collider, n, j)
					collider.body_contact.emit(self, -n, -j)
			n = Vector3(n.x, 0.0, n.z).normalized()
		else:
			if velocity.dot(n) < 0.0:
				velocity = velocity.slide(n)
		motion = velocity * remaining
		if fraction < 0.00001:
			motion = motion.slide(n)
