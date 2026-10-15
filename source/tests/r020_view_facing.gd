extends "res://tests/three_turn043_contact_completion.gd"
const Facing=preload("res://scripts/player_body_direction.gd")
func start()->void:
	for owned in [false,true]:
		for guard in [false,true]:
			for direction in [Vector3.LEFT,Vector3.RIGHT,Vector3.FORWARD,Vector3.BACK]:
				check("view target independent of keys and momentum",is_equal_approx(Facing.target(.7,direction,direction*5,owned,guard),.7))
	game=load("res://scenes/training_3v3.tscn").instantiate();game.test_mode=true;root.add_child(game);current_scene=game
	for i in 4:await process_frame
	await reset_case("free_side","B",Vector2(0,.28),true)
	game.ball.clear_control();game.ball.position=Vector3(8,game.ball.radius,8)
	set_keys([KEY_A]);await ticks(120)
	check("left movement keeps view facing",absf(angle_difference(game.player.rotation.y,game.player.hip_yaw))<.01)
	set_keys([KEY_D]);await ticks(120)
	check("right reversal keeps view facing",absf(angle_difference(game.player.rotation.y,game.player.hip_yaw))<.01)
	var old_yaw:float=game.player.hip_yaw
	game.player.head.mouse_axis=Vector2(-PI/2/game.player.head.mouse_sensitivity,0);game.player.head.camera_rotation()
	await ticks(1)
	check("view turn does not snap body",absf(angle_difference(old_yaw,game.player.hip_yaw))<.10)
	await ticks(100)
	check("body follows changed view",absf(angle_difference(game.player.rotation.y,game.player.hip_yaw))<.01)
	set_keys([])
	FileAccess.open(ProjectSettings.globalize_path("res://../verification/view.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"rows":rows}))
	game.shutdown_audio();game.queue_free()
	for i in 4:await process_frame
	quit(0 if checks.all(func(c):return c.passed) else 1)
