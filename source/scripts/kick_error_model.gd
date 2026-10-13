class_name KickErrorModel
extends RefCounted
## R004 human pass/shot skill-vs-risk model. Pure functions; AI kicks never call it.
const CHARGE_FULL_S := 0.6
const OVERCHARGE_FULL_S := 0.4     # overcharge time that adds +1.0 to the error multiplier
const BASE_ERROR_DEG := {"pass": 1.5, "shot": 2.5}
const ASSIST_SHORT_DEG := 12.0
const ASSIST_LONG_DEG := 6.0
const ASSIST_LONG_M := 20.0
const SPRINT_SPEED_MPS := 8.0      # speed normaliser for the speed term
const BODY_ANGLE_FULL_DEG := 90.0  # body-vs-kick angle giving +1.0
const PRESSURE_RADIUS_M := 3.0     # nearest opponent at 0 m gives +1.0
const BACK_TO_TARGET_DEG := 120.0  # beyond this the error doubles
const WEAK_FOOT_SKILL := 0.7       # error divided by this on the weak foot
const MAX_ERROR_DEG := 25.0

static func charge_power(held_s: float, minimum: float) -> float:
	return clampf(minimum + (1.0 - minimum) * held_s / CHARGE_FULL_S, 0.0, 1.0)

static func overcharge(held_s: float) -> float:
	return maxf(0.0, held_s - CHARGE_FULL_S)

## Snap to receiver when the raw aim lies inside the assist cone; returns direction.
static func assist(aim: Vector3, from: Vector3, receiver_pos: Vector3) -> Vector3:
	var to := Vector3(receiver_pos.x - from.x, 0, receiver_pos.z - from.z)
	var flat := Vector3(aim.x, 0, aim.z)
	if to.length() < .5 or flat.length() < .01: return aim
	var cone := ASSIST_LONG_DEG if to.length() >= ASSIST_LONG_M else ASSIST_SHORT_DEG
	return to.normalized() if rad_to_deg(flat.angle_to(to)) <= cone else aim

## Error standard deviation in degrees.
static func error_deg(kind: String, speed: float, body_kick_angle_deg: float, nearest_opponent_m: float, overcharge_s: float, weak_foot: bool) -> float:
	var speed_term := clampf(speed / SPRINT_SPEED_MPS, 0.0, 1.0)
	var body_term := clampf(body_kick_angle_deg / BODY_ANGLE_FULL_DEG, 0.0, 2.0)
	var pressure_term := clampf((PRESSURE_RADIUS_M - nearest_opponent_m) / PRESSURE_RADIUS_M, 0.0, 1.0)
	var over_term := clampf(overcharge_s / OVERCHARGE_FULL_S, 0.0, 2.0)
	var e: float = float(BASE_ERROR_DEG.get(kind, 2.0)) * (1.0 + speed_term + body_term + pressure_term + over_term)
	if body_kick_angle_deg > BACK_TO_TARGET_DEG: e *= 2.0
	if weak_foot: e /= WEAK_FOOT_SKILL
	return minf(e, MAX_ERROR_DEG)

## Signed sample, clamped to ±2 sigma; rng supplied so tests are deterministic.
static func sample(sigma_deg: float, rng: RandomNumberGenerator) -> float:
	return clampf(rng.randfn(0.0, sigma_deg), -2.0 * sigma_deg, 2.0 * sigma_deg)
