class_name FootballKickMapping
extends RefCounted
## Pure conversion from the input module's semantic intent. No input or ball writes.

static func from_input_intent(intent: Dictionary, p: FootballPhysicsProfile) -> Dictionary:
	var action: String = intent.get("action", "")
	if action not in ["pass_ground", "pass_high", "pass_spin", "shoot_straight", "shoot_curve"]:
		return {"accepted": false, "reason": "unsupported_action"}
	var direction: Vector3 = intent.get("direction", Vector3.ZERO)
	var power: float = intent.get("power", 0.0)
	var elevation: float = intent.get("elevation_deg", 0.0)
	var semantic_spin: Vector3 = intent.get("spin", Vector3.ZERO)
	if not direction.is_finite() or not semantic_spin.is_finite() or not is_finite(power) or not is_finite(elevation):
		return {"accepted": false, "reason": "invalid_numbers"}
	if absf(semantic_spin.x) > 0.0001 or absf(semantic_spin.z) > 0.0001:
		return {"accepted": false, "reason": "unsupported_topspin_request"}
	var kind := "shot" if action.begins_with("shoot") else "pass"
	var power_clamped := clampf(power, 0.0, 1.0)
	var spin_limit := p.shot_spin_max_rads if kind == "shot" else p.pass_spin_max_rads
	var spin := Vector3.ZERO
	if action in ["pass_spin", "shoot_curve"]:
		# Rightward bend = -Y omega under F_M = omega cross air_velocity.
		spin = Vector3.DOWN * clampf(semantic_spin.y, -1.0, 1.0) * spin_limit * lerpf(0.35, 1.0, power_clamped)
	if action == "pass_ground":
		elevation = 0.0
	return {"accepted": true, "direction_world": direction,
		"power_01": power_clamped, "lift_degrees": clampf(elevation, 0.0, 65.0),
		"spin_world": spin, "kind": kind}
