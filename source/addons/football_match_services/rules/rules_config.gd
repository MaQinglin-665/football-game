class_name FBMatchRulesConfig
extends Resource

# Boundaries are OUTER edges of painted lines, measured from the pitch centre.
@export var half_width: float = 34.0
@export var half_length: float = 52.5
@export var goal_half_width: float = 3.66
@export var goal_height: float = 2.44
@export var penalty_half_width: float = 20.16
@export var penalty_depth: float = 16.5
@export var goal_area_half_width: float = 9.16
@export var goal_area_depth: float = 5.5
@export var penalty_distance: float = 11.0
@export var corner_radius: float = 1.0
@export var ball_radius: float = 0.11
@export var team_size: int = 11
@export var kick_clearance: float = 9.15
@export var throw_clearance: float = 2.0
@export var drop_clearance: float = 4.0
@export var actor_margin: float = 0.35
# Arcade stop-clock, equal halves; set 2700 for a full 45-minute half.
@export var half_seconds: float = 120.0
@export var half_time_seconds: float = 4.0
@export var stoppage_seconds: float = 0.35
@export var restart_prepare_seconds: float = 0.6
@export var celebration_seconds: float = 1.8
@export var restart_retry_seconds: float = 8.0
@export var restart_flight_timeout: float = 5.0
@export var human_taker_preference_range: float = 5.0
@export var allow_proxy_goalkeeper: bool = true
@export var reassign_absent_human_taker: bool = true
@export var restart_plan_refresh_seconds: float = 0.75

func apply_stadium_layout(layout: Dictionary) -> PackedStringArray:
	# Separate geometry task's get_layout() is the source of dimensions. Never use boards.
	if str(layout.get("boundary_measurement", "outer_edge")) != "outer_edge":
		return PackedStringArray(["Rules require outer-edge boundary measurements"])
	half_width = float(layout.get("field_half_width", half_width))
	half_length = float(layout.get("field_half_length", half_length))
	goal_half_width = float(layout.get("goal_width_clear", goal_half_width * 2.0)) * 0.5
	goal_height = float(layout.get("goal_height_clear", goal_height))
	penalty_half_width = float(layout.get("penalty_area_half_width", penalty_half_width))
	penalty_depth = half_length - float(layout.get("penalty_area_front_abs_z", half_length - penalty_depth))
	goal_area_half_width = float(layout.get("goal_area_half_width", goal_area_half_width))
	goal_area_depth = half_length - float(layout.get("goal_area_front_abs_z", half_length - goal_area_depth))
	penalty_distance = half_length - float(layout.get("penalty_spot_abs_z", half_length - penalty_distance))
	kick_clearance = float(layout.get("circle_radius_outer", kick_clearance))
	corner_radius = float(layout.get("corner_radius_outer", corner_radius))
	return validate()

func validate() -> PackedStringArray:
	var issues := PackedStringArray()
	if half_width <= 0.0 or half_length <= 0.0 or half_seconds <= 0.0:
		issues.append("Pitch dimensions and half duration must be positive")
	if penalty_depth >= half_length or penalty_half_width >= half_width:
		issues.append("Penalty area must fit within a half of the pitch")
	if goal_area_depth >= penalty_depth or goal_area_half_width >= penalty_half_width:
		issues.append("Goal area must fit within the penalty area")
	if penalty_distance <= 0.0 or penalty_distance >= penalty_depth:
		issues.append("Penalty mark must lie in the penalty area")
	if goal_half_width <= ball_radius or goal_height <= ball_radius * 2.0:
		issues.append("Goal mouth must be larger than the ball")
	if team_size < 1:
		issues.append("Team size must be positive")
	return issues

static func small_pitch() -> FBMatchRulesConfig:
	var value := FBMatchRulesConfig.new()
	value.half_width = 20.0
	value.half_length = 30.0
	value.goal_half_width = 3.0
	value.goal_height = 2.4
	value.penalty_half_width = 8.0
	value.penalty_depth = 8.0
	value.goal_area_half_width = 4.0
	value.goal_area_depth = 3.0
	value.penalty_distance = 6.0
	value.kick_clearance = 6.0
	value.team_size = 5
	return value
