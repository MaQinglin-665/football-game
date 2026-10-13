class_name FootballShiftLegacyOverlay
extends RefCounted
## Optional NEXT/v1 bridge. Does not reach into either router or any actor/ball.
var _sequence := 0

func route_legacy(intent: Dictionary, policy: Dictionary) -> Dictionary:
	var output: Dictionary = route(intent, policy)
	return {} if output.is_empty() else _stamp(output, "football_input")

func route_shift(intent: Dictionary) -> Dictionary:
	return _stamp(intent, "football_shift_tiers")

func _stamp(intent: Dictionary, stream: String) -> Dictionary:
	var output: Dictionary = intent.duplicate(true)
	_sequence += 1
	output["input_stream"] = stream
	output["source_sequence"] = output.get("sequence", 0)
	output["sequence"] = _sequence
	return output

static func route(intent: Dictionary, policy: Dictionary) -> Dictionary:
	# All phases of the old continuous stride request must be filtered together.
	if intent.get("action", "") == "push_ball" and intent.get("style", "") == "stride":
		return {}
	var output: Dictionary = intent.duplicate(true)
	if output.get("action", "") == "move":
		output["tier"] = policy.get("tier", "walk_jog")
		output["control_style"] = policy.get("control_style", "none")
		if output.get("style", "") == "sprint":
			output["style"] = "run" # Prevent a legacy consumer choosing max speed.
	return output
