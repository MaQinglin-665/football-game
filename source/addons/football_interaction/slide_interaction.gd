extends "player_interaction.gd"
## Batch 02 depends on frozen batch 01. V routes through the existing input router.
## World still owns displacement, environmental/body sweeps and passive contacts.
const LowState := preload("low_body_state.gd")
const SLIDE_PREPARE := .12
const SLIDE_WINDOW := .26
const RECOVER_HIT := .28
const RECOVER_MISS := .50
const BOOT_RADIUS := .06
const SHIN_RADIUS := .075
var slide_phase := "IDLE"
var slide_id := ""
var slide_age := 0.0
var recovery_age := 0.0
var slide_direction := Vector3.FORWARD
var slide_consumed := false
var slide_ball_frame := -1
var slide_hits := 0
var slide_misses := 0
var slide_attempts := 0
var launch_count := 0
var leg_hits := 0
var victim_seen: Dictionary = {}
var low_body: Node
var boot_shape: CollisionShape3D
var boot_before := Vector3.ZERO
var ball_before := Vector3.ZERO
var slide_body_count := 0
var passive_slide_frame := -1
var body_pairs: Dictionary = {}
var victim_before: Dictionary = {}
var victim_velocity_before: Dictionary = {}
var velocity_before := Vector3.ZERO
var engine_boot_contacts: Dictionary = {}
var _slide_ball_id := 0
var pending_body_fall := ""
var body_fall_after := 0

func _ready() -> void:
	super._ready()
	low_body = LowState.new()
	low_body.setup(game,actor,_shapes,_head_shape,self)
	add_child(low_body)
	boot_shape = CollisionShape3D.new()
	boot_shape.name = "SlideBootContact"
	var sphere := SphereShape3D.new()
	sphere.radius = BOOT_RADIUS
	sphere.margin = actor.profile.sweep_margin_m
	boot_shape.shape = sphere
	boot_shape.disabled = true
	actor.add_child(boot_shape)
	actor.body_contact.connect(_on_body_pair)
	low_body.state_event.connect(func(event: Dictionary):
		_emit(event)
		if event.kind == "RECOVERED":
			phase = "GROUNDED"
			landing_left = LAND_RECOVER
			_apply_shape_height())

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ff_cancel") and slide_phase != "IDLE": cancel_slide("input_cancel")
	super._input(event)

func request_slide(forward: Vector3) -> bool:
	if not allowed() or not permits_foot_action() or not grounded() or not can_stand(): return false
	if actor.is_goalkeeper or actor.tackle_cooldown>0.0 or actor.stamina<18.0 or game.ball.carrier==actor: return false
	if not forward.is_finite(): return false
	slide_direction = Vector3(forward.x,0,forward.z).normalized()
	if slide_direction.length_squared()<.5: slide_direction = actor.facing
	slide_phase = "PREPARE"
	slide_id = _next_id("slide")
	slide_age = 0.0
	recovery_age = 0.0
	slide_consumed = false
	slide_ball_frame = -1
	_slide_ball_id = game.ball.get_instance_id()
	victim_seen.clear()
	victim_before.clear()
	pending_body_fall = ""
	engine_boot_contacts.clear()
	actor.tackle_cooldown = 2.0
	actor.stamina = maxf(0.0,actor.stamina-18.0)
	slide_attempts += 1
	clear_protected_actions()
	low_body.set_slide(0.0,slide_direction,slide_id)
	_emit({"kind":"SLIDE_STARTED","action_id":slide_id})
	return true

func accepts_mobility_input() -> bool:
	return slide_phase == "IDLE" and (not is_instance_valid(low_body) or not low_body.blocked())

func permits_foot_action() -> bool:
	return accepts_mobility_input() and super.permits_foot_action()

func movement_cap() -> float:
	if not accepts_mobility_input(): return .65 if low_body.state=="CRAWL" else 0.0
	return super.movement_cap()

