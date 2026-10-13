extends RefCounted
## Samples are offline processed CC0 field recordings. No runtime pitch synthesis.
const FILES: Dictionary = {
	"tap": ["tap_r_0", "tap_r_1", "tap_r_2"],
	"pass": ["pass_r_0", "pass_r_1", "pass_r_2"],
	"shot": ["shot_r_0", "shot_r_1", "shot_r_2"],
	"turf": ["turf_r_0", "turf_r_1", "turf_r_2"],
}

static func family(cue: String, strength: float) -> String:
	if cue == "turf": return "turf"
	if cue in ["touch", "dribble"]: return "pass" if strength >= .82 else "tap"
	if cue == "push": return "pass" if strength >= .42 else "tap"
	if cue == "pass": return "shot" if strength >= .88 else "pass" if strength >= .35 else "tap"
	if cue == "shot": return "shot" if strength >= .55 else "pass" if strength >= .20 else "tap"
	return ""

static func gain(strength: float, cue_scale: float) -> float:
	return (.08 + .68 * pow(clampf(strength, 0.0, 1.0), .72)) * cue_scale

static func variant(event_id: String, previous: int, size: int) -> int:
	if size <= 1: return 0
	var seed: int = absi(event_id.hash())
	var chosen: int = seed % size
	if chosen == previous: chosen = (chosen + 1 + (seed >> 8) % (size - 1)) % size
	return chosen
