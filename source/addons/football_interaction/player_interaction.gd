extends Node
## Batch 01: real jump, crouch volume, and a single deliberate aerial head contact.
## Actor/ball transforms remain owned by the existing swept physics World.
signal action_event(event: Dictionary)

const Pose := preload("interaction_pose.gd")
const JUMP_ACTION := &"ff_interaction_jump"
const CROUCH_ACTION := &"ff_interaction_crouch"
const JUMP_SPEED := 4.4
const CROUCH_DROP := .62
const HEAD_RADIUS := .125
const HEAD_OFFSET := Vector3(0, .105, 0)
const HEADER_PREPARE := .055
const HEADER_WINDOW := .12
const HEADER_RECOVER := .18
const LAND_RECOVER := .12
var game: Node
var actor: CharacterBody3D
var phase := "GROUNDED"
var crouch := 0.0
var stand_blocked := false
var jump_id := ""
var header_id := ""
var header_phase := "IDLE"
var header_age := 0.0
var header_used := false
var header_consumed := false
var landing_left := 0.0
var aim := Vector3.FORWARD
var serial := 0
var jumps := 0
var headers := 0
var misses := 0
var suppressed_contacts := 0
var input_conflicts: Array[Dictionary] = []
var history: Array[Dictionary] = []
var _shapes: Array[Dictionary] = []
var _head_shape: CollisionShape3D
var _pending_jump := false
var _pending_header := false
var _crouch_held := false
var _down: Dictionary = {}
var _blocked: Dictionary = {}
var _owns_shot := false
var _scope := ""
var _was_allowed := false
var _head_before := Vector3.ZERO
var _ball_before := Vector3.ZERO
var _head_hit_frame := -1
var _head_hit_ball_id := 0
var _passive_frame := -1
var _body_count_before := 0
var _camera_stand_y := 1.60
var _post: Node

class PostStep extends Node:
	var interaction: Node
	func _physics_process(delta: float) -> void:
		interaction.after_world(delta)

func setup(match_host: Node) -> void:
	game = match_host
	actor = game.player
	actor.interaction = self

func _ready() -> void:
	name = "PlayerInteraction"
	process_physics_priority = -42 # Input(-50), tactics(-45), this, actor(-40), feet(-20), World(20).
	_install_binding(JUMP_ACTION, KEY_J)
	_install_binding(CROUCH_ACTION, KEY_B)
	_audit_bindings()
	_camera_stand_y = actor.head.position.y
	for child in actor.get_children():
		if child is CollisionShape3D and not child.is_queued_for_deletion() and not child.disabled and (child.shape is CapsuleShape3D or child.shape is CylinderShape3D):
			var original: Shape3D = child.shape.duplicate()
			child.shape = child.shape.duplicate()
			_shapes.append({"node": child, "shape": original, "transform": child.transform})
	_head_shape = CollisionShape3D.new()
	_head_shape.name = "InteractionHeadContact"
	var head_sphere := SphereShape3D.new()
	head_sphere.radius = HEAD_RADIUS
	head_sphere.margin = actor.profile.sweep_margin_m
	_head_shape.shape = head_sphere
	actor.add_child(_head_shape)
	actor.avatar.action_pose_sampled.connect(Pose.apply)
	_apply_shape_height()
	sync_head_shape()
	_post = PostStep.new()
	_post.interaction = self
	_post.process_physics_priority = 30
	add_child(_post)

func _install_binding(action: StringName, code: int) -> void:
	if InputMap.has_action(action): return
	InputMap.add_action(action)
	var event := InputEventKey.new()
	event.physical_keycode = code
	InputMap.action_add_event(action, event)

func _audit_bindings() -> void:
	input_conflicts.clear()
	for action in [JUMP_ACTION, CROUCH_ACTION]:
		for event in InputMap.action_get_events(action):
			for other in InputMap.get_actions():
				if other == action or String(other).begins_with("ui_"): continue
				for bound in InputMap.action_get_events(other):
					if event.is_match(bound): input_conflicts.append({"action": action, "other": other})

