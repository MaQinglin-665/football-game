extends Node
## Match-owned authority for a small chest-height hand save/catch/release chain.
## The pose addon only returns geometry; it cannot take possession or kick balls.
signal keeper_resolved(event: Dictionary)
const Contact := preload("res://addons/football_keeper/keeper_contact.gd")
const DiveMotion := preload("res://addons/football_keeper/keeper_dive_motion.gd")
const PREPARE_SECONDS := .08
const CONTACT_SECONDS := .23
const RECOVER_SECONDS := .28
const HOLD_SECONDS := .70
const RELEASE_SECONDS := .14
const CATCH_SPEED_MPS := 8.0
var game: Node
var states: Dictionary = {}
var keeper_states: Array[Dictionary] = []
const FORBIDDEN_FOOT_KINDS := ["pass", "shot", "restart_kick", "throw", "carry", "close", "turn", "shield", "sprint", "pull", "receive", "settle", "stop", "nudge", "tackle"]
var arm_sample_count := 0
var sweep_query_count := 0
var hand_owner: Node3D
var records: Array[Dictionary] = []
var serial := 0
var sequence := 0
var control_generation := 0
var release_blocked_actor := 0
var _match_generation := -1
var _hold_age := 0.0
var _hold_midpoint := Vector3.ZERO
var _hold_offset_local := Vector3.ZERO
var _releasing := false
var _release_age := 0.0
var _release_direction := Vector3.ZERO
var _release_speed := 4.0
var _release_receiver: Node3D
var _release_lift := 1.2
var _internal_clear := false

func bind_match() -> void:
	game.ball.keeper_host = self
	_match_generation = int(game.match_generation)
	for actor: Node3D in game.players:
		if actor.is_goalkeeper and actor.avatar.has_method("set_keeper_action"):
			states[actor.get_instance_id()] = {"actor":actor,"phase":"IDLE","age":0.0,"sequence":0,"target_world":Vector3.ZERO,"hand_mode":"catch","hands":{},"old_hands":{},"active_start":0.0,"backpass_forbidden":false,"last_pose_frame":-1}
			var state: Dictionary = states[actor.get_instance_id()]
			state.dive = false
			var dive = DiveMotion.new()
			if dive.bind(actor,self):
				actor.keeper_dive = dive
				state.dive_driver = dive
			else: push_warning("GK dive disabled: incompatible original floor/rig profile")
			keeper_states.append(state)
	game.services.rules_event.connect(_on_rule_event)

func _live() -> bool:
	return game.phase == game.Phase.PLAY and game.services.rules.is_ball_live()

func _body_basis(actor: Node3D) -> Basis:
	return actor.avatar.keeper_facing_basis()

func _ready_target(actor: Node3D) -> Vector3:
	return actor.global_position + _body_basis(actor) * Vector3(0,1.10,-.35)

func _own_area(actor: Node3D, point: Vector3, padding := 0.0) -> bool:
	var config: RefCounted = game.services.configuration
	var side := -int(signf(game.attack_direction(actor.team)))
	return point.is_finite() and absf(point.x)+padding <= float(config.penalty_half_width) and point.z*side-padding >= float(config.half_length)-float(config.penalty_depth) and point.z*side+padding <= float(config.half_length)

func legal_hand_contact(actor: Node3D, point: Vector3) -> bool:
	if not _live() or not actor.is_goalkeeper or not actor.visible: return false
	if _blocked_actor(actor): return false
	if not game.can_touch_ball(actor) or not _own_area(actor,actor.global_position) or not _own_area(actor,point,game.ball.radius): return false
	if bool(states.get(actor.get_instance_id(),{}).get("backpass_forbidden",false)): return false
	var last: Dictionary = game.services.rules.last_touch
	var last_id := int(last.get("actor_id",-1))
	if release_blocked_actor == actor.get_instance_id() and last_id == release_blocked_actor: return false
	var kind := String(last.get("kind","")).to_lower()
	# Conservative first batch: block a same-team intentional foot kick/throw.
	if last_id!=actor.get_instance_id() and int(last.get("team",-1)) == actor.team and kind in FORBIDDEN_FOOT_KINDS: return false
	return true

