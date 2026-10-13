class_name AiAwareness
extends RefCounted
## R004 AI awareness / decision helpers. Pure static functions (deterministic with a
## supplied RNG) so planners stay testable. All values are named, tunable constants.
# Reaction
const REACTION_SLOW_S := 0.40
const REACTION_FAST_S := 0.15
const ABILITY_LOW := 0.85   # ability_touch at/below -> slowest / most random
const ABILITY_HIGH := 1.15  # ability_touch at/above -> fastest / most precise
# Decisions
const HYSTERESIS := 0.15        # new option must be >15% better to replace the current one
const HYSTERESIS_FLOOR := 0.05  # absolute margin for near-zero scores
const TEMP_LOW_ABILITY := 0.35  # softmax temperature (score units)
const TEMP_HIGH_ABILITY := 0.05
const VISION_HALF_DEG := 100.0
const SCAN_MEMORY_S := 1.5
const CALL_BOOST := 0.30        # +30% for the human calling / making a run
# Movement
const TOUCHLINE_BAND_M := 2.0
const TOUCHLINE_PENALTY := 1.5  # carry score at the line; linear to 0 at 2 m
const RECOVER_PACE := 7.0       # track-back pace when far out of position (was 5.8)
const RECOVER_FAR_M := 8.0
# Tackling
const HEAVY_TOUCH_M := 0.55     # carrier ball gap counted as a heavy touch
const BEHIND_DEG := 135.0       # tackler-to-carrier vs carrier travel; beyond = from behind
const CORNERED_M := 2.5         # carrier this close to a line counts as cornered
const MISS_SLOW_S := 0.5        # failed lunge commitment window (0.4–0.6)
const MISS_SPEED_SCALE := 0.55

static func ability01(touch: float) -> float:
	return clampf((touch - ABILITY_LOW) / (ABILITY_HIGH - ABILITY_LOW), 0.0, 1.0)

static func reaction_delay(touch: float) -> float:
	return lerpf(REACTION_SLOW_S, REACTION_FAST_S, ability01(touch))

static func temperature(touch: float) -> float:
	return lerpf(TEMP_LOW_ABILITY, TEMP_HIGH_ABILITY, ability01(touch))

static func in_vision(origin: Vector3, facing: Vector3, target: Vector3) -> bool:
	var to := Vector3(target.x - origin.x, 0, target.z - origin.z)
	var f := Vector3(facing.x, 0, facing.z)
	if to.length() < .5 or f.length() < .01: return true
	return rad_to_deg(f.angle_to(to)) <= VISION_HALF_DEG

static func touchline_penalty(point: Vector3, half_width: float, half_length: float) -> float:
	var gap := minf(half_width - absf(point.x), half_length - absf(point.z))
	return TOUCHLINE_PENALTY * clampf((TOUCHLINE_BAND_M - gap) / TOUCHLINE_BAND_M, 0.0, 1.0)

static func recover_pace(base: float, travel_m: float) -> float:
	return RECOVER_PACE if travel_m >= RECOVER_FAR_M else base

## Softmax pick with hysteresis toward the previous key. choices: [{key, score, ...}]
static func select(choices: Array, previous_key: String, temp: float, rng: RandomNumberGenerator) -> Dictionary:
	if choices.is_empty(): return {}
	var best: Dictionary = choices[0]
	var previous: Dictionary = {}
	for c in choices:
		if float(c.score) > float(best.score): best = c
		if String(c.get("key", "")) == previous_key and previous_key != "": previous = c
	if not previous.is_empty():
		var margin := maxf(HYSTERESIS * absf(float(previous.score)), HYSTERESIS_FLOOR)
		if float(best.score) <= float(previous.score) + margin: return previous
	if temp <= 0.0001: return best
	var weights: Array[float] = []
	var total := 0.0
	for c in choices:
		var w := exp((float(c.score) - float(best.score)) / temp)
		weights.append(w); total += w
	var r := rng.randf() * total
	for i in choices.size():
		r -= weights[i]
		if r <= 0.0: return choices[i]
	return best

static func tackler_behind(tackler: Vector3, carrier: Vector3, carrier_velocity: Vector3) -> bool:
	var v := Vector3(carrier_velocity.x, 0, carrier_velocity.z)
	var to := Vector3(tackler.x - carrier.x, 0, tackler.z - carrier.z)
	if v.length() < .8 or to.length() < .05: return false
	return rad_to_deg(v.angle_to(to)) >= BEHIND_DEG

static func cornered(carrier: Vector3, half_width: float, half_length: float) -> bool:
	return minf(half_width - absf(carrier.x), half_length - absf(carrier.z)) <= CORNERED_M

## Contain-first AI commitment: lunge only on a heavy touch, when cornered, or on an
## exposed ball approached from front/side. From behind only for a heavy touch.
static func should_commit(owner_gap: float, exposed: bool, behind: bool, is_cornered: bool) -> bool:
	var heavy := owner_gap >= HEAVY_TOUCH_M
	if behind: return heavy
	return heavy or is_cornered or exposed
