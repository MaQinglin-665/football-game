class_name FootballIntentRouter
extends RefCounted
## Deterministic input state machine. No scene nodes or physical ball ownership.
signal intent_emitted(intent: Dictionary)
signal notice_emitted(notice: Dictionary)
signal ui_requested(command: String)

const Catalog := preload("res://addons/football_input/action_catalog.gd")
const UI_TOKENS := ["pause", "help", "fullscreen"]
const CHARGE_TOKENS := ["shot", "pass"]
const SCOPE_KEYS := ["actor_id", "role", "possession", "phase", "paused", "focused", "ui_captured", "restart_taker", "restart_id", "ball_generation", "allowed_actions", "capabilities"]
var catalog := Catalog.new()
var context: Dictionary = {
	"actor_id": "local", "role": "outfield", "position": "CM",
	"possession": "none", "phase": "menu", "paused": false,
	"focused": true, "ui_captured": false, "restart_taker": false,
	"restart_id": "", "ball_generation": 0, "receive_available": false, "pass_receive_available": false,
	"allowed_actions": [], "capabilities": {}, "host_kick_queue":false, "action_ready": true
}
var now := 0.0
var sequence := 0
var context_revision := 0
var aim_forward := Vector3.FORWARD
var aim_right := Vector3.RIGHT
var shot_elevation := 12.0
var high_elevation := 35.0
var _sources: Dictionary = {}
var _blocked: Dictionary = {}
var _continuous: Dictionary = {}
var _last_continuous_time: Dictionary = {}
var _charge: Dictionary = {}
var _buffer: Dictionary = {}
var _cooldowns: Dictionary = {}
var _last_notice: Dictionary = {}

func _init(profile_path: String = Catalog.PROFILE_PATH) -> void:
	catalog = Catalog.new(profile_path)
	shot_elevation = catalog.value("shot_elevation_deg", 12.0)
	high_elevation = catalog.value("high_pass_elevation_deg", 35.0)

func set_context(patch: Dictionary) -> void:
	var before := context.duplicate(true)
	for key in patch:
		if context.has(key):
			context[key] = patch[key].duplicate(true) if patch[key] is Dictionary or patch[key] is Array else patch[key]
	var changed := false
	for key in SCOPE_KEYS:
		changed = changed or before[key] != context[key]
	if not changed:
		return
	context_revision += 1
	_cancel_buffer("context_changed")
	var actor_changed: bool = before.actor_id != context.actor_id or before.role != context.role
	var barrier_changed: bool = before.phase != context.phase or before.paused != context.paused or before.focused != context.focused or before.ui_captured != context.ui_captured
	if actor_changed or barrier_changed:
		reset("actor_changed" if actor_changed else "context_barrier")
	else:
		var retain_incoming: bool = before.possession=="none" and context.possession=="foot" and not _charge.is_empty() and bool(_charge.get("incoming_receive",false)) and before.restart_id==context.restart_id and before.ball_generation==context.ball_generation and before.allowed_actions==context.allowed_actions and before.capabilities==context.capabilities
		if retain_incoming: _charge.context_revision = context_revision
		else: _cancel_charge("context_changed")
		# Ball policies must end under the context that started them. Movement
		# survives ordinary possession updates; discrete actions are never replayed.
		for action in _continuous.keys():
			if action != "move":
				_end_continuous(action, "context_changed")
		for source in _sources:
			if (CHARGE_TOKENS.has(_sources[source]) and not retain_incoming) or _sources[source] in ["context", "slide", "stand_intercept"]:
				_blocked[source] = true
	# Recheck capabilities for ongoing movement on position permission changes.
	if _continuous.has("move") and not _allowed("move", false):
		_end_continuous("move", "permission_changed")
	_refresh_edge()

func set_aim(forward: Vector3, _right: Vector3 = Vector3.RIGHT) -> void:
	# Elevation is an independent semantic field. Camera pitch has no effect.
	var planar := Vector3(forward.x, 0.0, forward.z)
	if planar.length_squared() > 0.000001:
		aim_forward = planar.normalized()
		aim_right = Vector3(-aim_forward.z, 0.0, aim_forward.x)
	_refresh_edge()