func pose_grounded() -> bool:
	return accepts_mobility_input() and super.pose_grounded()

func pose_forward(fallback: Vector3) -> Vector3:
	return low_body.direction if is_instance_valid(low_body) and low_body.blocked() else fallback

func pose_state() -> Dictionary:
	var result: Dictionary = super.pose_state()
	if is_instance_valid(low_body) and low_body.blocked(): result.merge(low_body.pose_state(),true)
	return result

func clear_protected_actions() -> void:
	_pending_jump = false
	_pending_header = false
	_crouch_held = false
	for token in _down:
		if _down[token]: _blocked[token] = true
	cancel_header("protected_slide_or_fall")
	_cancel_ground_actions("slide_or_fall")

func cancel_inputs(reason: String) -> void:
	super.cancel_inputs(reason)
	if slide_phase != "IDLE": cancel_slide(reason)

func cancel_slide(reason: String) -> void:
	if slide_phase == "IDLE": return
	if slide_phase == "PREPARE":
		slide_phase = "IDLE"
		if low_body.can_stand():
			low_body.state = "IDLE"
			low_body.weight = 0.0
			low_body.apply_volume()
			_apply_shape_height()
		else:
			low_body.enter_recovery(slide_id,slide_direction,.18)
		_emit({"kind":"SLIDE_CANCELLED","action_id":slide_id,"reason":reason,"launched":false})
	else:
		_begin_recovery(reason) # Never restart or refund a launched challenge.
	clear_protected_actions()

func _step_exclusive(delta: float, _enabled: bool) -> bool:
	if accepts_mobility_input(): return false
	clear_protected_actions()
	crouch = 0.0
	if slide_phase != "IDLE":
		slide_age += delta
		if slide_phase == "PREPARE":
			low_body.set_slide(smoothstep(0.0,1.0,slide_age/SLIDE_PREPARE),slide_direction,slide_id)
			if slide_age>=SLIDE_PREPARE:
				slide_phase = "CONTACT"
				var current := Vector3(actor.velocity.x,0,actor.velocity.z)
				var speed := clampf(current.dot(slide_direction)+1.2,4.7,5.8)
				actor.velocity.x = slide_direction.x*speed
				actor.velocity.z = slide_direction.z*speed
				launch_count += 1 # Sole voluntary launch; collisions keep their momentum.
				_emit({"kind":"SLIDE_LAUNCHED","action_id":slide_id,"speed":speed})
		elif slide_phase == "CONTACT":
			if slide_age>=SLIDE_PREPARE+SLIDE_WINDOW: _begin_recovery("window_end")
		elif slide_phase == "RECOVER":
			recovery_age += delta
			var duration := RECOVER_HIT if slide_consumed else RECOVER_MISS
			if recovery_age>=duration:
				slide_phase = "IDLE"
				boot_shape.disabled = true
				low_body.enter_recovery(slide_id,slide_direction,.18)
	# Current body-eye anchor reads the final low skeleton; retain free yaw/pitch.
	actor.refresh_pose(0.0)
	sync_head_shape()
	boot_shape.disabled = slide_phase not in ["CONTACT","RECOVER"]
	_sync_boot()
	boot_before = _boot_center()
	ball_before = game.ball.global_position
	velocity_before = actor.velocity
	slide_body_count = game.ball.body_collision_count
	_snapshot_victims()
	if _slide_active():
		_try_slide_ball(game.ball,"initial_overlap")
	return true

func _begin_recovery(reason: String) -> void:
	if slide_phase == "RECOVER": return
	slide_phase = "RECOVER"
	recovery_age = 0.0
	if not slide_consumed:
		slide_misses += 1
		_emit({"kind":"SLIDE_MISSED","action_id":slide_id,"reason":reason,"success":false})
	else: _emit({"kind":"SLIDE_RECOVER","action_id":slide_id,"reason":reason})

