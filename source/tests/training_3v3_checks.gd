extends "res://tests/integration_checks.gd"
var actions: Array[Dictionary] = []
var rule_events: Array[Dictionary] = []

func tap(code: int) -> void:
	key(code, true)
	await ticks(1)
	key(code, false)
	await ticks(1)

func count_action(action: String, human_only := false) -> int:
	return actions.filter(func(e): return e.action == action and (not human_only or e.human)).size()

func fresh_round() -> void:
	release_inputs()
	game.training_mode.defensive_opening = false
	game.training_mode.reset_repetition()

func boundary_fixture(at: Vector3, direction: Vector3) -> void:
	# One starting fixture for each boundary case; crossing uses swept World
	# physics and inherited rules, with no rule-state/score writes in the test.
	game.ball.reset(at)
	game.ball.set_held(false)
	game.ball.apply_impulse_ns(direction * game.ball.mass_kg)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(evidence)
	game = load("res://scenes/training_3v3.tscn").instantiate()
	game.test_mode = true
	root.add_child(game)
	await ticks(3)
	check("training scene opens menu", game.phase == game.Phase.MENU)
	check("fixed human plus five AI", game.players.size() == 6 and game.agents.size() == 5 and game.players[0] == game.player)
	check("three outfield per side, zero goalkeepers", game.rule_roster().filter(func(row): return row.team == 0).size() == 3 and game.rule_roster().filter(func(row): return row.team == 1).size() == 3 and game.rule_roster().filter(func(row): return row.goalkeeper).is_empty())
	check("36x24m layout and 3x1.5m mouth", game.field_half_length == 18.0 and game.field_half_width == 12.0 and game.goal_width == 3.0 and game.goal_height == 1.5)
	check("no bowl roof crowd seat geometry", game.stadium.get_node("Bowl").get_child_count() == 0 and game.stadium.get_node("Roof").get_child_count() == 0 and game.stadium.find_children("*", "MultiMeshInstance3D", true, false).is_empty())
	check("same actors feet ball and sole World modules", game.player.get_script().resource_path == "res://scripts/football_player.gd" and game.agents[0].get_script().resource_path == "res://scripts/football_agent.gd" and game.ball.get_script().resource_path == "res://scripts/football.gd" and game.physics_world.get_script().resource_path == "res://addons/football_physics/physics_world.gd")
	check("training rules configured with no referee", game.services.configuration.team_size == 3 and not game.services.referee_enabled and game.services.configuration.validate().is_empty())
	await capture("training_menu")
	game.contact_hub.contact_resolved.connect(func(e: Dictionary):
		if e.get("success",false):
			actions.append({"action":e.action,"human":e.actor == game.player,"team":e.team,"frame":frames,"point":e.point,"impulse":e.get("impulse",Vector3.ZERO)})
	)
	game.services.rules_event.connect(func(e: Dictionary): rule_events.append(e.duplicate(true)))
	game.hud.menu.get_node("StartMatch").pressed.emit()
	check("start button begins live round with player ball", game.phase == game.Phase.PLAY and game.services.rules.is_ball_live() and game.ball.carrier == game.player)
	await capture("training_opening")
	var first_position: Vector3 = game.player.position
	var first_touches := actions.size()
	key(KEY_W, true)
	await ticks(90)
	key(KEY_A, true)
	await ticks(45)
	key(KEY_A, false)
	key(KEY_D, true)
	await ticks(45)
	key(KEY_D, false)
	key(KEY_W, false)
	key(KEY_S, true)
	await ticks(30)
	key(KEY_S, false)
	await ticks(30)
	check("continuous forward lateral and retreat input moves human", game.flat_distance(first_position,game.player.position) > 2.0, game.player.position)
	check("dribble uses confirmed foot contacts", actions.size() > first_touches, actions.slice(first_touches))
	await capture("training_turn_stop")
	var previous_round: int = game.training_mode.repetitions
	await tap(KEY_R)
	check("R resets current round into player control", game.training_mode.repetitions == previous_round + 1 and game.ball.carrier == game.player and game.phase == game.Phase.PLAY)
	var low_intent := {"pace":5.4,"action":"TACKLE","press":true,"move_target":game.ball.position}
	var reduced: Dictionary = game.training_mode.adapt_intent(game.players[3], low_intent.duplicate(true))
	check("low pressure caps opponent defense and suppresses tackle", reduced.pace == 2.6 and reduced.action != "TACKLE")
	await tap(KEY_F5)
	var ordinary: Dictionary = game.training_mode.adapt_intent(game.players[3], low_intent.duplicate(true))
	check("F5 ordinary pressure leaves stable intent intact", not game.training_mode.low_pressure and ordinary == low_intent)
	await tap(KEY_F5)
	check("F5 returns to low pressure", game.training_mode.low_pressure)
	# Shared physical passing and existing give-and-go planner. One round reset;
	# then input/AI only until this passing segment ends.
	fresh_round()
	var receiver: Node3D = game.get_pass_target(game.player)
	check("two teammates provide a legal opening pass target", receiver != null)
	if receiver != null:
		var aim: Vector3 = receiver.position - game.ball.position
		aim.y = 0
		game.player.reset_view(atan2(-aim.x,-aim.z))
		# Turn the ball with actual carry contacts after looking toward the wing;
		# a camera yaw alone does not move a ball into the new kicking stance.
		key(KEY_W,true)
		await ticks(50)
		var pass_before := count_action("PASS",true)
		key(KEY_Q,true)
		await ticks(12)
		key(KEY_Q,false)
		key(KEY_W,false)
		await ticks(110)
		check("Q pass executes a real human foot contact", count_action("PASS",true) > pass_before, {"actions":actions,"traces":game.input_bridge.traces,"feedback":game.status_message,"foot":game.player.foot.actual_contact})
		check("confirmed pass enters shared give and go planner", game.tactical_director.contact_counts.passes > 0 and game.tactical_director.give_go.has(0), game.tactical_director.give_go)
		key(KEY_E,true)
		await ticks(1)
		key(KEY_E,false)
		await ticks(500)
		check("AI receives through shared contact chain", count_action("RECEIVE") > 0, actions)
		check("AI passes during cooperation loop", count_action("PASS") > count_action("PASS",true), actions)
		await capture("training_cooperation")
	# Goal fixtures at both ends check whole-ball crossing, score ownership,
	# timed reset and score preservation through the ordinary six-actor World.
	fresh_round()
	var blue_before: int = game.scores[0]
	boundary_fixture(Vector3(0,.12,-17.45),Vector3(0,0,-8))
	await ticks(24)
	check("north physical mouth crossing awards blue goal", game.scores[0] == blue_before + 1 and game.phase == game.Phase.GOAL)
	await capture("training_goal")
	await ticks(135)
	check("goal resets quickly and retains score", game.phase == game.Phase.PLAY and game.scores[0] == blue_before + 1 and game.ball.carrier == game.player)
	var yellow_before: int = game.scores[1]
	boundary_fixture(Vector3(0,.12,17.45),Vector3(0,0,8))
	await ticks(24)
	check("south physical mouth crossing awards yellow goal", game.scores[1] == yellow_before + 1)
	await ticks(135)
	var score_before: Array = game.scores.duplicate()
	boundary_fixture(Vector3(0,2.2,-17.45),Vector3(0,0,-8))
	await ticks(24)
	check("ball above small crossbar is not a goal", game.scores == score_before and game.phase == game.Phase.RESTART)
	await ticks(135)
	check("goal line miss resumes short round", game.phase == game.Phase.PLAY and game.scores == score_before)
	boundary_fixture(Vector3(11.45,.12,0),Vector3(8,0,0))
	await ticks(24)
	check("touchline crossing ends repetition", game.phase == game.Phase.RESTART)
	await ticks(135)
	check("touchline quick reset without full throw in", game.phase == game.Phase.PLAY and game.ball.carrier == game.player and game.scores == score_before)
	await tap(KEY_F6)
	check("F6 defensive opening gives yellow possession", game.training_mode.defensive_opening and is_instance_valid(game.ball.carrier) and game.ball.carrier.team == 1)
	await ticks(180)
	await capture("training_defense")
	game.pause_match()
	var elapsed: float = game.training_mode.session_seconds
	var human_at: Vector3 = game.player.position
	await ticks(45)
	check("pause freezes training clock and human motion", game.phase == game.Phase.PAUSED and game.training_mode.session_seconds == elapsed and game.player.position == human_at)
	await capture("training_pause")
	game.resume_match()
	await tap(KEY_F6)
	check("F6 returns to attack with score retained", not game.training_mode.defensive_opening and game.ball.carrier == game.player and game.scores == score_before)
	game.show_menu()
	game.start_match(false)
	check("new menu session clears scores", game.scores == [0,0] and game.training_mode.repetitions == 1)
	game.shutdown_audio()
	game.queue_free()
	await process_frame
	# Full-size scene smoke regression: original main scene is still 22 actors.
	game = load("res://scenes/match.tscn").instantiate()
	game.test_mode = true
	root.add_child(game)
	await ticks(3)
	check("11v11 scene retains default roster dimensions and rules", game.training_configuration == null and game.training_mode == null and game.players.size() == 22 and game.agents.size() == 21 and game.field_half_length == 52.5 and game.field_half_width == 34.0 and game.services.rules.get_script().resource_path == "res://addons/football_match_services/rules/rules_engine.gd" and game.services.configuration.half_seconds == 120.0)
	game.start_match(false)
	check("11v11 still enters ordinary kickoff", game.services.rules.state in [game.Rules.State.RESTART_SETUP,game.Rules.State.RESTART_READY] and game.services.rules.restart.kind == "kickoff")
	game.shutdown_audio()
	var failures := checks.filter(func(c): return not c.passed)
	var report := {"engine":Engine.get_version_info(),"native":native,"input":"Godot synthesized key events, no OS keyboard/mouse or human feel acceptance","checks":checks,"passed":checks.size()-failures.size(),"failed":failures.size(),"frames":frames,"actions":actions,"rule_events":rule_events,"samples":samples,"captures":captures,"limitations":["No FPS or 11v11 performance acceptance","No 016 touchplan integration","Boundary tests use separate initial fixtures","Cooperation checks do not prove a completed natural two-pass one-two"]}
	var file := FileAccess.open(evidence.path_join("training_native.json" if native else "training_headless.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print("TRAINING_RESULT ",report.passed,"/",checks.size()," failed=",failures.size())
	await process_frame
	quit(0 if failures.is_empty() else 1)