func gameplay_allowed() -> bool:
	return context.focused and not context.paused and not context.ui_captured and context.phase in ["live", "dead_ball"]

func is_held(token: String) -> bool:
	for source in _sources:
		if _sources[source] == token and not _blocked.has(source):
			return true
	return false

func feed(token: String, pressed: bool, source: String, echo: bool = false) -> bool:
	if token.is_empty() or source.is_empty():
		return false
	var was_held := is_held(token)
	if not pressed:
		_sources.erase(source)
		_blocked.erase(source)
		if was_held and not is_held(token):
			_on_release(token)
		_refresh_edge()
		return true
	if echo or _sources.has(source):
		return true
	# A wheel tick is an impulse, not a key which stays down until released.
	if token in ["loft_up", "loft_down"]:
		if gameplay_allowed():
			_adjust_elevation(1.0 if token == "loft_up" else -1.0)
			_refresh_edge()
		return true
	_sources[source] = token
	if UI_TOKENS.has(token):
		if not was_held:
			if token in ["pause", "help"]:
				reset("ui_" + token)
			ui_requested.emit(token)
		return true
	if not gameplay_allowed():
		_blocked[source] = true
		return false
	if not was_held:
		_on_press(token, source)
	_refresh_edge()
	return true

func step(delta: float) -> void:
	now += maxf(delta, 0.0)
	if not gameplay_allowed():
		_end_all_continuous("blocked")
		return
	_process_buffer()
	if not _charge.is_empty():
		if now - float(_charge.started_at) > catalog.value("max_charge_hold_seconds", 6.0):
			_cancel_charge("hold_timeout")
			_block_token_sources(["shot", "pass"])
			_notify("hold_timeout", "蓄力超时已取消，请松开后重按")
		else:
			_update_charge()
	_update_continuous()

func reset(reason: String = "reset") -> void:
	_cancel_charge(reason)
	_cancel_buffer(reason)
	_end_all_continuous(reason)
	# Keep physical state so keys held across a barrier need a real release.
	for source in _sources:
		if not UI_TOKENS.has(_sources[source]):
			_blocked[source] = true

func availability(action: String) -> Dictionary:
	return catalog.availability(action, context)

func request_special(action: String) -> bool:
	# No default key is advertised for unverified knuckleball physics.
	# This API lets the help/host show the explicit disabled explanation.
	if not _allowed(action):
		return false
	_notify("no_binding", "该特殊动作没有已验证的输入流程", action)
	return false

func snapshot() -> Dictionary:
	var held: Array = []
	for token in _sources.values():
		if is_held(token) and not held.has(token):
			held.append(token)
	return {"context": context.duplicate(true), "context_revision": context_revision,
		"now": now, "held": held, "blocked_source_count": _blocked.size(),
		"charge": _charge.duplicate(true), "buffer": _buffer.duplicate(true), "continuous": _continuous.keys(),
		"shot_elevation_deg": shot_elevation, "high_elevation_deg": high_elevation}