func _blocked_actor(actor: Node3D) -> bool:
	if actor.has_method("keeper_dive_allowed") and actor.keeper_dive_allowed(): return false
	return is_instance_valid(actor.down_state) and actor.down_state.blocked()

func _aim(actor:Node3D)->Dictionary:
	var state:Dictionary=states.get(actor.get_instance_id(),{})
	if int(state.get("choice_frame",-1))==Engine.get_physics_frames():return state.get("choice",{})
	state.choice_frame=Engine.get_physics_frames();state.choice=_compute_hand_offer(actor)
	return state.choice

func _compute_hand_offer(actor: Node3D) -> Dictionary:
	var entry:Dictionary=states.get(actor.get_instance_id(),{})
	if entry.has("dive_driver"):
		var central:Dictionary=entry.dive_driver.central_offer()
		if not central.is_empty():return central
	var standing := _standing_aim(actor)
	if not standing.is_empty(): return standing
	var state: Dictionary = states.get(actor.get_instance_id(),{})
	if state.has("dive_driver"):
		var scoop:Dictionary=state.dive_driver.scoop_offer()
		if not scoop.is_empty():return scoop
		return state.dive_driver.offer()
	return {}

func _standing_aim(actor: Node3D) -> Dictionary:
	if game.ball.held or not legal_hand_contact(actor,game.ball.global_position): return {}
	var basis := _body_basis(actor)
	var p: Vector3 = basis.inverse() * (game.ball.global_position-actor.global_position)
	var v: Vector3 = basis.inverse() * (game.ball.velocity-actor.velocity)
	if v.z <= 1.0: return {}
	var time := (-.42-p.z)/v.z
	if time < .055 or time > .27: return {}
	var target: Vector3 = p + v*time + basis.inverse()*Vector3.DOWN*float(game.physics_profile.gravity_mps2)*.5*time*time
	var mode := "parry" if (game.ball.velocity-actor.velocity).length() > CATCH_SPEED_MPS else "catch"
	if target.y < .75 or target.y > 1.95 or absf(target.x) > (.48 if mode=="parry" else .22): return {}
	var state:Dictionary=states.get(actor.get_instance_id(),{})
	if state.has("dive_driver") and not state.dive_driver.body.standing_can_reach(actor.global_position+basis*target,basis,mode,game.ball.radius):return {}
	target.z = -.42
	return {"target_world":actor.global_position+basis*target,"hand_mode":mode}

func _pose(state: Dictionary, phase: String, target: Vector3, weight: float) -> void:
	var actor: Node3D = state.actor
	actor.avatar.set_keeper_action({"phase":phase,"sequence":state.sequence,"weight":weight,"elapsed":state.age,"target_world":target,"hold_world":target,"ball_radius":game.ball.radius,"hand_mode":state.hand_mode})
	actor.avatar.keeper_sample_action()
	arm_sample_count += 1
	state.hands = actor.avatar.keeper_hand_geometry().get("hands",{})
	state.pose_debug = actor.avatar.keeper_contact_debug()
	state.last_pose_frame = Engine.get_physics_frames()

