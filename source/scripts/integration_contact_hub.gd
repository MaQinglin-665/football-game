class_name FootballContactHub
extends Node
## The match owns this hub. Publishing reports a resolved event; it never applies forces.
signal contact_resolved(event: Dictionary)
signal body_contact(event: Dictionary)
signal rule_event(event: Dictionary)

const HISTORY_LIMIT := 512
const ALLOWED_KINDS := ["FOOT_TOUCH", "FOOT_ACTION_FAILED", "BODY_CONTACT", "GOAL", "RESTART"]
var serial := 0
var history: Array[Dictionary] = []
var rejected := 0
var duplicates := 0
var _frame := -1
var _seen: Dictionary = {}

func publish(input: Dictionary) -> bool:
	var kind := String(input.get("kind", ""))
	if not kind in ALLOWED_KINDS:
		rejected += 1
		return false
	for name in ["point", "normal", "before_velocity", "after_velocity", "impulse"]:
		if input.has(name):
			var value: Variant = input[name]
			if not value is Vector3 or not value.is_finite():
				rejected += 1
				return false
	var actor: Variant = input.get("actor", null)
	if kind in ["FOOT_TOUCH", "FOOT_ACTION_FAILED", "BODY_CONTACT"] and not is_instance_valid(actor):
		rejected += 1
		return false
	var frame := int(input.get("physics_frame", Engine.get_physics_frames()))
	if frame != _frame:
		_frame = frame
		_seen.clear()
	var actor_id := int(actor.get_instance_id()) if is_instance_valid(actor) else 0
	var key := "%s:%s:%s:%s" % [actor_id, kind, input.get("action", ""), input.get("sequence", 0)]
	if _seen.has(key):
		duplicates += 1
		return false
	_seen[key] = true
	serial += 1
	var event := input.duplicate()
	event["serial"] = serial
	event["physics_frame"] = frame
	event["actor_id"] = actor_id
	if not event.has("success"):
		event["success"] = kind != "FOOT_ACTION_FAILED"
	history.append(event)
	if history.size() > HISTORY_LIMIT:
		history.pop_front()
	if kind == "BODY_CONTACT":
		body_contact.emit(event)
	elif kind in ["GOAL", "RESTART"]:
		rule_event.emit(event)
	else:
		contact_resolved.emit(event)
	return true

func reset() -> void:
	serial = 0
	history.clear()
	rejected = 0
	duplicates = 0
	_frame = -1
	_seen.clear()

func export_records() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event in history:
		var row := event.duplicate()
		row.erase("actor")
		row.erase("other")
		for name in ["point", "normal", "before_velocity", "after_velocity", "impulse"]:
			if row.has(name):
				var v: Vector3 = row[name]
				row[name] = [v.x, v.y, v.z]
		result.append(row)
	return result
