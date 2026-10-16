extends "res://tests/three_turn043_contact_completion.gd"
func start()->void:
	evidence=ProjectSettings.globalize_path("res://../verification")
	game=load("res://scenes/training_3v3.tscn").instantiate();game.test_mode=true;root.add_child(game);current_scene=game
	for i in 4:await process_frame
	for spec in [{"name":"left_right","first":[KEY_A],"next":[KEY_D]},{"name":"forward_back","first":[KEY_W,KEY_SHIFT],"next":[KEY_S]},{"name":"fake_cut_run","first":[KEY_W,KEY_SHIFT],"next":[KEY_D]}]:
		await reset_case(spec.name,"B",Vector2(0,.28),true)
		var dx:float=-game.player.position.x
		game.player.position.x+=dx;game.ball.position.x+=dx
		game.player.avatar._plants.clear();game.player.avatar.invalidate_pose_snapshot()
		set_keys(spec.first);await ticks(160)
		# Observe a genuine completed touch, then enter the next command during follow.
		var count:int=contacts.size()
		for i in 90:
			await ticks(1)
			if contacts.size()>count and not game.player.foot.ordinary_scheduler.follow_step.pending.is_empty():break
		if spec.name=="forward_back":
			var a=game.player
			var follow=a.foot.ordinary_scheduler.follow_step
			var saved:Dictionary=a.foot.buffer.duplicate(true)
			var unqueued:Dictionary=follow.follow_motion(a,game.ball,Vector3.BACK,5)
			a.foot.buffer={"kind":"CUT"}
			var queued:Dictionary=follow.follow_motion(a,game.ball,Vector3.BACK,5)
			check("queued next action preserves same body follow",not unqueued.is_empty() and not queued.is_empty() and (unqueued.motion as Vector3).distance_to(queued.motion)<.00001)
			a.foot.buffer=saved
			var old_move:Vector3=a.move_intent
			a.move_intent=-a.velocity.normalized()
			var predicted:Vector3=a.foot.ordinary_scheduler.playable_root_delta(a,a.velocity,.12)
			check("touch forecast includes actual braking",predicted.dot(a.velocity.normalized())<(a.velocity*.12).length()-.015)
			a.move_intent=old_move
		var mark:int=case_tick
		set_keys(spec.next)
		if spec.name=="fake_cut_run":
			mouse(MOUSE_BUTTON_LEFT,true);mouse(MOUSE_BUTTON_RIGHT,true);mouse(MOUSE_BUTTON_LEFT,false);mouse(MOUSE_BUTTON_RIGHT,false)
			var follow=game.player.foot.ordinary_scheduler.follow_step
			if game.player.foot.has_buffer():check("queued cut keeps physical follow",not follow.follow_motion(game.player,game.ball,Vector3.RIGHT,5).is_empty())
		await ticks(240)
		var sample:Array=rows.filter(func(r):return r.case==case_name and r.tick>mark)
		check(case_name+" retains possession",sample.all(func(r):return r.owned))
		var end:Dictionary=sample[-1]
		check(case_name+" responds in new direction",float(end.actor_velocity[2])>.3 if spec.name=="forward_back" else float(end.actor_velocity[0])>.3)
		check(case_name+" next real contact",contacts.any(func(c):return c.case==case_name and c.tick>mark and c.event.success))
	set_keys([])
	check("one impulse per action",unique_contacts())
	var report:String="chain.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report=arg.trim_prefix("--report=")
	FileAccess.open(evidence.path_join(report),FileAccess.WRITE).store_string(JSON.stringify({"rows":rows,"contacts":contacts,"checks":checks}))
	game.shutdown_audio();game.queue_free()
	for i in 4:await process_frame
	quit(0 if checks.all(func(c):return c.passed) else 1)
func mouse(button:int,pressed:bool)->void:
	var e:=InputEventMouseButton.new();e.button_index=button;e.pressed=pressed;Input.parse_input_event(e);Input.flush_buffered_events()