func begin_substep(delta: float) -> void:
	if int(game.match_generation) != _match_generation:
		external_clear("match_generation")
		_match_generation = int(game.match_generation)
		release_blocked_actor = 0
	# Pause freezes the confirmed hand constraint and its clocks for resume.
	if game.phase == game.Phase.PAUSED: return
	if not _live():
		if is_instance_valid(hand_owner): external_clear("not_live")
		for state: Dictionary in keeper_states:
			if state.phase != "IDLE":
				state.phase = "IDLE"
				state.actor.avatar.keeper_reset()
		return
	var last: Dictionary = game.services.rules.last_touch
	if release_blocked_actor != 0 and int(last.get("actor_id",-1)) != release_blocked_actor: release_blocked_actor = 0
	if is_instance_valid(hand_owner):
		_step_held(delta)
		return
	for state: Dictionary in keeper_states:
		var actor: Node3D = state.actor
		state.old_hands = state.hands
		state.step_delta = delta
		state.active_start = 0.0
		if not actor.visible or _blocked_actor(actor) or not _own_area(actor,actor.global_position) or not actor.foot.idle() or actor.foot.has_buffer() or game.ball.carrier==actor:
			if state.phase != "IDLE": actor.avatar.keeper_reset()
			state.phase = "IDLE"
			continue
		state.age = float(state.age)+delta
		if state.phase == "IDLE":
			state.phase = "READY"
			state.age = 0.0
		if state.phase == "READY" and int(state.get("last_aim_frame",-1))!=Engine.get_physics_frames():
			state.last_aim_frame=Engine.get_physics_frames()
			var aim := _aim(actor)
			if not aim.is_empty():
				sequence += 1
				state.sequence = sequence
				state.phase = "PREPARE"
				state.age = 0.0
				state.target_world = aim.target_world
				state.hand_mode = aim.hand_mode
				state.contact_seconds=float(aim.get("contact_seconds",.43 if aim.get("dive",false) else CONTACT_SECONDS))
				state.dive = bool(aim.get("dive",false))
				if state.dive: state.dive_driver.start(aim)
				_emit("GK_PREPARE",actor,{"target":state.target_world,"mode":state.hand_mode,"central_block":bool(aim.get("central_block",false))})
		var prepare_seconds := .10 if bool(state.get("dive",false)) else PREPARE_SECONDS
		var contact_seconds:float=float(state.get("contact_seconds",CONTACT_SECONDS))
		if state.phase == "PREPARE" and float(state.age) >= prepare_seconds:
			state.age = float(state.age)-prepare_seconds
			state.active_start = clampf(1.0-float(state.age)/maxf(delta,.000001),0.0,1.0)
			state.phase = "CONTACT"
		elif state.phase == "CONTACT" and float(state.age) >= contact_seconds:
			state.phase = "RECOVER"
			state.age = 0.0
		elif state.phase == "RECOVER" and float(state.age) >= RECOVER_SECONDS:
			state.phase = "READY"
			state.age = 0.0
		var target: Vector3 = _ready_target(actor)
		if state.phase == "PREPARE": target = target.lerp(state.target_world,smoothstep(0.0,prepare_seconds,float(state.age)))
		elif state.phase == "CONTACT": target = state.target_world
		elif state.phase == "RECOVER": target = (state.target_world as Vector3).lerp(target,smoothstep(0.0,RECOVER_SECONDS,float(state.age)))
		var weight := .60*smoothstep(0.0,.18,float(state.age))
		if state.phase == "PREPARE": weight = lerpf(.60,1.0,smoothstep(0.0,prepare_seconds,float(state.age)))
		elif state.phase == "CONTACT": weight = 1.0
		elif state.phase == "RECOVER": weight = 1.0-smoothstep(0.0,RECOVER_SECONDS,float(state.age))
		if state.phase == "READY" and int(state.last_pose_frame)==Engine.get_physics_frames(): continue
		_pose(state,state.phase,target,weight)
		if state.old_hands.is_empty(): state.old_hands = state.hands

func _box_at(before: Dictionary, after: Dictionary, fraction: float) -> Transform3D:
	var a: Transform3D = before.padded_box_transform
	var b: Transform3D = after.padded_box_transform
	return Transform3D(Basis(a.basis.get_rotation_quaternion().slerp(b.basis.get_rotation_quaternion(),fraction)),a.origin.lerp(b.origin,fraction))

