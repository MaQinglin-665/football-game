extends "res://tests/three_turn043_contact_completion.gd"
func start()->void:
	evidence=ProjectSettings.globalize_path("res://../verification")
	game=load("res://scenes/training_3v3.tscn").instantiate();game.test_mode=true;root.add_child(game);current_scene=game
	for i in 4:await process_frame
	for label in ["ball_sprint","free_sprint"]:
		await reset_case(label,"B",Vector2(0,.28),true)
		game.player.position.x=0;game.ball.position.x=0
		game.player.avatar._plants.clear();game.player.avatar.invalidate_pose_snapshot()
		if label=="free_sprint":
			game.ball.clear_control();game.ball.position=Vector3(8,game.ball.radius,8);game.ball.velocity=Vector3.ZERO
		set_keys([KEY_W,KEY_SHIFT]);await ticks(360)
	set_keys([])
	var path:String=evidence.path_join("speed.json")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):path=arg.trim_prefix("--output=")
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify({"rows":rows,"contacts":contacts}))
	game.shutdown_audio();game.queue_free()
	for i in 4:await process_frame
	quit()
