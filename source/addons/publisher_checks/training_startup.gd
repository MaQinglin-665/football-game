extends Node
## Explicit QA scene only. Normal training/11v11 entry has no added hook.
var game: Node3D
var checks: Array[Dictionary] = []
var captures: Array[String] = []
var evidence := ""

func _ready() -> void:
	if not "--training-startup-check" in OS.get_cmdline_user_args():
		queue_free()
		return
	game = get_parent() as Node3D
	game.test_mode = true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="): evidence = arg.trim_prefix("--evidence=")
	call_deferred("run")

func check(label: String, ok: bool) -> void:
	checks.append({"label": label, "passed": ok})
	print("PASS " if ok else "FAIL ", label)

func key(code: int) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = down
		Input.parse_input_event(e)
		Input.flush_buffered_events()

func capture(tag: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := evidence.path_join(tag + ".png")
	check("capture " + tag, get_viewport().get_texture().get_image().save_png(path) == OK)
	captures.append(path)

func run() -> void:
	if evidence.is_empty():
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(evidence)
	Engine.max_fps = 60 # Functional startup only, never FPS evidence.
	for i in 4: await get_tree().process_frame
	check("six actual actors blue3 yellow3", game.players.size() == 6 and game.players.filter(func(p): return p.team == 0).size() == 3 and game.players.filter(func(p): return p.team == 1).size() == 3)
	check("one fixed human and five agents", game.players.filter(func(p): return p.is_human).size() == 1 and game.agents.size() == 5 and game.player.jersey == 10)
	check("configured36x24 small pitch", is_equal_approx(game.field_half_length, 18) and is_equal_approx(game.field_half_width, 12))
	check("training mode and120Hz active", is_instance_valid(game.training_mode) and Engine.physics_ticks_per_second == 120)
	await capture("training_menu")
	game.hud.menu.get_node("StartMatch").pressed.emit()
	for i in 24: await get_tree().physics_frame
	check("actual training opening LIVE", game.services.rules.state == game.Rules.State.LIVE and game.phase == game.Phase.PLAY)
	var low: bool = game.training_mode.low_pressure
	key(KEY_F5)
	await get_tree().physics_frame
	check("F5 actual pressure toggles", game.training_mode.low_pressure != low)
	key(KEY_F6)
	await get_tree().physics_frame
	check("F6 actual defensive opening", game.training_mode.defensive_opening and is_instance_valid(game.ball.carrier) and game.ball.carrier.team == 1)
	var rep: int = game.training_mode.repetitions
	key(KEY_R)
	await get_tree().physics_frame
	check("R actual repetition reset", game.training_mode.repetitions == rep + 1)
	await capture("training_defensive_opening")
	var report := {"passed": checks.all(func(c): return c.passed), "checks": checks, "captures": captures, "roster": game.players.size(), "physics_hz": Engine.physics_ticks_per_second, "native": DisplayServer.get_name() != "headless", "scene": "res://scenes/training_3v3.tscn", "scope": "Exact exported EXE startup/six actor configuration/LIVE/F5/F6/R only. Synthesized input. No FPS/manual feel or repeat of author32 full tests."}
	FileAccess.open(evidence.path_join("TRAINING_EXE_STARTUP.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t") + "\n")
	print("TRAINING_EXE_STARTUP_DONE valid=", report.passed, " checks=", checks.size())
	reparent(get_tree().root) # Keep only the QA runner alive during normal scene cleanup.
	game.pause_match()
	game.shutdown_audio()
	game.queue_free()
	game = null
	for i in 4: await get_tree().process_frame
	get_tree().quit(0 if report.passed else 1)
