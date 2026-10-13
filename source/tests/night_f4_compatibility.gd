extends SceneTree
var checks: Array[Dictionary] = []
func _initialize() -> void:call_deferred("run")
func check(label: String, ok: bool) -> void:
	checks.append({"check":label,"passed":ok})
	print("PASS " if ok else "FAIL ",label)
func press_f4() -> void:
	for down in [true,false]:
		var key := InputEventKey.new()
		key.physical_keycode=KEY_F4;key.keycode=KEY_F4;key.pressed=down
		Input.parse_input_event(key);Input.flush_buffered_events()
func run() -> void:
	AudioServer.set_bus_mute(0,true)
	var game: Node3D = load("res://scenes/match.tscn").instantiate()
	game.test_mode=true;root.add_child(game)
	game.set_process(false);game.set_physics_process(false);game.physics_world.set_physics_process(false)
	for actor in game.players:actor.set_physics_process(false)
	var world: WorldEnvironment = game.get_node("MatchEnvironment")
	var main: DirectionalLight3D = game.get_node("MatchSun")
	var rig: Node3D = game.stadium.get_node("NightFixtureRig")
	var far: Dictionary = game.stadium.get_meta("far_clarity_report").duplicate(true)
	var ball_state := [game.ball.position,game.ball.velocity,game.ball.carrier,game.player.foot.sequence]
	var rules: Dictionary = game.services.rules.snapshot().duplicate(true)
	check("0.6.12 default selects night low",world.get_meta("stadium_lighting_mode","")=="night" and world.get_meta("stadium_night_quality","")=="low")
	check("new far geometry inherited unchanged",far.new_proxy_triangles==5760 and far.changed_proxies==72 and game.stadium.get_meta("far_clarity_enabled",false))
	check("current FP arms and original three-tier player inherited",game.player.avatar.get_script().resource_path=="res://scripts/integration_character_pose.gd" and game.player.avatar.get_script().get_base_script().resource_path=="res://addons/football_motion/fp_visibility_03.gd" and game.player.foot.get_script().resource_path=="res://scripts/foot_action.gd")
	press_f4()
	check("real F4 edge selects daylight",world.get_meta("stadium_lighting_mode","")=="daylight")
	check("F4 hides night rig and restores main mask",not rig.visible and main.light_cull_mask!=(1<<19))
	check("daylight keeps original low AA and LOD",root.msaa_3d==0 and game.stadium.seat_lod_near_distance==55.0 and game.stadium.seat_lod_mid_distance==80.0)
	press_f4()
	check("second real F4 edge selects night",world.get_meta("stadium_lighting_mode","")=="night" and rig.visible)
	check("default low does not create optional spot",game.find_children("*","Light3D",true,false).size()==1 and rig.bank_positions.size()==8)
	check("F4 restores layer20 and night shadow distance60",main.light_cull_mask==(1<<19) and main.directional_shadow_max_distance==60.0)
	check("F4 leaves far proxy objects and report unchanged",game.stadium.get_meta("far_clarity_report")==far and game.stadium.get_meta("far_clarity_enabled",false))
	check("F4 leaves ball/contact/rules state unchanged",[game.ball.position,game.ball.velocity,game.ball.carrier,game.player.foot.sequence]==ball_state and game.services.rules.snapshot()==rules)
	check("22bodies physics120 and ordinary input focus policy retained",game.players.size()==22 and Engine.physics_ticks_per_second==120)
	var report := {"passed":checks.all(func(c):return c.passed),"total":checks.size(),"checks":checks,"scope":"Headless actual F4 InputEventKey edges, current0.6.11 far/arms/foot compatibility and state preservation. Does not prove three native views/readability or FPS."}
	FileAccess.open(ProjectSettings.globalize_path("res://../verification/F4_COMPATIBILITY_HEADLESS_RECHECK.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	game.shutdown_audio();game.queue_free()
	await process_frame;await process_frame
	quit(0 if report.passed else 1)
