extends "res://scripts/foot_action.gd"
## Opt-in single right-foot ground pass; base clock/contact/kick stay authoritative.
const STYLE := "ground_compact_r_01"
const BUFFER_SECONDS := .120
const TARGET_CORRECTION_M := .012
var ground_pass_enabled := false
var pending_ground_pass: Dictionary = {}
var ground_active := false
var diagnostics := {"buffered":0,"expired":0,"cancelled":0,"accepted":0,"support_rejected":0,"max_target_correction_m":0.0}
var _request_serial := 0
var _prepared_strike := Vector3.ZERO

func now_seconds() -> float:
	return float(Engine.get_physics_frames())/float(Engine.physics_ticks_per_second)

func context() -> Dictionary:
	var result: Dictionary = actor.avatar.ground_pass_shared_state() if actor.avatar.has_method("ground_pass_shared_state") else {}
	result = result.duplicate(true)
	if not result.has("velocity"): result.velocity = actor.velocity
	if not result.has("accel"): result.accel = result.get("acceleration",Vector3.ZERO)
	if not result.has("body_yaw"): result.body_yaw = atan2(-actor.body_facing.x,-actor.body_facing.z)
	if not result.has("support_phase"): result.support_phase = "UNKNOWN"
	if not result.has("turn_intent"): result.turn_intent = 0.0
	return result

func _scope() -> Dictionary:
	return {"owner":match_controller.ball.carrier,"ball":match_controller.ball.get_instance_id(),"generation":match_controller.match_generation,"formation":match_controller.formation_serial,"epoch":match_controller.input_bridge.authority_epoch}

func _context_valid(scope: Dictionary) -> bool:
	return actor.avatar.has_method("ground_pass_support") and bool(actor.avatar.get("pass_bind_ok")) and scope == _scope() and match_controller.ball.carrier == actor and match_controller.can_foot_action(actor,"PASS") and not match_controller.is_restart_taker(actor)

func _prestart_ready() -> bool:
	var state := context()
	var velocity: Vector3 = state.velocity
	if not velocity.is_finite() or Vector2(velocity.x,velocity.z).length()>1.5 or not bool(state.get("grounded",actor.position.y<.025)): return false
	var support_phase: Variant = state.support_phase
	if support_phase is String and String(support_phase).to_upper() in ["SWING","AIRBORNE","AIR"]: return false
	var support: Dictionary = actor.avatar.get_foot_contact(-1,"SOLE")
	return bool(support.get("valid",false)) and (support.point as Vector3).is_finite() and absf(support.point.y-actor.position.y)<.045

func _slot_available() -> bool:
	return idle() or (phase==Phase.RECOVER and hit and kind in ["CARRY","CLOSE","SHIELD","TURN"]) or (kind=="RECEIVE" and hit and match_controller.ball.carrier==actor and match_controller.ball.reception_ready(actor))

func _clear_ground_slot() -> void:
	pending_ground_pass.clear()
	if bool(buffer.get("ground_pass_slot",false)):
		buffer.clear()
		buffer_time = 0

func _mirror_ground_slot() -> void:
	# The host's existing auto-control guard recognizes a scheduled KICK slot.
	# This is the same request, not a second queue. Only this adapter clocks it.
	buffer = {"kind":"KICK","intent":pending_ground_pass.intent,"target":pending_ground_pass.target_actor,"owner":pending_ground_pass.scope.owner,"restart_id":pending_ground_pass.scope.formation,"ground_pass_slot":true}
	buffer_time = maxf(0.0,float(pending_ground_pass.deadline)-now_seconds())

func _start_ground(intent: Dictionary, target_actor: Node3D) -> bool:
	if not idle(): super.cancel("ground_pass_interrupt_cosmetic_recovery")
	var previous_side := next_side
	next_side = 1
	var accepted := super.request_semantic_kick(intent,0.0,0.0,target_actor)
	if not accepted:
		next_side = previous_side
		return false
	ground_active = true
	_prepared_strike = actor.position+(contact_target-actor.position).limit_length(match_controller.tuning.foot_reach)
	diagnostics.accepted += 1
	return true