func first_contact(from: Vector3, to: Vector3) -> Dictionary:
	var best := {}
	for state: Dictionary in keeper_states:
		if state.phase != "CONTACT" or not legal_hand_contact(state.actor,from): continue
		var errors: Dictionary = state.pose_debug.get("hand_errors",{})
		for side in ["L","R"]:
			if not state.hands.has(side) or not state.old_hands.has(side) or not bool(errors.get(side,{}).get("valid",false)): continue
			var start := float(state.active_start)
			var a: Dictionary = state.old_hands[side]
			var b: Dictionary = state.hands[side]
			sweep_query_count += 1
			var hit: Dictionary = Contact.sweep_sphere_box(from.lerp(to,start),to,game.ball.radius,_box_at(a,b,start),b.padded_box_transform,b.padded_box_size_m)
			if not bool(hit.get("hit",false)): continue
			var fraction := start+(1.0-start)*float(hit.fraction)
			if best.is_empty() or fraction < float(best.fraction): best = {"state":state,"side":side,"fraction":fraction}
	return best

func resolve_contact(candidate: Dictionary) -> bool:
	var state: Dictionary = candidate.state
	var actor: Node3D = state.actor
	var ball: Node3D = game.ball
	if not legal_hand_contact(actor,ball.global_position) or is_instance_valid(hand_owner): return false
	var touching := {}
	for side in ["L","R"]:
		if not state.hands.has(side) or not state.old_hands.has(side): continue
		var hand: Dictionary = state.hands[side]
		touching[side] = Contact.sphere_box(ball.global_position,ball.radius,_box_at(state.old_hands[side],hand,float(candidate.fraction)),hand.padded_box_size_m)
	var selected: Dictionary = touching.get(String(candidate.side),{})
	if not bool(selected.get("touching",false)): return false
	var incoming: Vector3 = ball.velocity-actor.velocity
	if bool(state.get("dive",false)):
		# Relative velocity of the actual material point on the swept glove.
		var before: Transform3D = state.old_hands[String(candidate.side)].padded_box_transform
		var after: Transform3D = state.hands[String(candidate.side)].padded_box_transform
		var at_contact := _box_at(state.old_hands[String(candidate.side)],state.hands[String(candidate.side)],float(candidate.fraction))
		var local_point: Vector3 = at_contact.affine_inverse()*selected.point
		var hand_velocity: Vector3 = (after*local_point-before*local_point)/maxf(float(state.get("step_delta",0.0)),.000001)
		if not hand_velocity.is_finite(): return false
		incoming = ball.velocity-hand_velocity
	var normal: Vector3 = selected.normal
	var both := bool(touching.get("L",{}).get("touching",false)) and bool(touching.get("R",{}).get("touching",false))
	var retain: bool = both and state.hand_mode == "catch" and bool(state.pose_debug.get("reachable",false)) and incoming.length() <= CATCH_SPEED_MPS
	if not retain and incoming.dot(normal) >= -.001: return false
	control_generation += 1
	var contact_id := "gk:%d:%d:%d:%d" % [game.match_generation,actor.get_instance_id(),state.sequence,control_generation]
	# Existing rule engine updates real last touch, double-touch and goal rules.
	if not game.services.report_ball_contact({"event_id":contact_id,"actor_id":actor.get_instance_id(),"team":actor.team,"position":ball.global_position,"kind":"keeper_hand","surface":"GLOVE","impulse":incoming.length()*ball.mass_kg}): return false
	if not _live(): return false
	_emit("GK_HAND_CONTACT",actor,{"point":selected.point,"both_hands":both,"fraction":candidate.fraction,"control_generation":control_generation})
	ball.last_touch_team = actor.team
	if retain:
		_internal_clear = true
		ball.clear_control(true)
		_internal_clear = false
		game.pass_receiver = null
		game.pass_receiver_timer = 0.0
		ball.set_held(true)
		ball.control_mode = "GK_HAND"
		hand_owner = actor
		_hold_age = 0.0
		_releasing = false
		var left: Transform3D = state.hands.L.padded_box_transform
		var right: Transform3D = state.hands.R.padded_box_transform
		_hold_midpoint = (left.origin+right.origin)*.5
		_hold_offset_local = _body_basis(actor).inverse()*(ball.global_position-_hold_midpoint)
		actor.set_move_intent(Vector3.ZERO)
		state.phase = "HOLD"
		state.age = 0.0
		game.sync_input_context()
		_emit("GK_RETAIN_CONFIRMED",actor,{"ball_point":ball.global_position,"geometry_midpoint":_hold_midpoint,"control_generation":control_generation})
	else:
		var impulse: Vector3 = normal * (-(1.0+.45)*incoming.dot(normal)*float(ball.mass_kg))
		ball.apply_impulse_ns(impulse)
		actor.receive_body_impulse_ns(-impulse)
		ball.pickup_block = .15
		state.phase = "RECOVER"
		state.age = 0.0
		_emit("GK_PARRY_CONFIRMED",actor,{"point":selected.point,"normal":normal,"impulse":impulse,"velocity":ball.velocity})
	return true