func override_motor(dt: float) -> bool:
	if not is_instance_valid(low_body): return false
	if slide_phase != "IDLE":
		var flat := Vector3(actor.velocity.x,0,actor.velocity.z)
		var drag := 4.0 if slide_phase == "CONTACT" else 9.0
		flat = flat.move_toward(Vector3.ZERO,drag*dt)
		actor.velocity.x = flat.x
		actor.velocity.z = flat.z
		actor.velocity.y -= actor.profile.gravity_mps2*dt
		return true
	return low_body.override_motor(dt)

func after_world(delta: float) -> void:
	if accepts_mobility_input():
		super.after_world(delta)
		return
	if game.phase in [game.Phase.MENU,game.Phase.PAUSED,game.Phase.FINISHED]: return
	_sync_boot()
	sync_head_shape()
	if slide_phase in ["CONTACT","RECOVER"]:
		# Both physical solver directions already have first refusal. Relative actual
		# socket sweep handles fast motion only if no passive ball collision happened.
		if _slide_active() and passive_slide_frame != Engine.get_physics_frames() and game.ball.body_collision_count==slide_body_count:
			var start: Vector3 = ball_before-boot_before
			var end: Vector3 = game.ball.global_position-_boot_center()
			var relative := end-start
			var closest := Geometry3D.get_closest_point_to_segment(Vector3.ZERO,start,end)
			if closest.length()<=BOOT_RADIUS+game.ball.radius+.004 and relative.length()<.8:
				var fraction := clampf(-start.dot(relative)/maxf(relative.length_squared(),.000001),0.0,1.0)
				var center: Vector3 = boot_before.lerp(_boot_center(),fraction)
				var ball_center: Vector3 = ball_before.lerp(game.ball.global_position,fraction)
				_resolve_slide_ball(game.ball,ball_center-closest.normalized()*game.ball.radius,closest.normalized(),"relative_socket_sweep",center.distance_to(ball_center),fraction)
		# Ball consumption NEVER stops subsequent physical leg/challenge evidence.
		for victim in engine_boot_contacts:
			var row: Dictionary = engine_boot_contacts[victim]
			if row.frame!=Engine.get_physics_frames(): continue
			_settle_leg(row.other,row.point,row.normal,row.relative,0.0,"engine_boot_to_lower_body_volume",delta,row.proof)
		_observe_legs(boot_before,_boot_center(),delta,"swept_rendered_boot_to_shin")
	if not pending_body_fall.is_empty():
		var id := pending_body_fall
		pending_body_fall = ""
		slide_phase = "IDLE"
		boot_shape.disabled = true
		clear_protected_actions()
		low_body.enter_hit(id,actor.facing)

func _slide_active() -> bool:
	return slide_phase=="CONTACT" and not slide_consumed and allowed() and game.can_touch_ball(actor)

func _socket() -> Dictionary:
	return actor.avatar.get_foot_contact(1,"TOE")

func _boot_center() -> Vector3:
	var socket := _socket()
	var normal: Vector3 = socket.normal
	var forward := Vector3(normal.x,0,normal.z).normalized()
	if forward.length_squared()<.5: forward = low_body.direction if is_instance_valid(low_body) else actor.facing
	return socket.point-forward*BOOT_RADIUS

func _sync_boot() -> void:
	if is_instance_valid(boot_shape): boot_shape.position = actor.to_local(_boot_center())

func resolve_ball_collision(ball: FootballPhysicsBall, point: Vector3) -> bool:
	var socket := _socket()
	var near_boot: bool = socket.get("valid",false) and point.distance_to(_boot_center())<=BOOT_RADIUS+.035
	if ball==game.ball and ball.get_instance_id()==_slide_ball_id and slide_ball_frame==Engine.get_physics_frames() and near_boot:
		suppressed_contacts += 1
		return true
	if _slide_active() and near_boot:
		if _try_slide_ball(ball,"engine_shape_contact",.009): return true
		passive_slide_frame = Engine.get_physics_frames()
	return super.resolve_ball_collision(ball,point)

