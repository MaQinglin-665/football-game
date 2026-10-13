extends "res://tests/continuous_control.gd"
## Same real-input full tiers, then release S at several foot-action phases.
## No ball/actor/ownership writes after the inherited initial real RECEIVE.
var release_cases: Array[Dictionary] = []

func _initialize() -> void:
	AudioServer.set_bus_mute(0,true)
	super._initialize()

func full_tier_sequence() -> void:
	await super.full_tier_sequence()
	for duration in [.10,.22,.55,1.70]:
		var tag := "%.2f" % duration
		await segment("phase_pull_"+tag,duration,[KEY_S])
		var release := {"hold_seconds":duration,"foot_kind":game.player.foot.kind,"phase":FootballFootAction.Phase.keys()[game.player.foot.phase],"hit":game.player.foot.hit,"gap_m":game.flat_distance(game.ball.position,game.player.position),"ball_ahead_m":(game.ball.position-game.player.position).dot(game.player.body_facing)}
		await segment("phase_stop_"+tag,1.0,[])
		var result: Dictionary = stages.back()
		release["stop"] = result
		release_cases.append(release)
		check("release S after "+tag+"s remains controlled and stops",result.owned_fraction==1.0 and result.final_gap<.55 and result.ball_final_speed<.08,release)
	FileAccess.open(evidence.path_join("retreat_release_phases.json"),FileAccess.WRITE).store_string(JSON.stringify({"scope":"Real input after full tiers, four backward/stop pairs without additional state fixture or resetting the ball. Foot phases are measured, not assigned.","cases":release_cases},"\t"))