func _step_held(delta: float) -> void:
	var actor := hand_owner
	if game.ball.carrier != null or not game.ball.held or game.ball.control_mode != "GK_HAND":
		external_clear("hand_control_replaced")
		return
	if _blocked_actor(actor):
		_drop_held("keeper_down")
		return
	if not actor.visible or not actor.is_goalkeeper:
		_drop_held("keeper_inactive")
		return
	var state: Dictionary = states[actor.get_instance_id()]
	actor.set_move_intent(Vector3.ZERO)
	_hold_age += delta
	state.old_hands = state.hands
	state.age = _hold_age
	var carry_target: Vector3 = actor.global_position+_body_basis(actor)*Vector3(0,1.10,-.34)
	if bool(state.get("dive",false)) and state.has("dive_driver"):
		carry_target = state.dive_driver.body.hold_target()
	var target := _hold_midpoint.lerp(carry_target,smoothstep(0.0,.18,_hold_age))
	if _releasing:
		_release_age += delta
		target += _release_direction*.055*smoothstep(0.0,RELEASE_SECONDS,_release_age)
	_pose(state,"RELEASE" if _releasing else "HOLD",target,1.0)
	var hands: Dictionary = state.hands
	if hands.size()!=2 or not bool(state.pose_debug.get("reachable",false)):
		_drop_held("hand_pose_unreachable")
		return
	var l: Transform3D = hands.L.padded_box_transform
	var r: Transform3D = hands.R.padded_box_transform
	var follow := (l.origin+r.origin)*.5+_body_basis(actor)*_hold_offset_local*(1.0-smoothstep(0.0,.12,_hold_age))
	if not _own_area(actor,actor.global_position) or not _own_area(actor,follow,game.ball.radius):
		_drop_held("leaving_own_penalty_area")
		return
	var left: Dictionary = Contact.sphere_box(follow,game.ball.radius,l,hands.L.padded_box_size_m)
	var right: Dictionary = Contact.sphere_box(follow,game.ball.radius,r,hands.R.padded_box_size_m)
	if not bool(left.touching) or not bool(right.touching):
		_drop_held("both_hand_contact_lost")
		return
	game.ball.global_position = follow # Controlled constraint only after confirmed catch.
	game.ball.previous_position = follow
	if _releasing and _release_age >= RELEASE_SECONDS:
		_release_held()
	elif not _releasing and _hold_age >= HOLD_SECONDS and (not state.has("dive_driver") or not state.dive_driver.active()):
		# Finite low-risk hand outlet in the team attack direction, never own goal.
		_choose_hand_outlet(actor)

func request_release(actor: Node3D, direction: Vector3, speed := 4.0) -> bool:
	if hand_owner != actor or _releasing or not _live() or not direction.is_finite() or direction.length_squared()<.0001: return false
	_releasing = true
	_release_age = 0.0
	_release_direction = direction.normalized()
	_release_speed = clampf(speed,2.0,14.0)
	return true

