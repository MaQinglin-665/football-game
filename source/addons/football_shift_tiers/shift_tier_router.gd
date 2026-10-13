class_name FootballShiftTierRouter
extends RefCounted
## Input semantics only. The host owns movement, scheduling and real contacts.
signal policy_changed(policy: Dictionary)
signal intent_emitted(intent: Dictionary)
signal notice_emitted(notice: Dictionary)

const SCOPE_KEYS := ["actor_id", "role", "possession", "phase", "paused", "focused",
	"ui_captured", "restart_id", "ball_generation", "capabilities", "allowed_actions",
	"close_override", "action_exclusive"]
const BARRIER_KEYS := ["actor_id", "role", "phase", "paused", "focused", "ui_captured"]
const EPSILON_DIRECTION := 0.000001

var context: Dictionary = {
	"actor_id": "local", "role": "outfield", "possession": "none", "phase": "menu",
	"paused": false, "focused": true, "ui_captured": false, "restart_id": "",
	"ball_generation": 0, "capabilities": {}, "allowed_actions": [],
	"action_ready": true, "close_override": false, "action_exclusive": false
}
var context_revision := 0
var double_press_window_usec := 260000
var max_first_hold_usec := 180000
var burst_quiet_usec := 260000
var input_buffer_usec := 75000
var heavy_touch_power := 0.8
var host_next_contact_dispatch := false
var next_contact_wait_ms := 350
var _now_usec := -1
var _sequence := 0
var _gesture_counter := 0
var toggle_sprint := false
var _sprint_toggled := false
var _sources: Dictionary = {}
var _blocked: Dictionary = {}
var _candidate: Dictionary = {}
var _pending: Dictionary = {}
var _burst_locked := false
var _last_edge_usec := -1
var _move_direction := Vector3.ZERO
var _aim_forward := Vector3.FORWARD
var _last_policy: Dictionary = {}

func _init(config: Dictionary = {}) -> void:
	toggle_sprint = bool(config.get("toggle_sprint",false))
	var window_ms: int = clampi(int(config.get("double_press_window_ms", 260)), 100, 500)
	double_press_window_usec = window_ms * 1000
	max_first_hold_usec = clampi(int(config.get("max_first_hold_ms", 180)), 1, window_ms) * 1000
	burst_quiet_usec = maxi(int(config.get("burst_quiet_ms", 260)), window_ms) * 1000
	input_buffer_usec = int(clampi(int(config.get("input_buffer_ms", 75)), 0, 75) * 1000)
	heavy_touch_power = clampf(float(config.get("heavy_touch_power", 0.8)), 0.0, 1.0)
	host_next_contact_dispatch = config.get("deliberate_touch_dispatch", "legacy_input_buffer") == "host_next_contact"
	next_contact_wait_ms = clampi(int(config.get("next_contact_wait_ms", 350)), 100, 400)

func set_context(patch: Dictionary, timestamp_usec: int = -1) -> void:
	_set_clock(timestamp_usec)
	var before: Dictionary = context.duplicate(true)
	for key in patch:
		if context.has(key):
			context[key] = patch[key].duplicate(true) if patch[key] is Dictionary or patch[key] is Array else patch[key]
	var scope_changed := false
	var barrier_changed := false
	for key in SCOPE_KEYS:
		scope_changed = scope_changed or before[key] != context[key]
	for key in BARRIER_KEYS:
		barrier_changed = barrier_changed or before[key] != context[key]
	if scope_changed:
		context_revision += 1
		_candidate.clear()
		_cancel_pending("context_changed")
	if barrier_changed or before.restart_id != context.restart_id or before.ball_generation != context.ball_generation:
		_sprint_toggled = false
		for source in _sources:
			_blocked[source] = true
		_burst_locked = false
	_publish_policy()
	_process_pending()

func set_direction(move_direction: Vector3, aim_forward: Vector3 = Vector3.FORWARD) -> void:
	_move_direction = Vector3(move_direction.x, 0.0, move_direction.z)
	var planar_aim := Vector3(aim_forward.x, 0.0, aim_forward.z)
	if planar_aim.length_squared() > EPSILON_DIRECTION:
		_aim_forward = planar_aim.normalized()

func gameplay_allowed() -> bool:
	return bool(context.focused) and not bool(context.paused) and not bool(context.ui_captured) and context.phase in ["live", "dead_ball"]

