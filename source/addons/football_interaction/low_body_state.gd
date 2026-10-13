extends Node
## Minimal local fall/get-up. Uses the host motor/World for every translation.
## enter_hit consumes posture once; the contact solver has already applied momentum.
signal state_event(event: Dictionary)
const Pose := preload("low_action_pose.gd")
const GETUP_SECONDS := .55
const HEAD_RADIUS := .125
var game: Node
var actor: CharacterBody3D
var owner_interaction: Node
var state := "IDLE"
var direction := Vector3.FORWARD
var age := 0.0
var minimum_down := .45
var weight := 0.0
var getup_age := 0.0
var stand_blocked := false
var action_id := ""
var falls := 0
var recoveries := 0
var duplicate_hits := 0
var seen: Dictionary = {}
var history: Array[Dictionary] = []
var records: Array[Dictionary] = []
var volume: CollisionShape3D
var head_shape: CollisionShape3D
var own_head := false

func setup(host: Node, body: CharacterBody3D, originals: Array[Dictionary] = [], head: CollisionShape3D = null, interaction: Node = null) -> void:
	game = host
	actor = body
	records = originals
	head_shape = head
	owner_interaction = interaction

func _ready() -> void:
	name = "LowBodyState"
	process_physics_priority = -43
	if records.is_empty():
		for child in actor.get_children():
			if child is CollisionShape3D and not child.is_queued_for_deletion() and not child.disabled and (child.shape is CapsuleShape3D or child.shape is CylinderShape3D):
				records.append({"node":child,"shape":child.shape.duplicate(),"transform":child.transform})
	volume = CollisionShape3D.new()
	volume.name = "LowBodyContact"
	var capsule := CapsuleShape3D.new()
	capsule.radius = actor.profile.player_radius_m
	capsule.height = 1.25
	capsule.margin = actor.profile.sweep_margin_m
	volume.shape = capsule
	volume.disabled = true
	actor.add_child(volume)
	if head_shape == null:
		own_head = true
		head_shape = CollisionShape3D.new()
		head_shape.name = "FallenHeadContact"
		var sphere := SphereShape3D.new()
		sphere.radius = HEAD_RADIUS
		head_shape.shape = sphere
		head_shape.disabled = true
		actor.add_child(head_shape)
	actor.avatar.action_pose_sampled.connect(Pose.apply)

func blocked() -> bool:
	return state != "IDLE"

func set_slide(value: float, forward: Vector3, id: String) -> void:
	state = "SLIDE"
	direction = forward
	action_id = id
	weight = clampf(value,0.0,1.0)
	apply_volume()

@export var running_fall_speed := 2.2

func enter_hit(id: String, forward: Vector3, down_seconds := .45, proof:Dictionary = {}) -> bool:
	if not bool(proof.get("contact",false)) or float(proof.get("speed",0))<running_fall_speed:return false
	var cause:String=String(proof.get("cause",""))
	if cause!="extended_leg":return false
	return _enter_low(id,forward,down_seconds,true)

func enter_recovery(id:String,forward:Vector3,down_seconds:=.18)->bool:
	# Only voluntary slide/dive completion can use this posture handoff.
	return _enter_low(id,forward,down_seconds,false)

func _enter_low(id:String,forward:Vector3,down_seconds:float,collision_fall:bool)->bool:
	if seen.has(id):
		duplicate_hits += 1
		return false
	seen[id] = true
	if seen.size()>64: seen.erase(seen.keys()[0])
	# A second hit cannot reset a fall/get-up timer, restart animation or add force.
	if state in ["DOWN","CRAWL","GETUP"]: return false
	state = "DOWN"
	age = 0.0
	getup_age = 0.0
	minimum_down = down_seconds
	direction = Vector3(forward.x,0,forward.z).normalized()
	if direction.length_squared()<.5: direction = actor.facing
	action_id = id
	weight = 1.0
	clear_action_cache()
	if game.ball.carrier == actor: game.ball.detach()
	apply_volume()
	actor.refresh_pose(0.0)
	sync_head_shape()
	if collision_fall: falls += 1
	_emit("FALLEN")
	return true

func clear_action_cache() -> void:
	actor.foot.cancel()
	if actor is FootballAgent:
		actor.pending_kick.clear()
		actor.pending_age = 0.0
	elif is_instance_valid(owner_interaction):
		owner_interaction.clear_protected_actions()

