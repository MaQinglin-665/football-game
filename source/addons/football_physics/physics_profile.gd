class_name FootballPhysicsProfile
extends Resource
## All units SI. Calibration/design parameters are explicitly documented in SOURCES.md.

@export_group("Real scale · identical across presets")
@export var ball_mass_kg: float = 0.43
@export var ball_radius_m: float = 0.11
@export var gravity_mps2: float = 9.81
@export var air_density_kgpm3: float = 1.225
@export var air_viscosity_pas: float = 0.0000181
@export var shell_inertia_factor: float = 2.0 / 3.0
@export var player_mass_kg: float = 78.0
@export var player_radius_m: float = 0.28
@export var player_height_m: float = 1.80

@export_group("Calibratable ball / surface model")
@export var drag_enabled: bool = true
@export var magnus_enabled: bool = true
@export var cd_low_speed: float = 0.47
@export var cd_high_speed: float = 0.18
@export var drag_transition_start_mps: float = 12.0
@export var drag_transition_end_mps: float = 20.0
@export var lift_slope: float = 1.10
@export var lift_coefficient_cap: float = 0.35
@export var air_spin_decay_per_second: float = 0.06
@export var ground_axial_spin_decay_per_second: float = 2.8
@export var roll_deceleration_mps2: float = 0.75
@export var sliding_friction_coefficient: float = 0.32
@export var bounce_friction_coefficient: float = 0.20
@export var turf_restitution: float = 0.60
@export var wall_restitution: float = 0.55
@export var body_restitution: float = 0.12
@export var body_friction_coefficient: float = 0.25
@export var low_bounce_cutoff_mps: float = 0.45
@export var rest_speed_mps: float = 0.025

@export_group("Player motor · tunable human / game design values")
@export var jog_speed_mps: float = 5.6
@export var sprint_speed_mps: float = 8.4
@export var start_acceleration_mps2: float = 6.8
@export var sprint_acceleration_mps2: float = 7.37
@export var theoretical_max_speed_mps: float = 9.61
@export var brake_deceleration_mps2: float = 5.5
@export var turn_acceleration_mps2: float = 6.5
@export var shoulder_restitution: float = 0.03
@export var shoulder_friction_coefficient: float = 0.25
@export var shield_move_speed_mps: float = 2.1

@export_group("Playable assistance · never changes size / mass / gravity")
@export var preset_name: String = "real_scale"
# Design assistance for low-speed supported rolling; zero restores legacy.
@export var low_speed_roll_extra_mps2: float = 0.0
@export var low_speed_roll_full_mps: float = 1.25
@export var low_speed_roll_end_mps: float = 3.5
@export var power_curve_exponent: float = 1.0
@export var pass_min_speed_mps: float = 3.5
@export var pass_max_speed_mps: float = 17.0
@export var loft_pass_min_speed_mps: float = 7.0
@export var loft_pass_max_speed_mps: float = 29.0
@export var pass_arrival_base_mps: float = 4.4
@export var pass_arrival_per_m: float = .18
@export var pass_arrival_max_mps: float = 11.5
@export var heel_max_speed_mps: float = 8.0
@export var ground_pass_distance_mapping_enabled: bool = false
@export var ground_pass_min_distance_m: float = 2.5
@export var ground_pass_max_distance_m: float = 49.0
@export var ground_pass_distance_exponent: float = 1.35
@export var shot_min_speed_mps: float = 9.0
@export var shot_max_speed_mps: float = 32.0
@export var kick_impulse_limit_ns: float = 20.0
@export var pass_spin_max_rads: float = 35.0
@export var shot_spin_max_rads: float = 65.0
@export var receiver_force_budget_n: float = 90.0
@export var receiver_relaxation_time_s: float = 0.075
@export var receiver_sync_ground_roll: bool = false
@export var receiver_spin_brake_per_second: float = 6.0
@export var receiver_contact_tolerance_m: float = 0.06

@export_group("Numerical controls · not extra friction")
@export var internal_step_seconds: float = 1.0 / 240.0
@export var sweep_margin_m: float = 0.0005
@export var ground_probe_m: float = 0.003
@export var max_contacts_per_substep: int = 8
@export var max_body_pairs_per_substep: int = 64
@export var safety_max_speed_mps: float = 120.0
@export var safety_max_spin_rads: float = 500.0

static func real_scale() -> FootballPhysicsProfile:
	return FootballPhysicsProfile.new()

static func playable() -> FootballPhysicsProfile:
	var p := FootballPhysicsProfile.new()
	p.preset_name = "playable"
	p.low_speed_roll_extra_mps2 = 0.75
	p.power_curve_exponent = 0.88
	p.ground_pass_distance_mapping_enabled = true
	p.brake_deceleration_mps2 = 7.5
	p.receiver_force_budget_n = 125.0
	p.receiver_relaxation_time_s = 0.050
	p.receiver_sync_ground_roll = true
	p.receiver_spin_brake_per_second = 9.0
	p.turf_restitution = .52
	return p

func loft_pass_speed(power:float)->float:
	return lerpf(loft_pass_min_speed_mps,loft_pass_max_speed_mps,pow(clampf(power,0,1),power_curve_exponent))

func inertia_kgm2() -> float:
	return shell_inertia_factor * ball_mass_kg * ball_radius_m * ball_radius_m

func validate() -> bool:
	return ball_mass_kg > 0.0 and ball_radius_m > 0.0 and inertia_kgm2() > 0.0 \
		and internal_step_seconds > 0.0 and internal_step_seconds <= 1.0 / 120.0 \
		and player_mass_kg > 0.0 and player_height_m >= 2.0 * player_radius_m \
		and drag_transition_end_mps > drag_transition_start_mps \
		and turf_restitution >= 0.0 and turf_restitution <= 1.0 \
		and roll_deceleration_mps2 >= 0.0 \
		and is_finite(low_speed_roll_extra_mps2) and low_speed_roll_extra_mps2 >= 0.0 \
		and is_finite(low_speed_roll_full_mps) and low_speed_roll_full_mps >= 0.0 \
		and is_finite(low_speed_roll_end_mps) and low_speed_roll_end_mps > low_speed_roll_full_mps \
		and is_finite(ground_pass_min_distance_m) and ground_pass_min_distance_m >= 0.0 \
		and is_finite(ground_pass_max_distance_m) and ground_pass_max_distance_m >= ground_pass_min_distance_m \
		and is_finite(ground_pass_distance_exponent) and ground_pass_distance_exponent > 0.0 \
		and is_finite(pass_max_speed_mps) and pass_max_speed_mps > 0.0 \
		and is_finite(receiver_relaxation_time_s) and receiver_relaxation_time_s >= 0.0 \
		and is_finite(receiver_force_budget_n) and receiver_force_budget_n >= 0.0

@export_range(0.0,.40,.01) var turn_inertia_strength := .22
