extends "res://addons/football_motion/fp_visibility_03.gd"
## Visibility-only addition on the released arms path. Bone/root facing is inherited.
const Body01:=preload("res://addons/football_motion/fp_body_01.gd")
var _visible_body01:=Body01.new()

func setup(team:int,jersey:int,first_person:bool)->void:
	super.setup(team,jersey,first_person)
	_visible_body01.apply(self,first_person)
