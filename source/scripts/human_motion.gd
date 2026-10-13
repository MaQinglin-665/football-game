class_name HumanMotion
extends RefCounted
## R004 human-only locomotion curve: explicit accel/decel, speed-dependent heading
## turn rate, sprint plant penalty and a feint (slow-then-cut) burst. AI never uses it.
const ACCEL_MPS2 := 12.0
const SPRINT_ACCEL_MPS2 := 6.0
const DECEL_MPS2 := 18.0
const TURN_RATE_LOW_DEG := 720.0
const TURN_RATE_SPRINT_DEG := 180.0
const TURN_LOW_SPEED := 2.0       # m/s at/below which TURN_RATE_LOW applies
const TURN_SPRINT_SPEED := 7.5    # m/s at/above which TURN_RATE_SPRINT applies
const PLANT_MIN_S := 0.15
const PLANT_MAX_S := 0.25
const PLANT_SPEED := 6.5          # sprint-speed threshold for a planted stop/cut
const CUT_ANGLE_DEG := 60.0       # desired-vs-velocity angle that counts as a cut
const FEINT_DROP_RATIO := 0.60    # speed must fall below 60% of recent peak...
const FEINT_LOOKBACK_S := 0.10    # ...within 0.1 s before the cut
const FEINT_BURST_S := 0.20
const FEINT_BURST_GAIN := 1.15
const PEAK_DECAY_S := 3.0         # peak-speed memory (slow decay ≈ recent cruise speed)

var plant_left := 0.0
var burst_left := 0.0
var peak_speed := 0.0
var since_drop := 99.0
var events: Array[String] = []

func turn_rate_rad(speed: float) -> float:
	return deg_to_rad(lerpf(TURN_RATE_LOW_DEG, TURN_RATE_SPRINT_DEG, smoothstep(TURN_LOW_SPEED, TURN_SPRINT_SPEED, speed)))

## flat: current horizontal velocity; desired: wanted horizontal velocity (already scaled by max speed).
func step(flat: Vector3, desired: Vector3, sprint: float, dt: float) -> Vector3:
	var speed := flat.length()
	peak_speed = maxf(speed, peak_speed - peak_speed * dt / PEAK_DECAY_S)
	since_drop = 0.0 if peak_speed > 1.0 and speed < peak_speed * FEINT_DROP_RATIO else since_drop + dt
	plant_left = maxf(0.0, plant_left - dt)
	burst_left = maxf(0.0, burst_left - dt)
	var want := desired.length()
	var cut := speed > .5 and want > .5 and rad_to_deg(flat.angle_to(desired)) > CUT_ANGLE_DEG
	var hard_stop := want < .2 * speed
	if plant_left <= 0.0 and speed >= PLANT_SPEED and sprint > .5 and (cut or hard_stop):
		plant_left = lerpf(PLANT_MIN_S, PLANT_MAX_S, smoothstep(PLANT_SPEED, 9.5, speed))
		events.append("plant")
	elif cut and since_drop <= FEINT_LOOKBACK_S and speed < PLANT_SPEED and burst_left <= 0.0:
		burst_left = FEINT_BURST_S
		since_drop = 99.0 # one burst per slow-down
		peak_speed = speed
		events.append("feint_burst")
	if burst_left > 0.0:
		desired *= FEINT_BURST_GAIN
		want = desired.length()
	if plant_left > 0.0:
		# Planted: only shed speed along the current heading; no new direction yet.
		return flat.move_toward(Vector3.ZERO, DECEL_MPS2 * dt) if want < speed or cut else flat
	# Heading: rotate current direction toward desired at a speed-dependent rate.
	var heading := flat / speed if speed > .05 else (desired / want if want > .05 else Vector3.ZERO)
	if want > .05 and speed > .05:
		var target_dir := desired / want
		var ang := heading.signed_angle_to(target_dir, Vector3.UP)
		heading = heading.rotated(Vector3.UP, clampf(ang, -turn_rate_rad(speed) * dt, turn_rate_rad(speed) * dt))
	var accel := lerpf(ACCEL_MPS2, SPRINT_ACCEL_MPS2, clampf(sprint, 0, 1))
	if burst_left > 0.0: accel *= FEINT_BURST_GAIN
	var next_speed := move_toward(speed, want, (accel if want > speed else DECEL_MPS2) * dt)
	return heading * next_speed