func request_semantic_kick(intent: Dictionary, speed := 0.0, lift := 0.0, target_actor: Node3D = null) -> bool:
	if kind=="PASS" and hit and phase in [Phase.CONTACT,Phase.RECOVER]:cancel("next_kick_interrupts_follow_through")
	if bool(intent.get("one_touch_pass",false)) or not ground_pass_enabled or String(intent.get("action","")) != "pass_ground" or match_controller.is_restart_taker(actor):
		var delegated := super.request_semantic_kick(intent,speed,lift,target_actor)
		if delegated and not pending_ground_pass.is_empty():
			_clear_ground_slot()
			diagnostics.cancelled += 1
		return delegated
	var aim: Variant = intent.get("direction",null)
	if not aim is Vector3 or not aim.is_finite() or aim.length_squared()<.0001 or match_controller.ball.carrier!=actor: return false
	if not _context_valid(_scope()) or (not idle() and kind in ["PASS","SHOT","TACKLE"]): return false
	var flat := Vector3(aim.x,0,aim.z).normalized()
	if flat.dot(actor.body_facing)<cos(deg_to_rad(30.0)): return false
	if ground_active and not idle(): return false
	if not pending_ground_pass.is_empty(): return true # Same one slot; never extend its deadline.
	if _slot_available() and _prestart_ready(): return _start_ground(intent,target_actor)
	_request_serial += 1
	super.clear_buffer("ground_pass_replaces_pending")
	pending_ground_pass = {"intent":intent.duplicate(true),"target_actor":target_actor,"deadline":now_seconds()+BUFFER_SECONDS,"scope":_scope(),"request_serial":_request_serial}
	_mirror_ground_slot()
	diagnostics.buffered += 1
	return true

func advance(delta: float) -> void:
	if not pending_ground_pass.is_empty():
		if not bool(buffer.get("ground_pass_slot",false)) or not _context_valid(pending_ground_pass.scope):
			_clear_ground_slot()
			diagnostics.cancelled += 1
		elif now_seconds()>float(pending_ground_pass.deadline):
			_clear_ground_slot()
			diagnostics.expired += 1
		elif _slot_available() and _prestart_ready():
			var queued := pending_ground_pass.duplicate(true)
			_clear_ground_slot()
			_start_ground(queued.intent,queued.target_actor)
	# Keep the inherited scheduler from independently dispatching this slot.
	if bool(buffer.get("ground_pass_slot",false)): buffer.clear()
	super.advance(delta)
	if not pending_ground_pass.is_empty(): _mirror_ground_slot()
	if idle(): ground_active = false

func pose_request() -> Dictionary:
	var result := super.pose_request()
	if not ground_active or kind != "PASS": return result
	result.pass_style = STYLE
	result.pose_revision = STYLE
	var origin := actor.position+start_local
	var target := _prepared_strike
	if not hit: result.strike_target = target
	if phase == Phase.PREPARE:
		var t := clampf(elapsed/maxf(windup,.001),0.0,1.0)
		var back := origin-foot_direction*.075+Vector3.UP*.035
		result.world_target = origin.lerp(back,smoothstep(0.0,.30,t)) if t<.30 else back.lerp(target,smoothstep(.30,1.0,t))
	elif hit:
		var follow := clampf((elapsed-contact_elapsed)/.09,0.0,1.0)
		result.world_target = contact_target+(foot_direction*.23+Vector3.UP*.085)*smoothstep(0.0,1.0,follow)
		if phase==Phase.RECOVER: result.world_target = (result.world_target as Vector3).lerp(origin,smoothstep(0.0,1.0,(elapsed-windup-window)/maxf(recovery,.001)))
	elif phase==Phase.RECOVER:
		result.world_target = target.lerp(origin,smoothstep(0.0,1.0,(elapsed-windup-window)/maxf(recovery,.001)))
	elif phase==Phase.CONTACT:
		# A fixed preparation target permits only 12mm of contact correction.
		# Never use the base PASS's unrestricted current-ball retargeting here.
		var correction := ball_surface(match_controller.ball.position)-target
		correction = correction.limit_length(TARGET_CORRECTION_M)
		target = actor.position+(target+correction-actor.position).limit_length(match_controller.tuning.foot_reach)
		result.world_target = target
		result.strike_target = target
		contact_target = target
		diagnostics.max_target_correction_m = maxf(diagnostics.max_target_correction_m,correction.length())
	return result

func _try_contact(delta: float) -> void:
	if ground_active and kind=="PASS":
		var support: Dictionary = actor.avatar.ground_pass_support() if actor.avatar.has_method("ground_pass_support") else {}
		if not bool(support.get("ready",false)):
			contact_failure = "ground_pass_support_not_ready"
			diagnostics.support_rejected += 1
			return
	var already_hit := hit
	super._try_contact(delta)
	if ground_active and hit and not already_hit: contact_target = toe_world

func cancel(reason := "cancelled") -> void:
	if not pending_ground_pass.is_empty(): diagnostics.cancelled += 1
	_clear_ground_slot()
	ground_active = false
	super.cancel(reason)

func clear_buffer(reason := "cancelled") -> void:
	if not pending_ground_pass.is_empty(): diagnostics.cancelled += 1
	_clear_ground_slot()
	super.clear_buffer(reason)
