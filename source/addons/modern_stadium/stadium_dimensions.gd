extends Resource
## Metres. Pitch extents measure the OUTSIDE edge of boundary paint.
## Regulation features remain real-size; custom_training scales markings only.
@export var pitch_length: float = 105.0
@export var pitch_width: float = 68.0
@export var line_width: float = 0.10
@export var goal_width: float = 7.32
@export var goal_height: float = 2.44
@export var goal_depth: float = 2.2
@export var goal_area_depth: float = 5.5
@export var penalty_area_depth: float = 16.5
@export var penalty_distance: float = 11.0
@export var circle_radius: float = 9.15
@export var corner_radius: float = 1.0
@export var flag_height: float = 1.6
@export var runoff: float = 8.0
@export var perimeter_clearance: float = 10.0
@export var tier_rows: PackedInt32Array = PackedInt32Array([18, 14, 22])
@export var row_depth: float = 0.82
@export var row_rise: float = 0.48
@export var seat_spacing: float = 0.52
@export var sector_count: int = 24
@export var crowd_density: float = 0.0
@export var perimeter_collision: bool = true
@export var quality_label: String = "standard"
@export var regulation_markings: bool = true

func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if pitch_length <= pitch_width: errors.append("Length must exceed width.")
	if pitch_width < goal_width + 2.0 * penalty_area_depth + 2.0: errors.append("Penalty boxes must fit pitch width.")
	if pitch_length < 2.0 * (penalty_distance + circle_radius) + 2.0: errors.append("Penalty arcs must fit pitch length.")
	if line_width <= 0.0 or line_width > 0.12: errors.append("Line/post width must be in (0, 0.12].")
	if flag_height < 1.5: errors.append("Corner flag height must be at least 1.5 m.")
	if sector_count < 8 or tier_rows.is_empty(): errors.append("Need at least 8 sectors and one seating tier.")
	if row_depth < 0.65 or row_rise <= 0.0 or seat_spacing < 0.45: errors.append("Seating spacing invalid.")
	if goal_depth <= 0.0 or perimeter_clearance <= goal_depth + 1.0: errors.append("Runoff must clear goal nets.")
	if regulation_markings:
		if pitch_length < 90.0 or pitch_length > 120.0 or pitch_width < 45.0 or pitch_width > 90.0:
			errors.append("Regulation pitch outside Law 1 general dimensions.")
		for pair in [[goal_width, 7.32], [goal_height, 2.44], [goal_area_depth, 5.5], [penalty_area_depth, 16.5], [penalty_distance, 11.0], [circle_radius, 9.15], [corner_radius, 1.0]]:
			if not is_equal_approx(pair[0], pair[1]): errors.append("Regulation preset has changed a fixed Law 1 feature.")
	return errors

func layout() -> Dictionary:
	var hw := pitch_width * 0.5
	var hl := pitch_length * 0.5
	var result := {
		"units": "metres", "axis_width": "X", "axis_length": "Z", "up": "Y",
		"pitch_width": pitch_width, "pitch_length": pitch_length,
		"field_half_width": hw, "field_half_length": hl, "ground_y": 0.0,
		"boundary_measurement": "outer_edge", "line_width": line_width,
		"goal_width_clear": goal_width, "goal_height_clear": goal_height,
		"goal_depth_design": goal_depth, "goal_post_radius": line_width * 0.5,
		"goal_line_center_abs_z": hl - line_width * 0.5,
		"goal_post_center_abs_x": (goal_width + line_width) * 0.5,
		"crossbar_center_y": goal_height + line_width * 0.5,
		"penalty_spot_abs_z": hl - penalty_distance,
		"penalty_area_half_width": goal_width * 0.5 + penalty_area_depth,
		"penalty_area_front_abs_z": hl - penalty_area_depth,
		"goal_area_half_width": goal_width * 0.5 + goal_area_depth,
		"goal_area_front_abs_z": hl - goal_area_depth,
		"circle_radius_outer": circle_radius, "corner_radius_outer": corner_radius,
		"flag_height": flag_height, "regulation_markings": regulation_markings,
		"selected_dimensions_note": "105x68 is a selected common full-size layout, not the only lawful field size.",
		"perimeter_collision_clearance": perimeter_clearance,
		"no_gameplay_rules": true
	}
	return result
