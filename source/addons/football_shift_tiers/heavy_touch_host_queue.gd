class_name FootballHeavyTouchHostQueue
extends RefCounted
## One explicit command waiting for a host foot slot. No ball/actor references.
signal command_cancelled(intent: Dictionary)
signal state_changed(state: Dictionary)

const MAX_WAIT_MS := 400
var _pending: Dictionary = {}
var _seen: Dictionary = {}
var _last_state: Dictionary = {"state": "idle"}

func offer(intent: Dictionary, context: Dictionary, timestamp_usec: int = -1) -> bool:
	var now: int = _clock(timestamp_usec)
	if intent.get("action", "") != "push_ball" or intent.get("phase", "") != "commit" or intent.get("style", "") != "deliberate_heavy_touch" or intent.get("request_mode", "") != "next_foot_window":
		return false
	var gesture: String = intent.get("gesture_id", "")
	if gesture.is_empty() or _seen.has(gesture):
		return false
	var reason := _denial(intent, context)
	var requested: int = intent.get("requested_at_usec", now)
	var wait_ms: int = clampi(int(intent.get("next_contact_wait_ms", 350)), 100, MAX_WAIT_MS)
	var deadline: int = requested + wait_ms * 1000
	if requested > now or now > deadline:
		reason = "command_expired"
	if not _pending.is_empty():
		reason = "command_pending"
	_seen[gesture] = true
	if _seen.size() > 32:
		_seen.erase(_seen.keys()[0])
	if not reason.is_empty():
		_cancel_payload(intent, reason, now)
		return false
	_pending = {"intent": intent.duplicate(true), "role": context.get("role", "outfield"),
		"expires_at_usec": deadline, "accepted_at_usec": now}
	_record("queued", intent, now)
	return true

func observe_context(context: Dictionary, timestamp_usec: int = -1) -> void:
	if _pending.is_empty():
		return
	var now: int = _clock(timestamp_usec)
	var reason := _denial(_pending.intent, context)
	if context.get("role", "outfield") != _pending.role:
		reason = "actor_changed"
	if now > int(_pending.expires_at_usec):
		reason = "command_expired"
	if not reason.is_empty():
		cancel(reason, now)

func take_ready(context: Dictionary, timestamp_usec: int = -1) -> Dictionary:
	var now: int = _clock(timestamp_usec)
	observe_context(context, now)
	if _pending.is_empty() or not bool(context.get("action_ready", false)):
		return {}
	var intent: Dictionary = _pending.intent.duplicate(true)
	intent["host_wait_ms"] = float(now - int(intent.requested_at_usec)) / 1000.0
	intent["dispatch_at_usec"] = now
	_pending.clear()
	_record("dispatched", intent, now)
	return intent

func dispatch_result(intent: Dictionary, accepted: bool, timestamp_usec: int = -1) -> void:
	var now: int = _clock(timestamp_usec)
	if accepted:
		_record("scheduled", intent, now)
	else:
		_cancel_payload(intent, "host_rejected", now)

func cancel(reason: String = "host_reset", timestamp_usec: int = -1) -> void:
	if _pending.is_empty():
		return
	var intent: Dictionary = _pending.intent.duplicate(true)
	_pending.clear()
	_cancel_payload(intent, reason, _clock(timestamp_usec))

func snapshot() -> Dictionary:
	return {"pending": _pending.duplicate(true), "last_state": _last_state.duplicate(true), "seen_count": _seen.size()}

func _denial(intent: Dictionary, context: Dictionary) -> String:
	if context.get("phase", "menu") != "live" or context.get("paused", false) or not context.get("focused", true) or context.get("ui_captured", false):
		return "context_barrier"
	if context.get("possession", "none") != "foot":
		return "no_ball"
	if str(intent.get("actor_id", "")) != str(context.get("actor_id", "")):
		return "actor_changed"
	if intent.get("ball_generation", -1) != context.get("ball_generation", -2) or str(intent.get("restart_id", "")) != str(context.get("restart_id", "")):
		return "ball_or_restart_changed"
	if context.get("close_override", false) or context.get("action_exclusive", false):
		return "exclusive"
	var allowed: Array = context.get("allowed_actions", [])
	if not context.get("capabilities", {}).get("push_ball", false) or (not allowed.is_empty() and not allowed.has("push_ball")):
		return "unsupported_or_denied"
	return ""

func _cancel_payload(intent: Dictionary, reason: String, now: int) -> void:
	var payload: Dictionary = intent.duplicate(true)
	payload["phase"] = "cancel"
	payload["reason"] = reason
	payload["execution_queue"] = "next_foot_window"
	payload["emitted_at_usec"] = now
	_record("cancelled", payload, now)
	command_cancelled.emit(payload)

func _record(state: String, intent: Dictionary, now: int) -> void:
	_last_state = {"state": state, "gesture_id": intent.get("gesture_id", ""),
		"at_usec": now, "reason": intent.get("reason", ""),
		"requested_at_usec": intent.get("requested_at_usec", now)}
	state_changed.emit(_last_state.duplicate(true))

func _clock(timestamp_usec: int) -> int:
	return Time.get_ticks_usec() if timestamp_usec < 0 else timestamp_usec
