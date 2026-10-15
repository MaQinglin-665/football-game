extends "res://tests/three_turn043_contact_completion.gd"
func start()->void:
	evidence=ProjectSettings.globalize_path("res://../verification")
	game=load("res://scenes/training_3v3.tscn").instantiate();game.test_mode=true;root.add_child(game);current_scene=game
	for i in 4:await process_frame
	for spec in [{"name":"release_gap3","run":true,"next":[KEY_S],"yaw":0.0,"gap":3},{"name":"release_gap8","run":true,"next":[KEY_S],"yaw":0.0,"gap":8},{"name":"release_gap15","run":true,"next":[KEY_S],"yaw":0.0,"gap":15}]:
		await reset_case(spec.name,"B",Vector2(0,.28),true)
		var dx:float=-game.player.position.x
		game.player.position.x+=dx;game.ball.position.x+=dx
		game.player.avatar._plants.clear();game.player.avatar.invalidate_pose_snapshot()
		set_keys([KEY_W,KEY_SHIFT] if spec.run else [KEY_W]);await ticks(260)
		turn_marks.append({"case":case_name,"tick":case_tick})
		if spec.yaw!=0:
			game.player.head.mouse_axis=Vector2(-spec.yaw/game.player.head.mouse_sensitivity,0);game.player.head.camera_rotation()
		set_keys([]);await ticks(spec.gap)
		game.player.foot.cancel()
		game.ball.touch_timer=0.0;game.ball.dribble_free_roll_remaining=0.0
		game.ball.position=game.player.position+Vector3(0,game.ball.radius+.001,-.80)
		game.ball.position.y=game.ball.radius+.001
		game.ball.velocity=Vector3(0,0,-5.8)
		game.player.velocity=Vector3(0,0,-4.8)
		set_keys(spec.next);await ticks(240)
	set_keys([])
	var out:String=evidence.path_join("large-turn.json")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):out=arg.trim_prefix("--output=")
	FileAccess.open(out,FileAccess.WRITE).store_string(JSON.stringify({"marks":turn_marks,"rows":rows,"contacts":contacts}))
	game.shutdown_audio();game.queue_free()
	for i in 4:await process_frame
	quit()