func _on_press(token: String, source: String) -> void:
	if token == "cancel":
		_emit("cancel_pass_queue", "commit", {})
		var had_action := not _charge.is_empty() or not _buffer.is_empty()
		_cancel_charge("input_cancel")
		_cancel_buffer("input_cancel")
		_block_token_sources(["shot", "pass"])
		if had_action:
			_notify("cancelled", "已取消传射；移动继续，松开原动作键后可重按")
		return
	if not _buffer.is_empty() and token in ["shot", "pass", "context", "slide", "stand_intercept", "cut"]:
		_blocked[source] = true
		_notify("buffer_pending", "正在等当前动作完成；中键取消后可重按")
		return
	if not _charge.is_empty() and token in ["shot", "pass", "context", "slide", "stand_intercept", "cut"]:
		_blocked[source] = true
		if token == "pass" and _charge.token == "shot":
			_cancel_charge("right_click_cancel")
			_block_token_sources(["shot"])
			_notify("cancelled", "射门蓄力已取消；再次按传球键才会传球")
		else:
			_notify("exclusive", "正在蓄力，请先松开或用右键取消")
		return
	if token == "call":
		if context.phase == "live" and context.possession == "none":
			_commit("call_ball", aim_forward, 1.0, 0.0, Vector3.ZERO, "request")
		else:
			_notify("wrong_context", "有球或死球期间无需向队友要球", "call_ball")
	elif token == "stand_intercept":
		pass # Held pressure is resolved once by the host before movement.
	elif token == "slide":
		if context.phase == "live" and context.possession == "none" and context.role != "goalkeeper":
			_commit("tackle_slide", _move_or_aim(), 1.0, 0.0, Vector3.ZERO, "slide")
		else:
			_notify("wrong_context", "飞铲只在场上无球防守时开放", "tackle_slide")
	elif token == "cut":
		if context.phase=="live" and context.possession=="foot":
			_commit("cut_ball",_move_or_aim(),.4,0.0,Vector3.ZERO,"directional_cut",{"cut_direction_selected":_move_vector().length_squared()>.01})
		else:_notify("no_ball","扣球需要球在脚下且比赛进行中","cut_ball")
	elif token == "context":
		_context_action()
	elif CHARGE_TOKENS.has(token):
		_begin_charge(token, source)

func _on_release(token: String) -> void:
	if not _charge.is_empty() and _charge.token == token:
		_update_charge(false)
		if _charge.is_empty():
			return
		var charge := _charge.duplicate(true)
		_charge.clear()
		if charge.valid:
			var accepted: bool = _commit(charge.action, charge.direction, charge.power, charge.elevation_deg, charge.spin, charge.style, {
				"gesture_id": charge.gesture_id,
				"held_seconds": maxf(0.0, now - float(charge.started_at)),
				"short_press": now - float(charge.started_at) <= catalog.value("tap_seconds", 0.18)
			})
			if not accepted:
				_emit_from_charge(charge, "cancel", "not_ready")
		else:
			_emit_from_charge(charge, "cancel", "unsupported_variant")

func _context_action() -> void:
	if context.phase == "dead_ball":
		_notify("dead_ball", "死球请等待开球权限，使用传球或射门", "stop_ball")
		return
	if context.role == "goalkeeper" and context.possession == "none":
		_commit("keeper_dive", _move_or_aim(), 1.0, 0.0, Vector3.ZERO, "dive")
	elif context.possession == "foot":
		if is_held("stance"):
			_commit("stop_ball", aim_forward, 1.0, 0.0, Vector3.ZERO, "shield_stop")
		elif is_held("close") and _move_vector().length_squared() > 0.01:
			_commit("nudge", _move_vector(), 0.35, 0.0, Vector3.ZERO, "short_touch")
		elif is_held("sprint") and not is_held("close"):
			_commit("push_ball", _move_or_aim(), 0.8, 0.0, Vector3.ZERO, "explicit_push")
		else:
			_commit("stop_ball", aim_forward, 1.0, 0.0, Vector3.ZERO, "sole_stop")
	elif context.possession == "none":
		if context.receive_available:
			_commit("receive", _move_or_aim(), 0.5, 0.0, Vector3.ZERO, "prepare")
		else:
			_commit("receive", _move_or_aim(), 0.5, 0.0, Vector3.ZERO, "prepare")
	else:
		_notify("wrong_context", "门将持球请使用 右键出球")