func _physics_process(delta: float) -> void:
	if state in ["IDLE","SLIDE"] or game.phase in [game.Phase.MENU,game.Phase.PAUSED,game.Phase.FINISHED]: return
	clear_action_cache()
	age += delta
	stand_blocked = not can_stand()
	if state in ["DOWN","CRAWL"]:
		weight = 1.0
		if age>=minimum_down and flat_speed()<2.1 and grounded() and not stand_blocked:
			state = "GETUP"
			getup_age = 0.0
			_emit("GETUP_BEGIN")
		elif age>=minimum_down+.8: state = "CRAWL"
	elif state == "GETUP":
		# Full original volume is checked before any growth, including every frame.
		if stand_blocked:
			state = "CRAWL"
			weight = 1.0
			getup_age = 0.0
			_emit("GETUP_BLOCKED")
		else:
			getup_age += delta
			weight = 1.0-smoothstep(0.0,1.0,getup_age/GETUP_SECONDS)
			if getup_age>=GETUP_SECONDS:
				clear_action_cache()
				state = "IDLE"
				weight = 0.0
				recoveries += 1
				_emit("RECOVERED")
	apply_volume()
	actor.refresh_pose(0.0)
	sync_head_shape()

func override_motor(dt: float) -> bool:
	if not blocked() or state == "SLIDE": return false
	var flat := Vector3(actor.velocity.x,0,actor.velocity.z)
	var desired := Vector3.ZERO
	if state == "CRAWL":
		if actor.is_human:
			if actor.input_enabled and is_instance_valid(owner_interaction) and owner_interaction.allowed():
				desired = actor.semantic_motion.limit_length(1)*.65
		elif actor.active:
			var offset: Vector3 = actor.target-actor.global_position
			desired = Vector3(offset.x,0,offset.z).limit_length(1)*.65
	flat = flat.move_toward(desired,7.0*dt)
	actor.velocity.x = flat.x
	actor.velocity.z = flat.z
	actor.velocity.y -= actor.profile.gravity_mps2*dt
	return true

func flat_speed() -> float:
	return Vector2(actor.velocity.x,actor.velocity.z).length()

func grounded() -> bool:
	var ray := PhysicsRayQueryParameters3D.create(actor.global_position+Vector3.UP*.025,actor.global_position-Vector3.UP*.045,1,[actor.get_rid()])
	return actor.velocity.y<=.1 and not actor.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func pose_state() -> Dictionary:
	return {"low_weight":weight,"low_state":state,"action_id":action_id,"crouch":0.0,"airborne":false,"mobility_busy":true}

func apply_volume() -> void:
	var low := blocked()
	for item in records: (item.node as CollisionShape3D).disabled = low
	volume.disabled = not low
	if own_head: head_shape.disabled = not low
	if not low: return
	var radius: float = volume.shape.radius
	var height: float = lerpf(actor.profile.player_height_m,1.25,weight)
	volume.shape.height = height
	var angle := PI*.5*weight
	var axis := Vector3.UP*cos(angle)+direction*sin(angle)
	var extent_y: float = radius+(height*.5-radius)*absf(axis.y)
	var center := actor.global_position-direction*.16*weight+Vector3.UP*extent_y
	volume.global_transform = Transform3D(Basis(Quaternion(Vector3.UP,axis)),center)

func sync_head_shape() -> void:
	if not blocked(): return
	var skeleton: Skeleton3D = actor.avatar.skeleton
	var head: Vector3 = skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone("head"))*Vector3(0,.105,0))
	head_shape.position = actor.to_local(head)

func vertical_bounds() -> Vector2:
	var radius: float = volume.shape.radius
	var half_segment: float = volume.shape.height*.5-radius
	var extent: float = radius+half_segment*absf(volume.global_basis.y.y)
	return Vector2(minf(volume.global_position.y-extent,head_shape.global_position.y-HEAD_RADIUS),maxf(volume.global_position.y+extent,head_shape.global_position.y+HEAD_RADIUS))

func can_stand() -> bool:
	for item in records:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = item.shape
		query.transform = actor.global_transform*(item.transform as Transform3D)
		query.transform.origin += Vector3.UP*.004
		query.collision_mask = 7
		query.exclude = [actor.get_rid()]
		var lower: Node = actor.get_node_or_null("LowerBallContacts")
		if is_instance_valid(lower):
			for body in lower.get_children():
				if body is PhysicsBody3D: query.exclude.append(body.get_rid())
		query.margin = .001
		if not actor.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): return false
	return true

func _emit(kind: String) -> void:
	var row := {"kind":kind,"action_id":action_id,"state":state,"age":age,"physics_frame":Engine.get_physics_frames()}
	history.append(row)
	if history.size()>64: history.pop_front()
	state_event.emit(row)
