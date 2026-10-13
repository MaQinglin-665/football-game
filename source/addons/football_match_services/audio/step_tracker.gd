class_name FBMatchStepTracker
extends RefCounted

# Optional fallback only. Prefer model/foot animation planted-foot events when available.
var _actors: Dictionary = {}
var _sequence: int = 0

func observe(actor_id: int, at: Vector3, speed: float, grounded: bool, delta: float) -> Dictionary:
	var previous: Dictionary = _actors.get(actor_id, {"position": at, "distance": 0.0, "cooldown": 0.0})
	var distance := Vector2(at.x, at.z).distance_to(Vector2(previous["position"].x, previous["position"].z))
	previous["position"] = at
	previous["cooldown"] = maxf(0.0, float(previous["cooldown"]) - delta)
	# Warps/restart placement do not become giant bursts of footsteps.
	if not grounded or speed < 0.4 or distance > maxf(2.0, speed * delta * 2.5):
		previous["distance"] = 0.0
		_actors[actor_id] = previous
		return {}
	previous["distance"] += distance
	var stride := 1.65 if speed > 5.0 else 1.15
	var event: Dictionary = {}
	if float(previous["distance"]) >= stride and float(previous["cooldown"]) <= 0.0:
		previous["distance"] = fmod(float(previous["distance"]), stride)
		previous["cooldown"] = 0.17
		_sequence += 1
		event = {"event_id": "step:%d:%d" % [actor_id, _sequence], "actor_id": actor_id,
			"position": at, "speed": speed, "grounded": true}
	_actors[actor_id] = previous
	return event