func allowed() -> bool:
	return game.phase == game.Phase.PLAY and game.input_bridge.focused and actor.input_enabled \
		and not game.hud.help.visible and not game.hud.credits.visible

func _input(event: InputEvent) -> void:
	var token := ""
	if event.is_action(JUMP_ACTION): token = "jump"
	elif event.is_action(CROUCH_ACTION): token = "crouch"
	elif event.is_action("ff_shot") and (phase == "AIRBORNE" or _owns_shot): token = "header"
	elif event.is_action_pressed("ff_cancel") or event.is_action_pressed("ff_pass"):
		if header_phase != "IDLE": cancel_header("input_cancel")
		return
	if token.is_empty(): return
	if event is InputEventKey and event.echo: return
	var pressed: bool = event.is_pressed()
	var was_down: bool = _down.get(token, false)
	_down[token] = pressed
	if not pressed:
		_blocked.erase(token)
		if token == "crouch": _crouch_held = false
		if token == "header" and _owns_shot:
			_owns_shot = false
			get_viewport().set_input_as_handled()
		return
	if token == "header": _owns_shot = true
	if event is InputEventKey and (event.alt_pressed or event.meta_pressed):
		_blocked[token] = true
		return # Leave OS chords to Windows; a later bare edge must be a fresh press.
	if not allowed():
		_blocked[token] = true
		return # Keep MENU/reset controls available to their existing owners.
	get_viewport().set_input_as_handled()
	if not accepts_mobility_input():
		_blocked[token] = true
		return
	if was_down or _blocked.has(token) or not input_conflicts.is_empty(): return
	if token == "jump": _pending_jump = true
	elif token == "crouch": _crouch_held = true
	elif token == "header": _pending_header = true

func _physics_process(delta: float) -> void:
	var scope := "%s:%s:%s" % [game.match_generation, game.formation_serial, game.ball.get_instance_id()]
	var enabled: bool = allowed()
	if scope != _scope or (_was_allowed and not enabled):
		cancel_inputs("context_barrier")
	_scope = scope
	_was_allowed = enabled
	if game.phase in [game.Phase.MENU, game.Phase.PAUSED, game.Phase.FINISHED]: return
	if _step_exclusive(delta, enabled): return
	landing_left = maxf(0.0, landing_left - delta)
	if phase == "LANDING" and landing_left <= 0.0: phase = "GROUNDED"
	if _pending_jump:
		_pending_jump = false
		if enabled: _start_jump()
	var want_crouch: bool = enabled and _crouch_held and phase != "AIRBORNE"
	stand_blocked = not want_crouch and crouch > 0.0 and not can_stand()
	var target: float = 1.0 if want_crouch or stand_blocked else 0.0
	var previous: float = crouch
	crouch = move_toward(crouch, target, 7.0 * delta)
	if previous <= .001 and crouch > .001: _cancel_ground_actions("crouch")
	_apply_shape_height()
	# 022 body-eye anchor owns camera position from the final sampled head.
	if _pending_header:
		_pending_header = false
		if enabled: _start_header()
	if header_phase != "IDLE":
		header_age += delta
		header_phase = "PREPARE" if header_age < HEADER_PREPARE else "CONTACT" if header_age < HEADER_PREPARE+HEADER_WINDOW else "RECOVER"
		if header_age >= HEADER_PREPARE+HEADER_WINDOW+HEADER_RECOVER: cancel_header("miss" if not header_consumed else "completed")
	# Keep the existing ordinary foot/contact pose cadence when interaction is idle.
	if not permits_foot_action(): actor.refresh_pose(0.0)
	sync_head_shape()
	_head_before = head_center()
	_ball_before = game.ball.global_position
	_body_count_before = game.ball.body_collision_count
	# Sweeps can ignore initial overlap. An exact sphere overlap is checked separately.
	if _header_active(): _try_header(game.ball, "initial_overlap")