func _begin_charge(token: String, source: String) -> void:
	if context.phase == "dead_ball" and not context.restart_taker:
		_blocked[source] = true
		_notify("restart_denied", "等待指定罚球队员执行开球")
		return
	if context.possession == "none" and context.phase != "dead_ball" and not (token=="pass" and context.pass_receive_available):
		if context.role == "goalkeeper" and token == "shot":
			if not _allowed("keeper_ready"):
				_blocked[source] = true
		else:
			_blocked[source] = true
			_notify("no_ball", "当前无球，不能传球或射门")
		return
	if context.possession == "hands" and token == "shot":
		_blocked[source] = true
		_notify("keeper_hands", "门将手持球请使用 右键出球")
		return
	var params := _kick_params(token)
	if not _kick_allowed(params) or not _can_start_charge(params.action):
		_blocked[source] = true
		return
	_charge = params
	_charge["token"] = token
	_charge["incoming_receive"] = token=="pass" and context.possession=="none" and context.pass_receive_available
	_charge["started_at"] = now
	_charge["last_update_at"] = now
	_charge["gesture_id"] = sequence + 1
	_charge["actor_id"] = context.actor_id
	_charge["context_revision"] = context_revision
	_charge["valid"] = true
	_charge["power"] = catalog.value("minimum_power", 0.2)
	_emit_from_charge(_charge, "begin")
	for action in _continuous.keys():
		if action != "move":
			_end_continuous(action, "kick_charge")

func _kick_params(token: String) -> Dictionary:
	var bend := float(int(is_held("spin_right")) - int(is_held("spin_left")))
	var high := is_held("high")
	var action := ""
	var elevation := shot_elevation
	var style := "straight"
	if token == "pass":
		elevation = high_elevation if high else catalog.value("ground_elevation_deg", 0.0)
		style = "high" if high else "ground"
		if context.possession == "hands":
			action = "keeper_distribute"
			style = "throw_high" if high else "roll_ground"
		else:
			action = "pass_spin" if bend != 0.0 else "pass_high" if high else "pass_ground"
	else:
		action = "shoot_curve" if bend != 0.0 else "shoot_straight"
		style = "curve" if bend != 0.0 else "straight"
		if is_held("placed_shot") and bend==0.0:
			style="placed"
			elevation=minf(elevation,8.0)
	return {"action": action, "direction": aim_forward, "power": 0.2,
		"elevation_deg": elevation, "spin": Vector3.UP * bend, "style": style}

func _update_charge(emit_update: bool = true) -> void:
	var params := _kick_params(_charge.token)
	var changed := false
	for key in params:
		if key != "power" and _charge.get(key) != params[key]:
			changed = true
	for key in params:
		_charge[key] = params[key]
	if not _kick_allowed(params, false):
		_kick_allowed(params)
		_cancel_charge("unsupported_variant")
		_block_token_sources(["shot", "pass"])
		return
	# R004: full power at KickErrorModel.CHARGE_FULL_S; holding longer is overcharge (more error).
	var held_s: float = now - float(_charge.started_at)
	_charge.power = KickErrorModel.charge_power(held_s, catalog.value("minimum_power", 0.2))
	_charge.overcharge_s = KickErrorModel.overcharge(held_s)
	if emit_update and (changed or now - float(_charge.last_update_at) >= catalog.value("continuous_update_seconds", 0.05)):
		_charge.last_update_at = now
		_emit_from_charge(_charge, "update", "" if _charge.valid else "unsupported_variant")

func _kick_allowed(params: Dictionary, announce: bool = true) -> bool:
	if not _allowed(params.action, announce):
		return false
	# A spin-high combination needs both advertised physical capabilities.
	if params.action == "pass_spin" and params.style == "high":
		return _allowed("pass_high", announce)
	return true

func _adjust_elevation(sign_value: float) -> void:
	var change := sign_value * catalog.value("elevation_step_deg", 5.0)
	if is_held("high") or (not _charge.is_empty() and _charge.token == "pass" and is_held("high")):
		high_elevation = clampf(high_elevation + change, 5.0, catalog.value("max_elevation_deg", 65.0))
	else:
		shot_elevation = clampf(shot_elevation + change, 0.0, catalog.value("max_elevation_deg", 65.0))

func _move_vector() -> Vector3:
	var axes := Vector2(float(int(is_held("right")) - int(is_held("left"))), float(int(is_held("forward")) - int(is_held("back"))))
	return (aim_right * axes.x + aim_forward * axes.y).limit_length(1.0)

func _move_or_aim() -> Vector3:
	var move := _move_vector()
	return move.normalized() if move.length_squared() > 0.0001 else aim_forward