func feed_shift(pressed: bool, source: String = "shift", echo: bool = false, timestamp_usec: int = -1) -> bool:
	if source.is_empty():
		return false
	_set_clock(timestamp_usec)
	_process_pending()
	if echo:
		return true
	var was_held := _shift_held()
	if not pressed:
		if not _sources.has(source):
			return true
		_sources.erase(source)
		_blocked.erase(source)
		_last_edge_usec = _now_usec
		if was_held and not _shift_held() and _sources.is_empty() and not _candidate.is_empty():
			var held_usec: int = _now_usec - int(_candidate.pressed_at_usec)
			if _candidate.source == source and held_usec <= max_first_hold_usec:
				_candidate.released = true
				_candidate.first_hold_usec = held_usec
			else:
				_candidate.clear()
		_publish_policy()
		return true
	if _sources.has(source):
		return true
	var had_physical_source := not _sources.is_empty()
	_sources[source] = true
	_last_edge_usec = _now_usec
	if not gameplay_allowed() or not _blocked.is_empty():
		_blocked[source] = true
		_candidate.clear()
		_publish_policy()
		return true
	# Physical edges still identify doubles; the latch alone owns sprint mode.
	if toggle_sprint and not had_physical_source and not _burst_locked:
		_sprint_toggled = not _sprint_toggled
	_publish_policy() # No delay waiting for the double-press window.
	if had_physical_source:
		_candidate.clear() # Two overlapping Shift keys cannot fake a double.
		return true
	if _burst_locked:
		return true
	if not _candidate.is_empty() and bool(_candidate.released) and _candidate.source == source and _now_usec - int(_candidate.pressed_at_usec) <= double_press_window_usec:
		var first_hold_usec: int = _candidate.first_hold_usec
		var interval_usec: int = _now_usec - int(_candidate.pressed_at_usec)
		_candidate.clear()
		_burst_locked = true
		if toggle_sprint:
			_sprint_toggled = true # Double Shift means big touch and continued chase.
			_publish_policy()
		_request_heavy_touch(interval_usec, first_hold_usec)
		return true
	_candidate = {"source": source, "pressed_at_usec": _now_usec, "released": false, "first_hold_usec": 0}
	return true

func tick(timestamp_usec: int = -1) -> void:
	_set_clock(timestamp_usec)
	_process_pending()

func reset(reason: String = "host_reset", timestamp_usec: int = -1) -> void:
	_set_clock(timestamp_usec)
	_candidate.clear()
	_cancel_pending(reason)
	_sprint_toggled = false
	_burst_locked = false
	for source in _sources:
		_blocked[source] = true
	_publish_policy()

func cancel_heavy_touch(reason: String = "input_cancel", timestamp_usec: int = -1) -> void:
	_set_clock(timestamp_usec)
	_candidate.clear()
	_cancel_pending(reason)

func policy() -> Dictionary:
	var held := _shift_held()
	var enabled := gameplay_allowed() and _action_allowed("move")
	var requested:bool = _sprint_toggled if toggle_sprint else held
	var tier := "run" if enabled and requested and not context.close_override else "walk_jog"
	var control_style := "none"
	if enabled and context.phase == "live" and context.possession == "foot" and not context.action_exclusive and _action_allowed("close_control"):
		control_style = "dribble" if tier == "run" else "close"
	return {"actor_id": context.actor_id, "context_revision": context_revision,
		"tier": tier, "control_style": control_style, "enabled": enabled, "shift_held": held, "sprint_toggled": _sprint_toggled}

func snapshot() -> Dictionary:
	return {"context": context.duplicate(true), "context_revision": context_revision,
		"now_usec": _now_usec, "policy": policy(), "first_press": _candidate.duplicate(true),
		"pending": _pending.duplicate(true), "burst_locked": _burst_locked,
		"physical_source_count": _sources.size(), "blocked_source_count": _blocked.size()}

func help_text_zh() -> String:
	var text := "松开Shift：行走/慢跑与近控\n按住Shift：稳定跑速，连续带球\n快速双击Shift：请求一次大趟，真实脚接触后追球\n首按≤180ms，两次按下间隔≤260ms；连按一段只请求一次\n无球/死球不大趟；Ctrl/C、传射蓄力优先"
	if toggle_sprint:
		text = text.replace("松开Shift：行走/慢跑与近控\n按住Shift：稳定跑速，连续带球", "单击Shift：开启/关闭加速，松键后保持\n双击Shift：大趟并保持加速；暂停/重开/切出窗口后恢复慢跑")
	if host_next_contact_dispatch:
		text += "\n大趟单独等待下一脚，最多%dms；超时或丢球取消" % next_contact_wait_ms
	return text

func _set_clock(timestamp_usec: int) -> void:
	var instant: int = Time.get_ticks_usec() if timestamp_usec < 0 else timestamp_usec
	_now_usec = maxi(_now_usec, instant)
	if not _candidate.is_empty() and _now_usec - int(_candidate.pressed_at_usec) > double_press_window_usec:
		_candidate.clear()
	if _burst_locked and _sources.is_empty() and _last_edge_usec >= 0 and _now_usec - _last_edge_usec >= burst_quiet_usec:
		_burst_locked = false