func after_world(_delta: float) -> void:
	if game.phase in [game.Phase.MENU, game.Phase.PAUSED, game.Phase.FINISHED]: return
	sync_head_shape()
	if phase == "AIRBORNE" and grounded():
		phase = "LANDING"
		landing_left = LAND_RECOVER
		cancel_header("landed")
		_emit({"kind": "LANDED", "action_id": jump_id})
	# Relative motion of the actual sampled head and actual ball during this World tick.
	# Engine contacts are authoritative; never add a retrospective second body impulse.
	if _header_active() and _passive_frame != Engine.get_physics_frames() and game.ball.body_collision_count == _body_count_before:
		var end: Vector3 = game.ball.global_position - head_center()
		var start: Vector3 = _ball_before - _head_before
		var relative: Vector3 = end-start
		var closest: Vector3 = Geometry3D.get_closest_point_to_segment(Vector3.ZERO, start, end)
		var travel: float = (game.ball.global_position-_ball_before).length() + (head_center()-_head_before).length()
		if travel < 1.0 and closest.length() <= HEAD_RADIUS+game.ball.radius and relative.length_squared() > .00000001:
			var t: float = clampf(-start.dot(relative)/relative.length_squared(), 0.0, 1.0)
			var normal: Vector3 = closest.normalized() if closest.length() > .0001 else aim
			var point: Vector3 = _head_before.lerp(head_center(), t) + normal*HEAD_RADIUS
			var query := PhysicsRayQueryParameters3D.create(_ball_before, point, 3, [actor.get_rid(), game.ball.get_rid()])
			if actor.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
				_resolve_header(game.ball, point, normal, "relative_sweep", closest.length(), t)

func grounded() -> bool:
	if actor.velocity.y > .10: return false
	var query := PhysicsRayQueryParameters3D.create(actor.global_position+Vector3.UP*.025, actor.global_position+Vector3.DOWN*.045, 1, [actor.get_rid()])
	var hit: Dictionary = actor.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and (hit.normal as Vector3).y > .70

func _start_jump() -> bool:
	if phase != "GROUNDED" or crouch > .001 or not grounded() or not can_stand(): return false
	_cancel_ground_actions("jump")
	phase = "AIRBORNE"
	jump_id = _next_id("jump")
	header_used = false
	header_consumed = false
	actor.velocity.y = JUMP_SPEED
	jumps += 1
	if game.ball.carrier == actor: game.ball.detach()
	_emit({"kind": "JUMP_STARTED", "action_id": jump_id})
	return true

func _start_header() -> bool:
	if phase != "AIRBORNE" or header_used or game.ball.held or is_instance_valid(game.ball.carrier): return false
	header_used = true # A miss also spends this aerial attempt; no spam/automatic retry.
	header_consumed = false
	header_id = _next_id("header")
	header_age = 0.0
	header_phase = "PREPARE"
	aim = Vector3(actor.facing.x, 0.0, actor.facing.z).normalized()
	_emit({"kind": "HEADER_STARTED", "action_id": header_id, "parent_id": jump_id})
	return true

func _header_active() -> bool:
	return allowed() and phase == "AIRBORNE" and header_phase == "CONTACT" and not header_consumed

func resolve_ball_collision(ball: FootballPhysicsBall, point: Vector3) -> bool:
	# Called instead of the ordinary passive impulse, from both sides of the existing solver.
	var near_head: bool = point.distance_to(head_center()) <= HEAD_RADIUS+.018 \
		and ball.global_position.distance_to(head_center()) <= HEAD_RADIUS+ball.radius+.018
	if near_head and ball == game.ball and ball.get_instance_id() == _head_hit_ball_id and _head_hit_frame == Engine.get_physics_frames():
		suppressed_contacts += 1
		return true
	if near_head and _try_header(ball, "engine_sweep"): return true
	_passive_frame = Engine.get_physics_frames()
	return false

