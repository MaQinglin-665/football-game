extends Resource
## Optional match configuration; the ordinary 11v11 scene has no profile.
const Dimensions := preload("res://addons/modern_stadium/stadium_dimensions.gd")
const Roles := preload("res://scripts/tactics/role_catalog.gd")
@export var pitch_length := 36.0
@export var pitch_width := 24.0
@export var goal_width := 3.0
@export var goal_height := 1.5
@export var reset_seconds := 0.9
@export var low_pressure := false

func dimensions() -> Resource:
	var d := Dimensions.new()
	d.pitch_length = pitch_length
	d.pitch_width = pitch_width
	d.goal_width = goal_width
	d.goal_height = goal_height
	d.goal_depth = 1.4
	d.goal_area_depth = 1.5
	d.penalty_area_depth = 4.0
	d.penalty_distance = 3.0
	d.circle_radius = 2.5
	d.corner_radius = 0.4
	d.runoff = 3.0
	d.perimeter_clearance = 5.0
	d.regulation_markings = false
	d.quality_label = "training_3v3"
	return d

func roster(team: int, ids: Array, human_id := -1) -> Array[Dictionary]:
	assert(ids.size() == 3)
	var result: Array[Dictionary] = []
	var roles := [Roles.ATTACKING_MIDFIELDER, Roles.CENTER_BACK, Roles.STRIKER]
	var lanes := [-.65, 0.0, .65]
	var slots := ["LF","BACK","RF"]
	var duties := ["link", "hold", "finish"]
	for i in range(3):
		result.append({"id":int(ids[i]), "team":team, "role":roles[i], "lane":lanes[i], "duty":duties[i], "slot":slots[i], "is_goalkeeper":false, "human":int(ids[i]) == human_id})
	return result

func homes() -> Array[Vector2]:
	return [Vector2(-pitch_width*.18,pitch_length*.10),Vector2(0,pitch_length*.28),Vector2(pitch_width*.18,pitch_length*.10)]
