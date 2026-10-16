extends "res://tests/three_turn043_contact_completion.gd"
func start()->void:
	evidence=ProjectSettings.globalize_path("res://../verification")
	game=load("res://scenes/training_3v3.tscn").instantiate();game.test_mode=true;root.add_child(game);current_scene=game
	for i in 4:await process_frame
	for mode in ["jog","run","right_first"]:
		var sprint:bool=mode!="jog"
		await reset_case("rapid_"+mode,"B",Vector2(0,.28),true)
		var shift:float=-game.player.position.x
		game.player.position.x+=shift;game.ball.position.x+=shift
		set_keys([KEY_D,KEY_SHIFT] if mode=="right_first" else [KEY_W,KEY_SHIFT] if sprint else [KEY_W]);await ticks(180)
		set_keys([KEY_D] if mode=="right_first" else [KEY_W]);var mark:int=case_tick
		for i in 6:
			set_keys([KEY_D] if i%2==0 and mode!="right_first" or i%2==1 and mode=="right_first" else [KEY_A]);await ticks(12)
		set_keys([KEY_A]);await ticks(240)
		var sample:Array=rows.filter(func(r):return r.case==case_name and r.tick>mark)
		check(case_name+" remains controlled",sample.all(func(r):return r.owned))
		check(case_name+" final left input executed",float(sample[-1].actor_velocity[0])<-.3)
		check(case_name+" actual contacts after switching",contacts.any(func(c):return c.case==case_name and c.tick>mark and c.event.success))
	set_keys([])
	check("single impulse",unique_contacts())
	var file:String="rapid.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):file=arg.trim_prefix("--report=")
	FileAccess.open(evidence.path_join(file),FileAccess.WRITE).store_string(JSON.stringify({"rows":rows,"contacts":contacts,"checks":checks}))
	game.shutdown_audio();game.queue_free()
	for i in 4:await process_frame
	quit(0 if checks.all(func(c):return c.passed) else 1)
