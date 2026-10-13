extends "res://addons/football_match_services/rules/rules_engine.gd"
## Only the practice opening differs. Goal crossing and foul/out detection are
## inherited unchanged; the mode controller handles the next short repetition.
var preserve_scores := false

func start(kickoff_team: int = 0) -> void:
	var saved := scores.duplicate()
	super.start(kickoff_team)
	if preserve_scores:
		scores.assign(saved)
	restart.clear()
	_restart_origin.clear()
	_second_touch_actor = -1
	_become_live()