func _update_continuous() -> void:
	var desired: Dictionary = {}
	var move := _move_vector()
	var has_movement := move.length_squared() > 0.0001
	var stance := is_held("stance")
	var close := is_held("close")
	var sprint := is_held("sprint") and not stance and not close
	if has_movement and _allowed("move", false):
		desired["move"] = {"direction": move.normalized(), "power": move.length(), "elevation_deg": 0.0, "spin": Vector3.ZERO, "style": "walk" if close or stance else "sprint" if sprint else "run"}
	if context.phase == "live" and _charge.is_empty() and _buffer.is_empty():
		if context.possession == "foot":
			if stance:
				desired["shield"] = _policy_params("protect")
			elif close:
				desired["close_control"] = _policy_params("near")
			elif sprint and has_movement:
				desired["push_ball"] = _policy_params("stride")
		elif context.possession == "none":
			if context.role == "goalkeeper" and is_held("shot"):
				desired["keeper_ready"] = _policy_params("hands_ready")
			elif stance:
				desired["pressure"] = _policy_params("jockey")
	for action in _continuous.keys():
		if not desired.has(action) or not _allowed(action, false):
			_end_continuous(action, "released_or_superseded")
	for action in desired:
		if not _allowed(action):
			continue
		var params: Dictionary = desired[action]
		params["actor_id"] = context.actor_id
		params["context_revision"] = context_revision
		if not _continuous.has(action):
			_continuous[action] = params
			_last_continuous_time[action] = now
			_emit(action, "begin", params)
		elif _continuous[action] != params or now - float(_last_continuous_time[action]) >= catalog.value("continuous_update_seconds", 0.05):
			_continuous[action] = params
			_last_continuous_time[action] = now
			_emit(action, "update", params)

func _policy_params(style: String) -> Dictionary:
	return {"direction": _move_or_aim(), "power": 1.0, "elevation_deg": 0.0, "spin": Vector3.ZERO, "style": style}

func _allowed(action: String, announce: bool = true) -> bool:
	var status := availability(action)
	if not status.enabled and announce:
		_notify(status.code, status.reason, action)
	return status.enabled

func _cooldown_key(action: String) -> String:
	return catalog.definition(action).get("charge_family", action)

func _ready_for(action: String) -> bool:
	if now < float(_cooldowns.get(_cooldown_key(action), -1.0)):
		_notify("cooldown", catalog.label(action) + "输入间隔中，请稍后重按", action)
		return false
	if catalog.definition(action).has("charge_family") and not context.action_ready:
		_notify("action_busy", "当前动作尚未结束，请稍后重按", action)
		return false
	return true

func buffer_window_seconds() -> float:
	# Tiny input assistance only; never grows into a second action scheduler.
	return clampf(catalog.value("input_buffer_seconds", 0.0), 0.0, 0.075)

func _is_ready(action: String) -> bool:
	if context.host_kick_queue and catalog.definition(action).has("charge_family"):return context.action_ready
	return now >= float(_cooldowns.get(_cooldown_key(action), -1.0)) and (not catalog.definition(action).has("charge_family") or context.action_ready)

func _can_start_charge(action: String) -> bool:
	if context.host_kick_queue and catalog.definition(action).has("charge_family"):return context.action_ready
	if _is_ready(action):
		return true
	var cooldown_remaining := float(_cooldowns.get(_cooldown_key(action), now)) - now
	if buffer_window_seconds() > 0.0 and cooldown_remaining <= buffer_window_seconds():
		return true
	return _ready_for(action)

func _refresh_edge() -> void:
	if not bool(catalog.profile.get("edge_updates", false)) or not gameplay_allowed():
		return
	if not _charge.is_empty():
		_update_charge()
	_update_continuous()