func _try_slide_ball(ball: FootballPhysicsBall, source: String, skin := .004) -> bool:
	var socket := _socket()
	if not _slide_active() or not socket.get("valid",false): return false
	var offset: Vector3 = ball.global_position-_boot_center()
	if offset.length()>BOOT_RADIUS+ball.radius+skin: return false
	var normal := offset.normalized()
	if normal.length_squared()<.5: normal = slide_direction
	return _resolve_slide_ball(ball,ball.global_position-normal*ball.radius,normal,source,offset.length(),0.0)

func _resolve_slide_ball(ball: FootballPhysicsBall, point: Vector3, normal: Vector3, source: String, separation: float, fraction: float) -> bool:
	if not _slide_active() or ball!=game.ball or ball.held or not _socket().get("valid",false): return false
	if ball.global_position.y>actor.global_position.y+.42 or normal.dot(slide_direction)<-.35: return false
	var ray := PhysicsRayQueryParameters3D.create(_boot_center(),ball.global_position,3,[actor.get_rid(),ball.get_rid()])
	if not actor.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): return false
	var before: Vector3 = ball.velocity
	var direction: Vector3 = (slide_direction+Vector3.UP*.025).normalized()
	if direction.dot(normal)<.04: direction = (direction+normal*.45).normalized()
	var impulse: Vector3 = ((direction*6.4-before)*ball.mass_kg).limit_length(3.6)
	if impulse.length_squared()<.000001: return false
	slide_consumed = true
	slide_ball_frame = Engine.get_physics_frames()
	if not ball.apply_impulse_ns(impulse):
		slide_consumed = false
		return false
	actor.receive_body_impulse_ns(-impulse)
	if is_instance_valid(ball.carrier): ball.detach()
	ball.record_touch(actor,before,.25,"SLIDE_TACKLE",point)
	ball.pickup_block = .25
	ball.last_kick_intent = {"action":"tackle_slide","action_id":slide_id,"direction":direction}
	slide_hits += 1
	game.stats.tackles += 1
	var event := {"kind":"FOOT_TOUCH","actor":actor,"team":actor.team,"action":"SLIDE_TACKLE","surface":"TOE","success":true,
		"action_id":slide_id,"event_id":slide_id+":ball","sequence":serial,"point":point,"normal":normal,"impulse":impulse,
		"before_velocity":before,"after_velocity":ball.velocity,"source":source,"boot_center":_boot_center(),"boot_radius":BOOT_RADIUS,
		"separation":separation,"contact_fraction":fraction,"action_time":slide_age,"physics_frame":slide_ball_frame}
	game.contact_hub.publish(event)
	_emit(event)
	return true

func _snapshot_victims() -> void:
	victim_before.clear()
	victim_velocity_before.clear()
	if slide_phase not in ["CONTACT","RECOVER"]: return
	for other in game.players:
		if other==actor or not other.visible or actor.global_position.distance_squared_to(other.global_position)>9.0: continue
		victim_before[other.get_instance_id()] = _shins(other)
		victim_velocity_before[other.get_instance_id()] = other.velocity

func _shins(other: CharacterBody3D) -> Array:
	var skeleton: Skeleton3D = other.avatar.skeleton
	var pairs: Array = []
	for suffix in ["L","R"]:
		pairs.append([skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone("foot."+suffix)).origin),
			skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone("shin."+suffix)).origin)])
	return pairs

