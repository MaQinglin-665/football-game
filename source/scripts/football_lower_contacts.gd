extends Node3D
## Ball-only shin/boot proxies from the real skeleton; no self/player collision.
## Active semantic foot actions own contact, so passive shoe collisions cannot
## inject a second impulse into the same interaction (IOSoccer action priority).
class ContactBody extends AnimatableBody3D:
	var actor: Node3D
	var part := ""
	var measured_velocity := Vector3.ZERO
	var previous_point := Vector3.ZERO
	var initialized := false
	var substep_origin:=Vector3.ZERO
	var substep_dt:=0.0
	var substep_frame:=-1
	func begin_ball_substep(dt:float)->void:
		substep_origin=global_position
		substep_dt=dt
		substep_frame=Engine.get_physics_frames()
	func resolve_foot_ball_contact(ball:Node3D,point:Vector3,normal:Vector3,dt:float)->bool:
		ball.last_lower_contact_frame=Engine.get_physics_frames()
		if not part.begins_with("boot.") or actor.foot==null:return false
		var side:int=-1 if part.ends_with("L") else 1
		if not actor.foot.resolve_physical_contact(side,point,normal,dt):return false
		# Immediate handover inside this same World sweep, before any second impulse.
		get_parent().update_from_skeleton(0.0)
		return true
	func get_ball_contact_owner() -> CharacterBody3D: return actor
	func ball_contact_velocity(_point: Vector3) -> Vector3:
		# World sweeps after skeletal posing: use the translation being resolved
		# now, not last animation frame's (possibly much faster) ankle movement.
		if substep_frame==Engine.get_physics_frames() and substep_dt>0:
			return (global_position-substep_origin)/substep_dt
		return measured_velocity
	func physics_mass_kg() -> float: return actor.physics_mass_kg()
	func receive_body_impulse_ns(impulse: Vector3) -> void: actor.receive_body_impulse_ns(impulse)

var actor: Node3D
var parts := {}
var updates := 0

func _ready() -> void:
	name = "LowerBallContacts"
	process_physics_priority = -19 # After foot actions, before the sole World.
	for side in ["L","R"]:
		var shin := CapsuleShape3D.new()
		shin.radius = .033
		shin.height = .44
		_add_part("shin."+side,shin)
		var thigh:=CapsuleShape3D.new()
		thigh.radius=.065
		thigh.height=.43
		_add_part("thigh."+side,thigh)
		var boot := BoxShape3D.new()
		boot.size = Vector3(.065,.105,.285)
		_add_part("boot."+side,boot)
	update_from_skeleton(0.0)

func _add_part(part: String, shape: Shape3D) -> void:
	var body := ContactBody.new()
	body.name = part.replace(".","_")
	body.actor = actor
	body.part = part
	body.sync_to_physics = false
	body.collision_layer = 8
	body.collision_mask = 4
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	parts[part] = body

func _physics_process(delta: float) -> void:
	var began:int=Time.get_ticks_usec()
	_sync_physics(delta)
	preload("res://scripts/frame_spike_watch.gd").proxy_us+=Time.get_ticks_usec()-began

func _sync_physics(delta:float)->void:
	if preload("res://scripts/visual_pose_cadence39.gd").far_visual(actor):
		# Frozen local bone transforms still follow the live root. Visual LOD
		# never disables physical legs; the incoming horizon promotes exact pose.
		for body in parts.values():
			body.collision_layer=8 if actor.visible else 0
			body.measured_velocity=actor.velocity
			body.initialized=false
		return
	if actor.has_method("ensure_contact_pose_current") and preload("res://scripts/visual_pose_cadence39.gd").needs_exact_contact_pose(actor):actor.ensure_contact_pose_current()
	update_from_skeleton(delta)

