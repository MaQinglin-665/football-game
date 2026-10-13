extends SceneTree
## Publisher-only short wiring/3v3 isolation and two-GK activity-budget check.
var checks: Array[Dictionary] = []
var evidence := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="): evidence = arg.trim_prefix("--evidence=")
	call_deferred("run")

func check(label: String, ok: bool) -> void:
	checks.append({"label":label,"passed":ok})
	print("PASS " if ok else "FAIL ",label)

func run() -> void:
	if evidence.is_empty(): quit(2); return
	AudioServer.set_bus_mute(0,true)
	var training: Node3D = load("res://scenes/training_3v3.tscn").instantiate()
	training.test_mode = true
	root.add_child(training)
	await physics_frame
	check("3v3 has six outfield and no keeper host",training.players.size()==6 and not training.has_node("KeeperActions04") and training.players.filter(func(a):return a.is_goalkeeper).is_empty())
	check("3v3 uses original ball and avatar implementation",training.ball.get_script().resource_path=="res://scripts/football.gd" and training.agents.all(func(a):return not a.avatar.has_method("keeper_sample_action")))
	training.shutdown_audio()
	training.queue_free()
	await process_frame
	var game: Node3D = load("res://scenes/match.tscn").instantiate()
	game.test_mode = true
	root.add_child(game)
	await physics_frame
	var host: Node = game.get_node("KeeperActions04")
	check("only two roster keepers instantiate arm layer",host.states.size()==2 and game.players.filter(func(a):return a.avatar.has_method("keeper_sample_action")).size()==2)
	for state: Dictionary in host.keeper_states:
		var a: Node3D = state.actor
		check("GK gloves bind original rig: team%d" % a.team,bool(a.avatar.keeper_pose_debug().bound) and a.avatar.keeper_hand_geometry().get("hands",{}).size()==2)
	game.start_match(false)
	game.set_phase(game.Phase.PLAY)
	game.services.rules._second_touch_actor = -1
	game.services.rules._become_live()
	game.ball.reset(Vector3(0,.13,0))
	game.ball.set_held(false)
	var before_samples: int = host.arm_sample_count
	var before_sweeps: int = host.sweep_query_count
	var first_frame: int = Engine.get_physics_frames()
	# Natural AI enabled; keep ball far from either GK to measure READY budget.
	for i in 60: await physics_frame
	var elapsed_frames: int = Engine.get_physics_frames()-first_frame
	check("far-ball READY samples at most once per GK per frame",host.arm_sample_count-before_samples<=2*(elapsed_frames+1))
	check("far ball does not run hand collision sweeps",host.sweep_query_count==before_sweeps)
	check("current keeper AI intent remains live",host.keeper_states.all(func(s):return not s.actor.tactical_intent.is_empty() and s.actor.is_goalkeeper))
	var passed := checks.all(func(row):return row.passed)
	DirAccess.make_dir_recursive_absolute(evidence)
	FileAccess.open(evidence.path_join("KEEPER_038_ISOLATION.json"),FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"checks":checks,"scope":"Short production wiring/budget counters. Not frame-time/FPS benchmark."},"\t"))
	game.pause_match()
	game.shutdown_audio()
	game.queue_free()
	await process_frame
	quit(0 if passed else 1)