func _try_header(ball: FootballPhysicsBall, source: String) -> bool:
	if not _header_active(): return false
	var offset: Vector3 = ball.global_position-head_center()
	if offset.length() > HEAD_RADIUS+ball.radius+(.008 if source == "engine_sweep" else 0.0): return false
	var normal: Vector3 = offset.normalized() if offset.length() > .0001 else aim
	return _resolve_header(ball, ball.global_position-normal*ball.radius, normal, source, offset.length(), 0.0)

func _resolve_header(ball: FootballPhysicsBall, point: Vector3, normal: Vector3, source: String, separation: float, fraction: float) -> bool:
	if not _header_active() or ball != game.ball or ball.held or is_instance_valid(ball.carrier): return false
	if not game.can_touch_ball(actor) or normal.dot(aim) < -.15: return false
	var obstruction := PhysicsRayQueryParameters3D.create(head_center(), ball.global_position, 3, [actor.get_rid(), ball.get_rid()])
	if not actor.get_world_3d().direct_space_state.intersect_ray(obstruction).is_empty(): return false
	var before: Vector3 = ball.velocity
	var direction: Vector3 = (aim + Vector3.UP*.13).normalized()
	# Require the intended result to leave the contacting surface, not drive through the skull.
	if direction.dot(normal) < .06: direction = (direction+normal*.45).normalized()
	var impulse: Vector3 = ((direction*10.5-before)*ball.mass_kg).limit_length(6.0)
	if impulse.length_squared() < .000001: return false
	header_consumed = true # Set before any callback can resample/re-enter this action.
	_head_hit_frame = Engine.get_physics_frames()
	_head_hit_ball_id = ball.get_instance_id()
	if not ball.apply_impulse_ns(impulse):
		header_consumed = false
		return false
	actor.receive_body_impulse_ns(-impulse)
	headers += 1
	ball.record_touch(actor, before, .16, "HEADER", point)
	ball.pickup_block = .16
	ball.last_kick_intent = {"action": "header", "action_id": header_id, "direction": direction}
	game.stats.shots += 1
	var event := {"kind": "BODY_CONTACT", "actor": actor, "other": ball, "team": actor.team,
		"action": "HEADER", "surface": "HEAD", "ball_contact": true, "success": true,
		"action_id": header_id, "event_id": header_id+":contact", "parent_id": jump_id, "sequence": serial,
		"point": point, "normal": normal, "impulse": impulse, "before_velocity": before, "after_velocity": ball.velocity,
		"source": source, "head_center": head_center(), "head_radius": HEAD_RADIUS, "separation": separation,
		"contact_fraction": fraction, "action_time": header_age, "physics_frame": Engine.get_physics_frames()}
	game.contact_hub.publish(event)
	_emit(event)
	return true

func cancel_header(reason: String) -> void:
	if header_phase == "IDLE": return
	if not header_consumed:
		misses += 1
		_emit({"kind": "HEADER_FAILED", "action_id": header_id, "reason": reason, "success": false})
	header_phase = "IDLE"

func cancel_inputs(reason: String) -> void:
	_pending_jump = false
	_pending_header = false
	_crouch_held = false
	for token in _down:
		if _down[token]: _blocked[token] = true
	cancel_header(reason)
	# Preserve actual airborne motion/low volume through pause or an obstructed stand.

func _cancel_ground_actions(reason: String) -> void:
	game.input_bridge.pending_intents.clear()
	actor.foot.cancel()
	game.input_bridge.heavy_queue.cancel("interaction_"+reason)
	# Use the router's existing cancel gesture: cancel charged/buffered kicks while
	# preserving held WASD and Shift movement sources.
	game.input_bridge.adapter.router.feed("cancel", true, "interaction-cancel")
	game.input_bridge.adapter.router.feed("cancel", false, "interaction-cancel")

func accepts_mobility_input() -> bool:
	return true

func _step_exclusive(_delta: float, _enabled: bool) -> bool:
	return false

