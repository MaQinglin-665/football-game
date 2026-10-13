class_name FootballControlTuning
extends Resource
@export_group("Foot geometry")
@export var ball_radius := 0.11
@export var body_radius := 0.27
@export var rest_distance := 0.62
@export var foot_reach := 0.96
@export var foot_contact_radius := 0.11
@export var normal_reach := 0.96
@export var recovery_reach := 0.96
@export var sprint_reach := 0.96
@export var pickup_reach := 1.16
@export var kick_reach := 1.08
@export var body_block_radius := 0.34
@export var normal_leash := 2.45
@export var sprint_leash := 3.10
@export_group("Movement")
@export var normal_ball_speed := 2.8
@export var sprint_ball_speed := 5.0 # Shift hold: continuous running dribble.
@export var close_speed := 1.7
@export var shield_speed := 2.1
@export var turn_speed := 2.0
@export_group("Backward sole carry")
@export var retreat_close_speed := 1.55
@export var retreat_speed := 2.25
@export var retreat_fast_speed := 2.8
@export var retreat_front_distance := .43
@export var retreat_outer_distance := .76
@export var retreat_prediction_seconds := .20
@export var retreat_touch_period := .14
@export var retreat_recovery_seconds := .075
@export_group("Movement response")
@export var body_turn_degrees := 360.0
@export var acceleration := 8.0
@export var sprint_acceleration := 9.0
@export var controlled_deceleration := 12.0
@export_group("Ordinary dribble scheduling")
@export_range(.060,.080,.001) var dribble_direction_debounce_seconds := .070
@export var dribble_high_enter_mps := 2.10
@export var dribble_high_exit_mps := 1.85
@export_group("Touch rhythm")
@export var carry_interval := 0.22
@export var sprint_interval := 0.34
@export var close_interval := 0.17
@export var turn_interval := 0.14
@export var touch_prepare := 0.04
@export var touch_window := 0.055
@export var touch_recover := 0.10
@export var receive_prepare := 0.025
@export var foot_impulse := 3.5
@export var sprint_impulse := 5.2
@export var sprint_push := 3.0
@export var turn_impulse := 4.0
@export var reception_impulse := 24.0
@export var turn_roll_speed := 2.1
@export var pull_speed := 0.95
@export var ground_friction := 2.2
@export_group("Continuous close control · physical contacts only")
@export var near_contact_interval := 0.12
@export var near_relative_speed := 0.22
@export var near_outer_distance := 0.48
@export var near_limit_distance := 0.80
@export var running_contact_interval := 0.22
@export var running_touch_lead := .76
@export var running_touch_horizon := .48
@export var running_control_reach := 1.70
@export var running_relative_speed := 0.46
@export var running_outer_distance := 0.72
@export var big_touch_speed := 7.6
@export var big_touch_buffer_seconds := 0.30
@export var normal_move_speed := 3.2
@export var running_move_speed := 5.6
@export var big_chase_speed := 7.6
@export var big_chase_seconds := 2.4
@export var turn_angle_degrees := 25.0
@export var shield_bias_degrees := 20.0
@export_group("Shared standing tackle")
@export var tackle_prepare := 0.14
@export var tackle_window := 0.08
@export var tackle_reach := 0.96
@export var tackle_hit_recover := 0.22
@export var tackle_miss_recover := 0.46
@export var tackle_cooldown := 0.80
@export var tackle_poke := 2.2
@export var tackle_cone_degrees := 30.0
@export_group("Observed defense")
@export var defender_reaction := 0.16
@export var defender_standoff := 1.75
@export var defender_jockey_speed := 4.1
@export var defender_recovery_speed := 6.2
@export var defender_exposed_gap := 0.90
@export_group("First person")
@export var eye_offset := 0.48
@export var default_pitch_degrees := -39.0
@export var arm_sway := 0.012
@export_group("Restarts")
@export var restart_inset := 1.30
@export var restart_wait := 0.90
@export var restart_clearance := 1.45
@export var human_restart_limit := 3.0