func _observe_legs(from: Vector3, to: Vector3, delta: float, source: String) -> void:
	if slide_phase not in ["CONTACT","RECOVER"] or not game.can_touch_ball(actor) or not _socket().get("valid",false): return
	for other in game.players:
		if other==actor or not other.visible or victim_seen.has(other.get_instance_id()) or actor.global_position.distance_squared_to(other.global_position)>9.0: continue
		# The solver may already have separated/reversed the contact. Classify the
		# actual crossing with incoming motion, and reuse its resolved impulse.
		var relative: Vector3 = velocity_before-(victim_velocity_before.get(other.get_instance_id(),other.velocity) as Vector3)
		var current: Array = _shins(other)
		var previous: Array = victim_before.get(other.get_instance_id(),current)
		for i in 2:
			var movement: Vector3 = ((current[i][0]+current[i][1])-(previous[i][0]+previous[i][1]))*.5
			var points := Geometry3D.get_closest_points_between_segments(from,to-movement,previous[i][0],previous[i][1])
			var distance: float = points[0].distance_to(points[1])
			if distance>BOOT_RADIUS+SHIN_RADIUS or relative.length()<.35: continue
			var proof_point: Vector3 = points[1]+movement*.5
			# Closest approach can be past the shin: derive an entry-side normal,
			# rather than rejecting a crossing as already separating after impact.
			var travel: Vector3 = to-movement-from
			var entry: Vector3 = points[0]
			if travel.length()>.0001:
				var back := sqrt(maxf(0.0,pow(BOOT_RADIUS+SHIN_RADIUS,2)-distance*distance))
				var along := clampf((points[0]-from).dot(travel.normalized())-back,0.0,travel.length())
				entry = from+travel.normalized()*along
			var shin_entry := Geometry3D.get_closest_point_to_segment(entry,previous[i][0],previous[i][1])
			var normal: Vector3 = entry-shin_entry
			normal.y = 0.0
			if normal.length()<.001: normal = -relative
			normal = normal.normalized()
			if relative.dot(normal)>=-.05: continue
			_settle_leg(other,proof_point,normal,relative,distance,source,delta)
			break

func observe_body_collision(other: CharacterBody3D, normal: Vector3, impulse: Vector3, point: Vector3, own_owner: Object, other_owner: Object) -> void:
	if slide_phase not in ["CONTACT","RECOVER"] or not game.can_touch_ball(actor) or impulse.length_squared()<.000001: return
	if own_owner!=boot_shape or not _socket().get("valid",false): return
	if not other_owner is CollisionShape3D or point.y>other.global_position.y+.65: return
	# This is the solver's actual rendered-toe proxy against the host's physical
	# lower body, not a widened rendered-shin distance or a proximity-only foul.
	var own_before: Vector3 = actor.velocity-impulse/actor.physics_mass_kg()
	var other_before: Vector3 = other.velocity+impulse/other.physics_mass_kg()
	engine_boot_contacts[other.get_instance_id()] = {"frame":Engine.get_physics_frames(),"other":other,"point":point,"normal":normal,
		"relative":own_before-other_before,"proof":{"contact_geometry":"solver_shape_contact","actor_shape":own_owner.get_instance_id(),"victim_shape":other_owner.get_instance_id(),
		"victim_body_part":"LOWER_BODY","victim_shape_name":String(other_owner.name),"boot_surface":"TOE"}}

