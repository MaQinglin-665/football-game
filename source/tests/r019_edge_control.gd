extends "res://tests/three_turn043_contact_completion.gd"
func start()->void:
	game=load("res://scenes/training_3v3.tscn").instantiate();game.test_mode=true;root.add_child(game);current_scene=game
	for i in 4:await process_frame
	for sign_side in [-1,1]:
		await reset_case("edge_"+str(sign_side),"B",Vector2(sign_side*.72,.20),true)
		var shift:float=-game.player.position.x
		game.player.position.x+=shift;game.ball.position.x+=shift
		game.player.avatar._plants.clear();game.player.avatar.invalidate_pose_snapshot()
		game.ball.velocity=Vector3(sign_side*.28,0,0)
		set_keys([KEY_D] if sign_side<0 else [KEY_A])
		await ticks(180)
		var actual:Array=contacts.filter(func(c):return c.case==case_name and c.event.success)
		check(case_name+" actual foot returns ball",not actual.is_empty() and float(actual[0].event.after_velocity[0])*sign_side<-.25)
		check(case_name+" no failed extension",contacts.filter(func(c):return c.case==case_name).all(func(c):return c.event.success))
		check(case_name+" body closes gap before touch",not actual.is_empty() and absf(float(actual[0].actor[0]))>.20)
		check(case_name+" keeps control",rows.filter(func(r):return r.case==case_name).all(func(r):return r.owned))
	set_keys([])
	check("one impulse per touch",unique_contacts())
	game.player.foot.cancel()
	game.ball.position=game.player.position+Vector3(1.3,game.ball.radius,0);game.ball.velocity=Vector3.ZERO
	check("outside control range does not auto recover",game.player.foot.ordinary_scheduler.follow_step.follow_motion(game.player,game.ball,Vector3.LEFT,3.2).is_empty())
	game.ball.clear_control()
	check("free ball does not auto recover",game.player.foot.ordinary_scheduler.follow_step.follow_motion(game.player,game.ball,Vector3.LEFT,3.2).is_empty())
	FileAccess.open(ProjectSettings.globalize_path("res://../verification/edge.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"rows":rows,"contacts":contacts}))
	game.shutdown_audio();game.queue_free()
	for i in 4:await process_frame
	quit(0 if checks.all(func(c):return c.passed) else 1)
