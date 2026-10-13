extends "res://tests/integration_checks.gd"
var rows:Array=[]
var eleven:=false
func run()->void:
	for arg in OS.get_cmdline_user_args():
		if arg=="--eleven":eleven=true
	seed(81008)
	game=load("res://scenes/match.tscn" if eleven else "res://scenes/training_3v3.tscn").instantiate()
	game.test_mode=true;root.add_child(game);current_scene=game
	root.mode=Window.MODE_WINDOWED;root.size=Vector2i(1280,720)
	game.settings_menu.values.volume=0;game.settings_menu.values.lighting=0;game.settings_menu.apply_values(false)
	game.start_match(false);await ticks(8)
	# Declared visual fixture: isolate sprint/view movement, no forced contacts.
	game.tactics_bridge.set_physics_process(false)
	game.services.rules.state=game.Rules.State.LIVE;game._sync_rule_phase()
	for actor in game.players:
		actor.foot.cancel("visual fixture");actor.velocity=Vector3.ZERO;actor.set_move_intent(Vector3.ZERO)
		if actor!=game.player:
			actor.set_physics_process(false);actor.position=Vector3(10+actor.team,0,10)
	var p=game.player
	p.position=Vector3(0,.002,8);p.reset_view(0);p.camera_bob_enabled=true
	game.ball.reset(Vector3(7,.111,0));game.ball.clear_control();game.ball.set_held(false)
	await ticks(40)
	key(KEY_W,true);key(KEY_SHIFT,true)
	await ticks(190)
	await shot("sprint_60",-60)
	await shot("sprint_85",-85)
	key(KEY_W,false);key(KEY_SHIFT,false);await ticks(100)
	await shot("idle_85",-85)
	p.camera_bob_enabled=false
	key(KEY_W,true);key(KEY_SHIFT,true);await ticks(150)
	await shot("bob_off_65",-65)
	key(KEY_W,false);key(KEY_SHIFT,false)
	FileAccess.open(evidence.path_join("sprint_look_down.json"),FileAccess.WRITE).store_string(JSON.stringify({"eleven":eleven,"rows":rows,"scope":"native isolated actual W/Shift input and existing view input; other actors parked; screenshots not FPS measurement"},"  "))
	game.quit_game()
func shot(label:String,pitch:float)->void:
	var p=game.player
	p.head.mouse_axis=Vector2(0,(p.head.rot.x-deg_to_rad(pitch))/p.head.mouse_sensitivity);p.head.camera_rotation()
	await ticks(18)
	var sk:Skeleton3D=p.avatar.skeleton
	var chest:Vector3=sk.to_global(sk.get_bone_global_pose(sk.find_bone("chest")).origin)
	rows.append({"case":label,"pitch":pitch,"velocity":p.velocity,"eye":p.camera.global_position-p.position,"physical_eye":p.head.global_position-p.position,"chest":chest-p.position,"body_cut":p._fp_cut_previous})
	await capture(label)
