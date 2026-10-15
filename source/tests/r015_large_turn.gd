extends "res://tests/three_turn043_contact_completion.gd"
var follow_samples:int=0
var changed_motion:int=0
func ticks(count:int)->void:
	for i in count:
		await super.ticks(1)
		var a=game.player
		var follow=a.foot.ordinary_scheduler.follow_step
		if not follow.pending.is_empty():
			var first:Dictionary=follow.follow_motion(a,game.ball,Vector3.FORWARD,5.0)
			var second:Dictionary=follow.follow_motion(a,game.ball,Vector3.RIGHT,5.0)
			if not first.is_empty() and not second.is_empty():
				follow_samples+=1
				if (first.motion as Vector3).distance_to(second.motion)>.00001:changed_motion+=1
func start()->void:
	evidence=ProjectSettings.globalize_path("res://../verification")
	game=load("res://scenes/training_3v3.tscn").instantiate();game.test_mode=true;root.add_child(game);current_scene=game
	for i in 4:await process_frame
	for spec in [{"name":"W_S","gap":0,"next":[KEY_S],"yaw":0.0},{"name":"W_release_S","gap":8,"next":[KEY_S],"yaw":0.0},{"name":"camera180","gap":0,"next":[KEY_W],"yaw":PI}]:
		await reset_case(spec.name,"B",Vector2(0,.28),true)
		var dx:float=-game.player.position.x
		game.player.position.x+=dx;game.ball.position.x+=dx
		game.player.avatar._plants.clear();game.player.avatar.invalidate_pose_snapshot()
		set_keys([KEY_W,KEY_SHIFT]);await ticks(180);set_keys([KEY_W])
		var count:int=contacts.size()
		for i in 90:
			await ticks(1)
			if contacts.size()>count and contacts[-1].event.success:break
		turn_marks.append({"case":case_name,"tick":case_tick})
		if spec.yaw!=0:
			game.player.head.mouse_axis=Vector2(-spec.yaw/game.player.head.mouse_sensitivity,0);game.player.head.camera_rotation()
		set_keys([])
		if spec.gap>0:await ticks(spec.gap)
		set_keys(spec.next);await ticks(240)
		var sample:Array=rows.filter(func(r):return r.case==case_name)
		check(case_name+" control maintained",sample.all(func(r):return r.owned))
		check(case_name+" exits backward",sample[-1].actor_velocity[2]>.3)
	set_keys([])
	check("committed follow ignores next-input direction",follow_samples>20 and changed_motion==0)
	check("single ordinary impulse",unique_contacts())
	FileAccess.open(evidence.path_join("r015-natural-input.json"),FileAccess.WRITE).store_string(JSON.stringify({"rows":rows,"contacts":contacts,"marks":turn_marks,"checks":checks,"follow_samples":follow_samples,"changed_motion":changed_motion}))
	game.shutdown_audio();game.queue_free()
	for i in 4:await process_frame
	quit(0 if checks.all(func(c):return c.passed) else 1)
