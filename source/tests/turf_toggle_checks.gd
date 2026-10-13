extends SceneTree
var game: Node
var checks: Array[Dictionary] = []
var evidence := ""
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="): evidence = arg.trim_prefix("--evidence=")
	call_deferred("run")
func check(label: String, ok: bool) -> void:
	checks.append({"label":label,"passed":ok})
	print("PASS " if ok else "FAIL ", label)
func key(code: int) -> void:
	for down in [true,false]:
		var event := InputEventKey.new()
		event.keycode=code; event.physical_keycode=code; event.pressed=down
		Input.parse_input_event(event); Input.flush_buffered_events()
func state() -> Array:
	return [game.ball.position,game.ball.velocity,game.ball.spin_rads,game.ball.carrier,game.player.foot.sequence,game.phase]
func run() -> void:
	DirAccess.make_dir_recursive_absolute(evidence)
	game=load("res://scenes/training_3v3.tscn").instantiate(); game.test_mode=true; root.add_child(game)
	for i in 4: await process_frame
	var toggle: Node=game.get_node("TurfRollAB")
	check("default B sharedprofile",toggle.mode=="B" and game.physics_profile.low_speed_roll_extra_mps2==.75 and game.ball.profile==game.physics_world.profile and game.players.all(func(a):return a.profile==game.physics_profile))
	var before:=state(); key(KEY_F7)
	check("F7 selects originalA without ballstate writes",toggle.mode=="A" and game.physics_profile.low_speed_roll_extra_mps2==0 and state()==before)
	key(KEY_F7)
	check("F7 returnsB without ballstate writes",toggle.mode=="B" and game.physics_profile.low_speed_roll_extra_mps2==.75 and state()==before)
	game.hud.menu.get_node("StartMatch").pressed.emit()
	for i in 24: await physics_frame
	check("six real actors andLIVE unchanged",game.players.size()==6 and game.agents.size()==5 and game.services.rules.is_ball_live())
	key(KEY_R); await physics_frame
	check("R preserves selectedB",toggle.mode=="B" and game.physics_profile.low_speed_roll_extra_mps2==.75)
	key(KEY_F7); key(KEY_R); await physics_frame
	check("live F7 andR preserves selectedA",toggle.mode=="A" and game.physics_profile.low_speed_roll_extra_mps2==0)
	var passed:=checks.all(func(c):return c.passed)
	FileAccess.open(evidence.path_join("TURF_TOGGLE_CHECKS.json"),FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"checks":checks,"scope":"Actual3v3 sharedprofile F7/R input, no force/position/velocity/ownership changes in toggler; not manual/performance."},"\t"))
	print("TURF_TOGGLE_DONE valid=",passed)
	game.pause_match();game.shutdown_audio();game.queue_free();game=null
	for i in 4: await process_frame
	quit(0 if passed else 1)
