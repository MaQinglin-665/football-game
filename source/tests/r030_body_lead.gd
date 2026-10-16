extends "res://tests/three_turn043_contact_completion.gd"
func start()->void:
	evidence=ProjectSettings.globalize_path("res://../verification")
	game=load("res://scenes/training_3v3.tscn").instantiate();game.test_mode=true;root.add_child(game);current_scene=game
	for i in 4:await process_frame
	for spec in [{"name":"walk_forward","keys":[KEY_W],"axis":Vector3.FORWARD},{"name":"walk_left","keys":[KEY_A],"axis":Vector3.LEFT},{"name":"walk_right","keys":[KEY_D],"axis":Vector3.RIGHT},{"name":"close_left","keys":[KEY_CTRL,KEY_A],"axis":Vector3.LEFT}]:
		await reset_case(spec.name,"B",Vector2(0,.28),true)
		var origin:Vector3=game.player.position
		set_keys(spec.keys);await ticks(240)
		var events:Array=contacts.filter(func(c):return c.case==case_name and c.event.success)
		var sample:Array=rows.filter(func(r):return r.case==case_name)
		var advance:float=0
		if not events.is_empty():advance=(Vector3(events[0].actor[0],events[0].actor[1],events[0].actor[2])-origin).dot(spec.axis)
		var pace:float=0
		for row in sample.slice(-60):pace+=Vector3(row.actor_velocity[0],0,row.actor_velocity[2]).dot(spec.axis)/60.0
		check(case_name+" body moves before first touch",advance>=.02)
		check(case_name+" sustained useful pace",pace>1.25)
		check(case_name+" keeps ball",sample.all(func(r):return r.owned))
		print("BODY_LEAD ",case_name," first_advance=",advance," pace=",pace)
		check(case_name+" supported pelvis transfer is applied",sample.any(func(r):return r.get("body_debug",{}).get("control_phase",{}).get("body_led_near",false) and r.get("body_debug",{}).get("control_phase",{}).get("bone_writes",false)))
		if spec.name=="walk_forward":
			set_keys([KEY_W,KEY_A]);await ticks(120)
			set_keys([KEY_A]);await ticks(120)
			var turning:Array=rows.filter(func(r):return r.case==case_name and r.tick>240)
			check("walking diagonal then left keeps real ball control",turning.all(func(r):return r.owned) and float(turning[-1].actor_velocity[0])<-.5)

	set_keys([])
	check("single touch impulse",unique_contacts())
	var file:String="body-lead.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):file=arg.trim_prefix("--report=")
	FileAccess.open(evidence.path_join(file),FileAccess.WRITE).store_string(JSON.stringify({"rows":rows,"contacts":contacts,"checks":checks}))
	game.shutdown_audio();game.queue_free()
	for i in 4:await process_frame
	quit(0 if checks.all(func(c):return c.passed) else 1)
