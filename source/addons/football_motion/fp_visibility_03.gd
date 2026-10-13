extends "res://addons/football_motion/pose_refresh_02.gd"
## Visibility only. Original gait, clock, contacts and support are inherited.
const Arms03 := preload("res://addons/football_motion/fp_arms_03.gd")
var _visible_arms03 := Arms03.new()

func setup(team: int, jersey: int, first_person: bool) -> void:
	super.setup(team,jersey,first_person)
	_visible_arms03.apply(self,first_person)
	set_color_preset(_preset)
