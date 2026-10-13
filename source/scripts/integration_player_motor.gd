extends "res://addons/football_physics/player_motor.gd"
## MIT: adapted frozen player_motor.move_swept with zero-normal guards.
## This host shim changes no body response, acceleration or finite integration.
var invalid_normal_contacts := 0
var origin_ground_frame := -1
var origin_ground_y := 0.0
var origin_ground_supported := false

func _ready() -> void:
	super._ready()
	# The motor capsule handles torso/shoulder motion. Ground balls see only
	# the distinct skeletal shin/boot bodies, not a solid lower-body wall.
	for child in get_children():
		if not child is CollisionShape3D: continue
		if child.name=="LowerBodyContact":
			child.disabled = true
			child.queue_free()
		elif child.shape is CapsuleShape3D:
			child.shape.height = 1.12
			child.position.y = 1.24
	collision_mask = 3 # Environment + other torsos; ball sweeps contacts itself.

func advance_motor(dt: float) -> void:
	super.advance_motor(dt)
	_apply_origin_ground_support(dt)

func _apply_origin_ground_support(dt: float) -> void:
	# A terrain support constraint at the actor's foot origin lets the raised
	# torso capsule move normally without falling 0.68m through the field.
	# It changes vertical velocity at support, never the actor/ball position.
	var frame := Engine.get_physics_frames()
	if frame!=origin_ground_frame:
		origin_ground_frame = frame
		var query := PhysicsRayQueryParameters3D.create(global_position+Vector3.UP*.12,global_position+Vector3.DOWN*.20,1,[get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		origin_ground_supported = not hit.is_empty() and hit.normal.y>=.70
		if origin_ground_supported: origin_ground_y = hit.position.y
	if origin_ground_supported and velocity.y<0:
		var allowed := (origin_ground_y+.002-global_position.y)/maxf(dt,.000001)
		velocity.y = maxf(velocity.y,allowed)

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
		if not n.is_finite() or n.length_squared()<0.5:
			invalid_normal_contacts += 1
			break
		if collider is FootballPhysicsBall:
			if has_method("resolve_interaction_ball_contact") and call("resolve_interaction_ball_contact",collider,hit.get_position()):
				motion = (velocity * remaining).slide(n)
				continue
			var ball_normal := -n
			var ground_ball: bool = collider.velocity.y <= 0.08 and collider.global_position.y <= global_position.y + collider.radius + profile.ground_probe_m * 2.0
			if ground_ball:
				ball_normal = Vector3(ball_normal.x, 0.0, ball_normal.z).normalized()
				n = -ball_normal
				if n.length_squared()<0.5:
					invalid_normal_contacts += 1
					velocity.y = maxf(velocity.y,0)
					break
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
				if has_method("observe_interaction_body_collision"):
					call("observe_interaction_body_collision",collider,n,j,hit.get_position(),hit.get_local_shape(),hit.get_collider_shape())
				if collider.has_method("observe_interaction_body_collision"):
					collider.call("observe_interaction_body_collision",self,-n,-j,hit.get_position(),hit.get_collider_shape(),hit.get_local_shape())
				resolved_pairs[pair_key] = true
				if j.length_squared() > 0.0000001:
					body_contact.emit(collider, n, j)
					collider.body_contact.emit(self, -n, -j)
			n = Vector3(n.x, 0.0, n.z).normalized()
			if n.length_squared()<0.5:
				invalid_normal_contacts += 1
				break
		else:
			if velocity.dot(n) < 0.0:
				velocity = velocity.slide(n)
		motion = velocity * remaining
		if fraction < 0.00001:
			motion = motion.slide(n)