func _shift_held() -> bool:
	for source in _sources:
		if not _blocked.has(source):
			return true
	return false

func _action_allowed(action: String) -> bool:
	var allowed: Array = context.allowed_actions
	if not allowed.is_empty() and not allowed.has(action):
		return false
	return action == "move" or context.capabilities.get(action, false) == true

func _push_denial() -> String:
	if not gameplay_allowed() or context.phase != "live":
		return "wrong_phase"
	if context.possession != "foot":
		return "no_ball"
	if context.close_override or context.action_exclusive:
		return "exclusive"
	if not _action_allowed("push_ball"):
		return "unsupported_or_denied"
	return ""

func _request_heavy_touch(interval_usec: int, first_hold_usec: int) -> void:
	var denial := _push_denial()
	if not denial.is_empty():
		var messages := {"wrong_phase": "当前比赛状态不允许大趟", "no_ball": "当前没有脚下球，大趟未提交",
			"exclusive": "近控/护球或传射动作优先，大趟未提交", "unsupported_or_denied": "当前能力或位置权限未开放大趟"}
		notice_emitted.emit({"code": denial, "action": "push_ball", "message_zh": messages[denial]})
		return
	if not _pending.is_empty():
		notice_emitted.emit({"code": "buffer_pending", "action": "push_ball", "message_zh": "已有一次大趟等待宿主就绪"})
		return
	_gesture_counter += 1
	var direction := _move_direction.normalized() if _move_direction.length_squared() > EPSILON_DIRECTION else _aim_forward
	var payload := {"schema_version": 1, "actor_id": context.actor_id, "context_revision": context_revision,
		"input_stream": "football_shift_tiers",
		"action": "push_ball", "phase": "commit", "direction": direction,
		"power": heavy_touch_power, "elevation_deg": 0.0, "spin": Vector3.ZERO,
		"style": "deliberate_heavy_touch", "tier": "heavy_touch", "reason": "",
		"gesture_id": "shift:%s:%d:%d" % [context.actor_id, context_revision, _gesture_counter],
		"ball_generation": context.ball_generation, "restart_id": context.restart_id,
		"input_source": "shift_double", "requested_at_usec": _now_usec,
		"double_interval_ms": float(interval_usec) / 1000.0,
		"first_hold_ms": float(first_hold_usec) / 1000.0, "buffered_ms": 0.0}
	if host_next_contact_dispatch:
		# A deliberate command is submitted once now. The host arbitrates the
		# next real foot window in its own bounded slot, not this 75ms buffer.
		payload["request_mode"] = "next_foot_window"
		payload["next_contact_wait_ms"] = next_contact_wait_ms
		_publish_intent(payload)
	elif bool(context.action_ready):
		_publish_intent(payload)
	elif input_buffer_usec > 0:
		_pending = {"payload": payload, "expires_at_usec": _now_usec + input_buffer_usec}
		notice_emitted.emit({"code": "buffered", "action": "push_ball", "message_zh": "大趟意图最多等待75ms；宿主仍须真实脚接触"})
	else:
		payload.phase = "cancel"
		payload.reason = "not_ready"
		_publish_intent(payload)

func _process_pending() -> void:
	if _pending.is_empty():
		return
	if not _push_denial().is_empty():
		_cancel_pending("context_changed")
	elif _now_usec > int(_pending.expires_at_usec):
		_cancel_pending("buffer_timeout")
	elif context.action_ready:
		var payload: Dictionary = _pending.payload.duplicate(true)
		_pending.clear()
		payload.buffered_ms = float(_now_usec - int(payload.requested_at_usec)) / 1000.0
		_publish_intent(payload)

func _cancel_pending(reason: String) -> void:
	if _pending.is_empty():
		return
	var payload: Dictionary = _pending.payload.duplicate(true)
	_pending.clear()
	payload.phase = "cancel"
	payload.reason = reason
	payload.buffered_ms = float(_now_usec - int(payload.requested_at_usec)) / 1000.0
	_publish_intent(payload)

func _publish_policy() -> void:
	var next: Dictionary = policy()
	if next == _last_policy:
		return
	_last_policy = next.duplicate(true)
	_sequence += 1
	var payload: Dictionary = next.duplicate(true)
	payload.schema_version = 1
	payload.input_stream = "football_shift_tiers"
	payload.sequence = _sequence
	payload.changed_at_usec = _now_usec
	policy_changed.emit(payload)

func _publish_intent(payload: Dictionary) -> void:
	_sequence += 1
	payload.sequence = _sequence
	payload.emitted_at_usec = _now_usec
	intent_emitted.emit(payload)