func _release_held() -> void:
	var actor := hand_owner
	var state: Dictionary = states[actor.get_instance_id()]
	var at: Vector3 = game.ball.global_position
	var accepted:bool=game.services.report_ball_contact({"event_id":"gk-release:%d:%d" % [actor.get_instance_id(),control_generation],"actor_id":actor.get_instance_id(),"team":actor.team,"position":at,"kind":"throw","surface":"GLOVE","impulse":_release_speed*game.ball.mass_kg})
	if not accepted or not _live():
		external_clear("release_rule_rejected")
		return
	game.ball.set_held(false)
	var desired_velocity: Vector3 = actor.velocity+_release_direction*_release_speed+Vector3.UP*_release_lift
	game.ball.apply_impulse_ns((desired_velocity-game.ball.velocity)*game.ball.mass_kg)
	game.ball.spin_rads = Vector3.ZERO
	game.ball.pickup_block = .25
	game.ball.control_mode = "LOOSE"
	release_blocked_actor = actor.get_instance_id()
	hand_owner = null
	_releasing = false
	state.phase = "RECOVER"
	state.age = 0.0
	state.target_world = at
	control_generation += 1
	game.sync_input_context()
	if is_instance_valid(_release_receiver):
		game.pass_receiver=_release_receiver
		game.pass_receiver_timer=3.0
		var adapter:Node=game.get_node("TacticalPlanning")
		game.tactical_director.consume_contact({"kind":"KEEPER_RELEASE","success":true,"event_key":"gk-release:%d:%d" % [actor.get_instance_id(),control_generation],"actor_id":game.players.find(actor),"receiver_id":game.players.find(_release_receiver),"action":"PASS","tactical_action":"PASS","ball_position":adapter.canonical(at),"after_velocity":adapter.canonical(game.ball.velocity),"space_target":adapter.canonical(_release_receiver.position),"carrier_id":-1})
		adapter.contact_refresh_requested=true
	_release_receiver=null
	_emit("GK_RELEASE_ACCEPTED",actor,{"point":at,"velocity":game.ball.velocity,"control_generation":control_generation})

func _drop_held(reason: String) -> void:
	if not is_instance_valid(hand_owner): return
	var actor := hand_owner
	hand_owner = null
	_releasing = false
	game.ball.set_held(false)
	game.ball.velocity = actor.velocity
	game.ball.control_mode = "LOOSE"
	release_blocked_actor = actor.get_instance_id()
	states[actor.get_instance_id()].phase = "RECOVER"
	states[actor.get_instance_id()].age = 0.0
	control_generation += 1
	game.sync_input_context()
	_emit("GK_DROP",actor,{"reason":reason,"point":game.ball.global_position})

func external_clear(reason: String) -> void:
	if _internal_clear: return
	var actor := hand_owner
	# Release only this host's own constraint. A following referee hold/place
	# command retains authority, and a new foot owner retains its ownership.
	if is_instance_valid(actor) and game.ball.control_mode == "GK_HAND":
		game.ball.set_held(false)
		if game.ball.carrier == null: game.ball.velocity = actor.velocity
		game.ball.control_mode = "SETTLE" if is_instance_valid(game.ball.carrier) else "LOOSE"
		release_blocked_actor = actor.get_instance_id()
	hand_owner = null
	_releasing = false
	_hold_age = 0.0
	control_generation += 1
	for state: Dictionary in keeper_states:
		state.phase = "IDLE"
		state.age = 0.0
		state.choice_frame=-1;state.erase("choice")
		# Foot detach/clear must not erase a deliberate same-team backpass.
		if state.has("dive_driver"): state.dive_driver.cancel("host:"+reason)
		state.actor.avatar.keeper_reset()
	if is_instance_valid(actor): _emit("GK_CANCEL",actor,{"reason":reason})

