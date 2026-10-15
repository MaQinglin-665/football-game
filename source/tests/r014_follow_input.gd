extends "res://tests/three_turn043_contact_completion.gd"
func start()->void:
	evidence=ProjectSettings.globalize_path("res://../verification")
	game=load("res://scenes/training_3v3.tscn").instantiate();game.test_mode=true;root.add_child(game);current_scene=game
	for i in 4:await process_frame
	for label in ["camera_cut","release_collect","camera_collect","feint"]:
		await reset_case(label,"B",Vector2(0,.28),true)
		var dx:float=-game.player.position.x
		game.player.position.x+=dx;game.ball.position.x+=dx
		game.player.avatar._plants.clear();game.player.avatar.invalidate_pose_snapshot()
		set_keys([KEY_W,KEY_SHIFT]);await ticks(180);set_keys([KEY_W])
		var count:int=contacts.size()
		for i in 90:
			await ticks(1)
			if contacts.size()>count and contacts[-1].event.success:break
		turn_marks.append({"case":label,"tick":case_tick,"speed":game.player.velocity.length(),"ball_speed":game.ball.velocity.length()})
		if label in ["camera_cut","camera_collect","feint"]:
			game.player.head.mouse_axis=Vector2(-PI/game.player.head.mouse_sensitivity,0);game.player.head.camera_rotation()
		if label in ["release_collect","camera_collect"]:
			set_keys([KEY_W,KEY_SHIFT]);await ticks(1);set_keys([KEY_W])
		if label=="feint":
			await ticks(5)
			game.player.head.mouse_axis=Vector2(PI/game.player.head.mouse_sensitivity,0);game.player.head.camera_rotation()
		await ticks(180)
	set_keys([])
	check("single actual impulse per ordinary sequence",unique_contacts())
	for label in ["camera_cut","release_collect","camera_collect","feint"]:
		check(label+" retains actual control",rows.filter(func(r):return r.case==label).all(func(r):return r.owned))
	for label in ["release_collect","camera_collect"]:
		check(label+" real sole collection",contacts.any(func(c):return c.case==label and c.event.success and c.surface=="SOLE" and c.plan.get("follow_collect",false)))
	check("sprint change real inside cut",contacts.any(func(c):return c.case=="camera_cut" and c.event.success and c.surface=="INSIDE" and c.plan.get("follow_cut",false)))
	var out:String=evidence.path_join("follow-input.json")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):out=arg.trim_prefix("--output=")
	FileAccess.open(out,FileAccess.WRITE).store_string(JSON.stringify({"marks":turn_marks,"rows":rows,"contacts":contacts,"checks":checks}))
	game.shutdown_audio();game.queue_free()
	for i in 4:await process_frame
	quit(0 if checks.all(func(c):return c.passed) else 1)