func _settle_leg(other: CharacterBody3D, point: Vector3, normal: Vector3, relative: Vector3, separation: float, source: String, _delta: float, geometry: Dictionary = {}) -> void:
	var victim_speed:float=Vector2(other.velocity.x,other.velocity.z).length()
	var victim: int = other.get_instance_id()
	if victim_seen.has(victim): return
	if geometry.is_empty():
		var sight := PhysicsRayQueryParameters3D.create(_boot_center(),point,1,[actor.get_rid(),other.get_rid()])
		if not actor.get_world_3d().direct_space_state.intersect_ray(sight).is_empty(): return
	victim_seen[victim] = true # Claim before callbacks, rule stoppage or victim pose changes.
	var id := slide_id+":victim:"+str(victim)
	var pair: Dictionary = body_pairs.get(victim,{})
	var reuse: bool = int(pair.get("frame",-1))==Engine.get_physics_frames()
	var impulse: Vector3
	if reuse:
		impulse = pair.impulse
	else:
		# Effective boot/leg contact mass; equal/opposite actual momentum, once.
		var size := clampf(-relative.dot(normal)*8.0,0.0,70.0)
		impulse = normal*size
		actor.receive_body_impulse_ns(impulse)
		other.receive_body_impulse_ns(-impulse)
	leg_hits += 1
	var down: Node = other.get("down_state") if other is FootballAgent else other.interaction.low_body
	if not is_instance_valid(down):
		down = LowState.new()
		down.setup(game,other)
		other.down_state = down
		other.add_child(down)
	var closing:float=maxf(0.0,-relative.dot(normal.normalized()))
	var disruptive:bool=(victim_speed>=2.2 and closing>=1.6) or closing>=2.4
	if disruptive:down.enter_hit(id,other.facing,.45,{"cause":"extended_leg","contact":true,"speed":victim_speed})
	var frame := Engine.get_physics_frames()
	var severity := "reckless" if closing>=4.5 else "careless"
	var evidence := {"confirmed":true,"offence":"trip","severity":severity,"contact":true,"ball_first":slide_consumed and slide_ball_frame<frame,
		"disruptive":disruptive,"closing_speed":closing,"dangerous":closing>=4.5,"contact_order_known":not slide_consumed or slide_ball_frame!=frame,"ball_in_play_at_contact":true,"body_contact_time":frame/120.0,
		"ball_contact_time":slide_ball_frame/120.0 if slide_consumed else -1.0,"source":source,"action_id":slide_id,
		"boot_radius":BOOT_RADIUS,"relative_speed":relative.length(),"action_phase":slide_phase}
	if geometry.is_empty():
		evidence["contact_geometry"] = "swept_rendered_socket"
		evidence["boot_shin_separation"] = separation
		evidence["shin_radius"] = SHIN_RADIUS
	evidence.merge(geometry,true)
	var event := {"kind":"BODY_CONTACT","actor":actor,"other":other,"team":actor.team,"action":"LEG_CHALLENGE","action_id":slide_id,"event_id":id,
		"sequence":id,"point":point,"normal":normal,"impulse":impulse,"success":true,"reused_world_impulse":reuse,"foul_evidence":evidence}
	game.contact_hub.publish(event)
	_emit(event)

func _on_body_pair(other: CharacterBody3D, normal: Vector3, impulse: Vector3) -> void:
	var victim: int = other.get_instance_id()
	var old: Dictionary = body_pairs.get(victim,{})
	var accumulated: Vector3 = old.get("impulse",Vector3.ZERO) if int(old.get("frame",-1))==Engine.get_physics_frames() else Vector3.ZERO
	body_pairs[victim] = {"frame":Engine.get_physics_frames(),"impulse":accumulated+impulse,"normal":normal}
	# Match owns collision fall permission for both human and AI.

func sync_head_shape() -> void:
	super.sync_head_shape()
	if is_instance_valid(low_body) and low_body.blocked(): low_body.sync_head_shape()
	if is_instance_valid(boot_shape): _sync_boot()

func vertical_bounds() -> Vector2:
	if is_instance_valid(low_body) and low_body.blocked():
		var bounds: Vector2 = low_body.vertical_bounds()
		if is_instance_valid(boot_shape) and not boot_shape.disabled:
			bounds.x = minf(bounds.x,boot_shape.global_position.y-BOOT_RADIUS)
			bounds.y = maxf(bounds.y,boot_shape.global_position.y+BOOT_RADIUS)
		return bounds
	return super.vertical_bounds()

func help_text() -> String:
	return super.help_text().replace("V 滑铲本批未接入","V：无球滑铲，真实触球／空铲都有恢复，中键取消准备")+"\n滑铲／倒地期间自由观察；障碍下 WASD 低速挪动；每动作／受害者只结算一次"