func pose_grounded() -> bool:
	return grounded()

func pose_forward(fallback: Vector3) -> Vector3:
	return fallback

func permits_foot_action() -> bool:
	return phase == "GROUNDED" and crouch <= .001 and landing_left <= 0.0

func movement_cap() -> float:
	return 1.4 if crouch > .001 else 2.0 if phase == "LANDING" else 100.0

func pose_state() -> Dictionary:
	if permits_foot_action() and header_phase == "IDLE": return {}
	var weight := 0.0
	if header_phase != "IDLE": weight = sin(PI*clampf(header_age/(HEADER_PREPARE+HEADER_WINDOW+HEADER_RECOVER), 0.0, 1.0))
	return {"mobility_busy": not permits_foot_action(), "crouch": crouch, "crouch_drop": CROUCH_DROP, "airborne": phase == "AIRBORNE", "header_weight": weight, "phase": phase, "action_id": header_id if header_phase != "IDLE" else jump_id}

func head_center() -> Vector3:
	var skeleton: Skeleton3D = actor.avatar.skeleton
	return skeleton.global_transform * (skeleton.get_bone_global_pose(skeleton.find_bone("head")) * HEAD_OFFSET)

func sync_head_shape() -> void:
	if is_instance_valid(_head_shape): _head_shape.position = actor.to_local(head_center())

func vertical_bounds() -> Vector2:
	var low := INF
	var high := -INF
	for item in _shapes:
		var node: CollisionShape3D = item.node
		if node.disabled: continue
		low = minf(low, node.global_position.y-node.shape.height*.5)
		high = maxf(high, node.global_position.y+node.shape.height*.5)
	if is_instance_valid(_head_shape):
		low = minf(low, _head_shape.global_position.y-HEAD_RADIUS)
		high = maxf(high, _head_shape.global_position.y+HEAD_RADIUS)
	return Vector2(low, high)

func can_stand() -> bool:
	for item in _shapes:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = item.shape
		query.transform = actor.global_transform * (item.transform as Transform3D)
		query.transform.origin += Vector3.UP*.004
		query.collision_mask = 7
		query.exclude = [actor.get_rid()]
		query.margin = .001
		if not actor.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(): return false
	return true

func _apply_shape_height() -> void:
	var factor: float = (actor.profile.player_height_m-CROUCH_DROP*crouch)/actor.profile.player_height_m
	for item in _shapes:
		var node: CollisionShape3D = item.node
		var original: Shape3D = item.shape
		var old_height: float = original.height
		var bottom: float = (item.transform as Transform3D).origin.y-old_height*.5
		if original is CapsuleShape3D:
			# Keep the exact 022 standing torso. During flight expose the actual
			# skeletal head instead of letting the taller torso intercept it first.
			var top: float = bottom+old_height-CROUCH_DROP*crouch
			if phase == "AIRBORNE": top = minf(top, actor.to_local(head_center()).y-HEAD_RADIUS+.01)
			bottom *= factor
			node.shape.height = maxf(original.radius*2.0, top-bottom)
		else:
			bottom *= factor
			node.shape.height = old_height*factor
		node.position.y = bottom+node.shape.height*.5

func _next_id(kind: String) -> String:
	serial += 1
	return "interaction:%s:%s:%s:%s" % [game.match_generation, actor.get_instance_id(), serial, kind]

func _emit(event: Dictionary) -> void:
	var row: Dictionary = event.duplicate()
	row["physics_frame"] = Engine.get_physics_frames()
	history.append(row)
	if history.size() > 128: history.pop_front()
	action_event.emit(row)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: cancel_inputs("focus_lost")

func help_text() -> String:
	return "J：跳跃；空中左键：一次真实头球尝试（不遥控球）\n按住 B：蹲下；松开 B：空间足够时站起；中键：取消头球\nR 重置、C 防守姿态、Space/Ctrl/Shift、F7/F8 保留；V 滑铲本批未接入"
