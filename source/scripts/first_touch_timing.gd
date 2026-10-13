class_name FirstTouchTiming
extends RefCounted
## R004 directional first touch: grades how early the player committed a direction
## before the real RECEIVE shoe contact. Pure data; contact code stays authoritative.
## onset_age = contact time - time the current input direction was first chosen.
##   onset_age < LATE_WINDOW_S             -> LATE   (rushed: heavy touch + aim error)
##   LATE_WINDOW_S..ON_TIME_WINDOW_S       -> ON_TIME (tight, accurate touch)
##   > ON_TIME_WINDOW_S                    -> EARLY  (committed early: slightly heavy)
##   no direction held                     -> NONE   (existing cushion, unchanged)
const LATE_WINDOW_S := 0.06
const ON_TIME_WINDOW_S := 0.25
const DIRECTION_CHANGE_DEG := 25.0 # a turn larger than this restarts the onset clock
const LEAD_SCALE := {"LATE": 1.35, "ON_TIME": 0.80, "EARLY": 1.15, "NONE": 1.0}
const AIM_ERROR_DEG := {"LATE": 10.0, "ON_TIME": 0.0, "EARLY": 0.0, "NONE": 0.0}

var direction := Vector3.ZERO
var onset_time := -1.0
var last_grade := {}

func observe(input_direction: Vector3, now: float) -> void:
	var d := Vector3(input_direction.x, 0, input_direction.z)
	if d.length_squared() < .0025:
		direction = Vector3.ZERO
		onset_time = -1.0
		return
	d = d.normalized()
	if direction == Vector3.ZERO or rad_to_deg(direction.angle_to(d)) > DIRECTION_CHANGE_DEG:
		onset_time = now
	direction = d

static func grade_for_age(age: float) -> String:
	if age < 0.0: return "NONE"
	if age < LATE_WINDOW_S: return "LATE"
	if age <= ON_TIME_WINDOW_S: return "ON_TIME"
	return "EARLY"

func grade(now: float) -> Dictionary:
	var age: float = now - onset_time if onset_time >= 0.0 else -1.0
	var g := grade_for_age(age)
	last_grade = {"grade": g, "onset_age_s": age, "lead_scale": LEAD_SCALE[g], "aim_error_deg": AIM_ERROR_DEG[g]}
	return last_grade

## Deterministic aim error: rotate away from the side the ball came from (no RNG).
static func apply_aim_error(aim: Vector3, error_deg: float, side: float) -> Vector3:
	if error_deg <= 0.0: return aim
	return aim.rotated(Vector3.UP, deg_to_rad(error_deg) * (1.0 if side >= 0.0 else -1.0))