func _on_rule_event(event: Dictionary) -> void:
	var type := String(event.get("type",""))
	if type == "ball_contact":
		var contact: Dictionary = event.get("contact",{})
		var kind := String(contact.get("kind","")).to_lower()
		var forbidden := kind in FORBIDDEN_FOOT_KINDS
		for state: Dictionary in keeper_states:
			# A keeper's own body/foot touch must not erase a prior illegal backpass.
			if int(contact.get("actor_id",-1)) == state.actor.get_instance_id():
				pass # Own foot/body contact preserves provenance; it does not create a teammate backpass.
			elif int(contact.get("team",-1)) != state.actor.team :
				state.backpass_forbidden = false
			elif forbidden:
				state.backpass_forbidden = true
			# Same-team torso deflection does not legalize an intentional backpass.
	elif type == "restart_taken":
		var restart: Dictionary = event.get("restart",{})
		for state: Dictionary in keeper_states: state.backpass_forbidden = int(restart.get("team",-1)) == state.actor.team
	if String(event.get("type","")) in ["restart_awarded","half_time","ends_changed","match_finished","full_time"]:
		external_clear("rule:"+String(event.type))
		release_blocked_actor = 0
		for state: Dictionary in keeper_states: state.backpass_forbidden = false

func _emit(kind: String, actor: Node3D, values: Dictionary) -> void:
	serial += 1
	var event := values.duplicate(true)
	event.merge({"kind":kind,"serial":serial,"actor_id":actor.get_instance_id(),"team":actor.team,"physics_frame":Engine.get_physics_frames(),"world_substep":game.physics_world.step_serial},true)
	records.append(event)
	if records.size()>128: records.pop_front()
	keeper_resolved.emit(event)

func control_state() -> Dictionary:
	return {"mode":"GK_HAND" if is_instance_valid(hand_owner) else "FOOT" if is_instance_valid(game.ball.carrier) else "RESTART" if game.ball.held else "FREE","keeper_id":hand_owner.get_instance_id() if is_instance_valid(hand_owner) else 0,"generation":control_generation,"release_blocked_actor":release_blocked_actor,"held_age":_hold_age,"events":records.duplicate(true)}

func _choose_hand_outlet(actor:Node3D)->void:
	var best:Node3D
	var cost:float=INF
	var origin:Vector3=game.ball.global_position
	for mate:Node3D in game.players:
		if mate==actor or mate.team!=actor.team or not mate.visible:continue
		var offset:Vector3=mate.global_position-origin;offset.y=0
		var distance:float=offset.length()
		if distance<3.0 or distance>18.0 or offset.z*game.attack_direction(actor.team)<-1.0:continue
		var clearance:float=INF
		for opponent:Node3D in game.players:
			if opponent.team==actor.team or not opponent.visible:continue
			var closest:Vector3=Geometry3D.get_closest_point_to_segment(opponent.global_position,origin,mate.global_position)
			var gap:Vector3=opponent.global_position-closest;gap.y=0
			clearance=minf(clearance,gap.length())
		if clearance<1.5:continue
		var score:float=distance*.08-minf(clearance,5.0)
		if score<cost:cost=score;best=mate
	_release_receiver=best
	_release_lift=2.0
	if is_instance_valid(best):
		var target:Vector3=best.global_position+best.velocity*.25
		var direction:Vector3=target-origin;direction.y=0
		# Flight plus rolling continuation; receiver follows the actual released ball.
		request_release(actor,direction,clampf(direction.length()*.62+2.0,4.0,13.0))
	else:
		# Finite hold even when all short lanes are closed.
		request_release(actor,Vector3(.35 if actor.position.x<0 else -.35,0,game.attack_direction(actor.team)),6.0)

func reserve_slow_capture(actor:Node3D)->bool:
	if not states.has(actor.get_instance_id()) or not legal_hand_contact(actor,game.ball.global_position):return false
	var state:Dictionary=states[actor.get_instance_id()]
	if state.phase in ["PREPARE","CONTACT","HOLD","RELEASE"]:return true
	if state.phase not in ["READY","IDLE"] or not state.has("dive_driver"):return false
	return not _aim(actor).is_empty()