func _commit(action: String, direction: Vector3, power: float, elevation: float, spin: Vector3, style: String, extra: Dictionary = {}) -> bool:
	if not _allowed(action):
		return false
	var params := {"direction": direction.normalized(), "power": clampf(power, 0.0, 1.0), "elevation_deg": elevation, "spin": spin, "style": style}
	params.merge(extra)
	if not _is_ready(action):
		if catalog.definition(action).has("charge_family") and buffer_window_seconds() > 0.0 and _buffer.is_empty():
			var cooldown_remaining := float(_cooldowns.get(_cooldown_key(action), now)) - now
			if cooldown_remaining <= buffer_window_seconds():
				params["actor_id"] = context.actor_id
				params["context_revision"] = context_revision
				_buffer = {"action": action, "params": params, "started_at": now,
					"expires_at": now + buffer_window_seconds(), "context_revision": context_revision}
				_notify("buffered", "已暂存传射，最多等75毫秒；中键取消", action)
				return true
		_ready_for(action)
		return false
	_publish_commit(action, params)
	return true

func _publish_commit(action: String, params: Dictionary) -> void:
	_emit(action, "commit", params)
	_cooldowns[_cooldown_key(action)] = now + float(catalog.definition(action).get("cooldown_seconds", 0.0))

func _process_buffer() -> void:
	if _buffer.is_empty():
		return
	if _buffer.context_revision != context_revision or not _allowed(_buffer.action, false):
		_cancel_buffer("context_changed")
		return
	if now > float(_buffer.expires_at) + 0.0000001:
		_cancel_buffer("buffer_timeout")
		_notify("buffer_timeout", "等待超时，传射已取消；请重新操作")
		return
	if _is_ready(_buffer.action):
		var action: String = _buffer.action
		var params: Dictionary = _buffer.params.duplicate(true)
		_buffer.clear()
		_publish_commit(action, params)

func _cancel_buffer(reason: String) -> void:
	if _buffer.is_empty():
		return
	var action: String = _buffer.action
	var params: Dictionary = _buffer.params.duplicate(true)
	_buffer.clear()
	_emit(action, "cancel", params, reason)

func _emit(action: String, phase: String, params: Dictionary, reason: String = "") -> void:
	sequence += 1
	var payload := {"schema_version": 1, "sequence": sequence,
		"actor_id": context.actor_id, "context_revision": context_revision,
		"action": action, "phase": phase, "direction": Vector3.ZERO,
		"power": 0.0, "elevation_deg": 0.0, "spin": Vector3.ZERO,
		"style": "", "reason": reason}
	payload.merge(params, true)
	payload.elevation_deg = clampf(float(payload.elevation_deg), 0.0, catalog.value("max_elevation_deg", 65.0))
	intent_emitted.emit(payload)

func _emit_from_charge(charge: Dictionary, phase: String, reason: String = "") -> void:
	_emit(charge.action, phase, {"actor_id": charge.actor_id, "context_revision": charge.context_revision,
		"gesture_id": charge.gesture_id,
		"direction": charge.direction, "power": charge.power, "elevation_deg": charge.elevation_deg,
		"spin": charge.spin, "style": charge.style, "valid": charge.valid,
		"overcharge_s": float(charge.get("overcharge_s", 0.0))}, reason)

func _cancel_charge(reason: String) -> void:
	if _charge.is_empty():
		return
	_emit_from_charge(_charge, "cancel", reason)
	_charge.clear()

func _block_token_sources(tokens: Array) -> void:
	for source in _sources:
		if tokens.has(_sources[source]):
			_blocked[source] = true

func _end_continuous(action: String, reason: String) -> void:
	if not _continuous.has(action):
		return
	var params: Dictionary = _continuous[action].duplicate(true)
	params.power = 0.0
	_emit(action, "end", params, reason)
	_continuous.erase(action)
	_last_continuous_time.erase(action)

func _end_all_continuous(reason: String) -> void:
	for action in _continuous.keys():
		_end_continuous(action, reason)

func _notify(code: String, message: String, action: String = "") -> void:
	var notice_key := code + ":" + action
	if now - float(_last_notice.get(notice_key, -10.0)) < 0.8:
		return
	_last_notice[notice_key] = now
	notice_emitted.emit({"code": code, "action": action, "message_zh": message})
