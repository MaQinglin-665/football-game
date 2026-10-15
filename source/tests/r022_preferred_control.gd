extends "res://tests/three_turn043_contact_completion.gd"
func start()->void:
	game=load("res://scenes/training_3v3.tscn").instantiate();game.test_mode=true;root.add_child(game);current_scene=game
	for i in 4:await process_frame
	for spec in [{"name":"left","key":KEY_A,"offset":Vector2(0,.28)},{"name":"right","key":KEY_D,"offset":Vector2(0,.28)},{"name":"left_far","key":KEY_A,"offset":Vector2(-.48,.28)},{"name":"left_foot_right","key":KEY_D,"offset":Vector2(0,.28),"dominant":-1}]:
		await reset_case(spec.name,"B",spec.offset,true)
		game.player.set_meta("dominant_foot_side",spec.get("dominant",1))
		var dx:float=-game.player.position.x
		game.player.position.x+=dx;game.ball.position.x+=dx
		game.player.avatar._plants.clear();game.player.avatar.invalidate_pose_snapshot()
		set_keys([spec.key]);await ticks(360)
		var sample:Array=rows.filter(func(r):return r.case==case_name)
		var actual:Array=contacts.filter(func(c):return c.case==case_name and c.event.success)
		check(case_name+" retains control",sample.all(func(r):return r.owned))
		check(case_name+" has repeated real touches",actual.size()>=6)
		check(case_name+" no failed actions",contacts.filter(func(c):return c.case==case_name).all(func(c):return c.event.success))
		check(case_name+" body stays facing view",sample.all(func(r):return float(r.body_facing[2])<-.999))
		var sum_speed:float=0
		for row in sample.slice(120):sum_speed+=absf(float(row.actor_velocity[0]))
		check(case_name+" sustained slow-control pace",sum_speed/240>1.2)
		if spec.name=="left":check("right inside preferred for central left move",actual.filter(func(c):return c.side==1 and c.surface=="INSIDE").size()>actual.size()/2)
		if spec.name=="right":check("right outside preferred for right move",not actual.is_empty() and actual[0].side==1 and actual[0].surface=="OUTSIDE")
		if spec.name=="left_far":check("far left ball uses reachable left shoe",not actual.is_empty() and actual[0].side==-1)
		if spec.name=="left_foot_right":check("left foot preference mirrors inside touch",not actual.is_empty() and actual[0].side==-1 and actual[0].surface=="INSIDE")
	set_keys([])
	check("single impulse per actual contact",unique_contacts())
	FileAccess.open(ProjectSettings.globalize_path("res://../verification/preferred.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"rows":rows,"contacts":contacts}))
	game.shutdown_audio();game.queue_free()
	for i in 4:await process_frame
	quit(0 if checks.all(func(c):return c.passed) else 1)