func update_from_skeleton(delta: float) -> void:
	if not is_instance_valid(actor.avatar) or not is_instance_valid(actor.avatar.skeleton): return
	var skeleton: Skeleton3D = actor.avatar.skeleton
	var game: Node = actor.match_controller
	var skeleton_world:Transform3D=skeleton.global_transform
	var local_from_world:Transform3D=global_transform.affine_inverse()
	var action_owns_contact: bool = is_instance_valid(game.ball) and game.ball.locks_lower_contact(actor) and not actor.is_human
	for side in ["L","R"]:
		var knee := skeleton_world*skeleton.get_bone_global_pose(actor.avatar.cached_bone_id("shin."+side))
		var hip:=skeleton_world*skeleton.get_bone_global_pose(actor.avatar.cached_bone_id("thigh."+side))
		var thigh_axis:Vector3=knee.origin-hip.origin
		var thigh_pose:=Transform3D(Basis(Quaternion(Vector3.UP,thigh_axis.normalized())),(hip.origin+knee.origin)*.5)
		var foot := skeleton_world*skeleton.get_bone_global_pose(actor.avatar.cached_bone_id("foot."+side))
		var axis := foot.origin-knee.origin
		var shin_pose := Transform3D(Basis(Quaternion(Vector3.UP,axis.normalized())),(foot.origin+knee.origin)*.5)
		var boot_pose := foot
		boot_pose.origin = foot*Vector3(0,-.0525,-.095)
		var shoe_owned:bool=action_owns_contact
		if actor.foot!=null and (actor.is_human or actor.foot.kind=="TACKLE"):
			shoe_owned=actor.foot.protects_shoe(-1 if side=="L" else 1)
			# During a finite action, an overlapping support shoe yields to the
			# semantic contact. Far support/idle legs retain physical collisions.
			if is_instance_valid(game.ball) and (not actor.foot.idle() or game.ball.last_contact_actor==actor and game.ball.touch_age<.18):
				var local:Vector3=boot_pose.affine_inverse()*game.ball.position
				var nearest:Vector3=local.clamp(-Vector3(.0325,.0525,.1425),Vector3(.0325,.0525,.1425))
				shoe_owned=shoe_owned or local.distance_to(nearest)<game.ball.radius+.045
		# Incoming balls must still see both boots while a receive/block is winding
		# up. Only the selected boot can settle an action; others deflect passively.
		if actor.foot!=null and (actor.foot.kind in ["RECEIVE","TACKLE"] or actor.foot.kind=="PASS" and bool(actor.foot.kick_intent.get("one_touch_pass",false))) and not actor.foot.hit and not actor.foot.idle():
			shoe_owned=false
		# Foreign incoming balls never inherit another action's shoe immunity.
		var own_ball:bool=is_instance_valid(game.ball) and (game.ball.carrier==actor or game.ball.last_contact_actor==actor and game.ball.touch_age<.18)
		if not own_ball:shoe_owned=false
		_set_pose(parts["thigh."+side],thigh_pose,delta,false,local_from_world)
		_set_pose(parts["shin."+side],shin_pose,delta,shoe_owned,local_from_world)
		_set_pose(parts["boot."+side],boot_pose,delta,shoe_owned,local_from_world)
	updates += 1

func _set_pose(body: ContactBody, pose: Transform3D, delta: float, action_owns_contact: bool, local_from_world:Transform3D) -> void:
	if body.initialized and delta>0:
		body.measured_velocity = ((pose.origin-body.previous_point)/delta).limit_length(18.0)
	else: body.measured_velocity = Vector3(actor.velocity.x,0,actor.velocity.z)
	body.transform = local_from_world*pose
	body.previous_point = pose.origin
	body.initialized = true
	var wanted_layer:int=0 if action_owns_contact or not actor.visible else 8
	if body.collision_layer!=wanted_layer:body.collision_layer=wanted_layer

func snapshot() -> Dictionary:
	var result := {}
	for part in parts:
		var body: ContactBody = parts[part]
		result[part] = {"position":body.global_position,"velocity":body.measured_velocity,"active":body.collision_layer==8,"shape":body.get_child(0).shape.get_class()}
	return result
