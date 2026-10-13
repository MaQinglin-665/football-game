extends "res://tests/three_turn038_short.gd"
var post_samples:Array=[]
var reverse_samples:Array=[]
func start()->void:
	game=load("res://scenes/training_3v3.tscn").instantiate();game.test_mode=true;root.add_child(game);current_scene=game
	for i in 4:await process_frame
	game.hud.menu.get_node("StartMatch").pressed.emit()
	for i in 24:await physics_frame
	await reset_case("fast_90","B",Vector2(0,.28),true)
	set_keys([KEY_SHIFT,KEY_W]);await ticks(180)
	turn_marks.append({"case":case_name,"tick":case_tick,"speed":game.player.velocity.length(),"aim":pack(game.player.get_ball_direction())})
	set_keys([KEY_SHIFT,KEY_D])
	var touch_tick:int=-1
	# Follow the same actual movement until a real EXIT touch, then half a second.
	# This observer does not replace the original2s acceptance report.
	for i in 360:
		await ticks(1)
		var scheduler=game.player.foot.ordinary_scheduler
		post_samples.append(pack({"tick":case_tick-1,"turn_stage":scheduler.turn_stage,"turn_reason":scheduler.turn_reason,"foot_phase":game.player.foot.phase,"hit":game.player.foot.hit,"foot_kind":game.player.foot.kind,"foot_sequence":game.player.foot.sequence,"touch_plan":game.player.foot.touch_plan,"motor_target":game.player.shared_last_result.get("motion",Vector3.ZERO),"actor_velocity":game.player.velocity,"actor":game.player.position,"ball":game.ball.position,"owned":game.ball.carrier==game.player}))
		if touch_tick<0:
			for c in contacts:
				if c.event.success and c.event.action=="TURN" and c.plan.get("turn_stage","") in ["EXIT","CUT90"]:touch_tick=int(c.tick)
		if touch_tick>=0 and case_tick-1>=touch_tick+60:break
	# Same-input follow has completed. Change only the real keyboard input.
	set_keys([KEY_SHIFT,KEY_A])
	for i in 120:
		await ticks(1)
		var scheduler=game.player.foot.ordinary_scheduler
		reverse_samples.append(pack({"tick":case_tick-1,"stage":scheduler.turn_stage,"reason":scheduler.turn_reason,"accepted":scheduler._accepted_direction,"completed":scheduler._completed_turn_aim046,"velocity":game.player.velocity,"hit":game.player.foot.hit,"kind":game.player.foot.kind,"plan":game.player.foot.touch_plan}))
	set_keys([])
	check("actual lateral EXIT shoe contact",touch_tick>=0)
	var after:Array=post_samples.filter(func(r):return touch_tick>=0 and int(r.tick)>touch_tick)
	check("observe actual half-second after contact",after.size()>=60)
	check("no immediate BRAKE while successful EXIT shoe recovers",after.filter(func(r):return r.hit and r.touch_plan.get("turn_stage","")=="EXIT" and r.foot_phase!=0).all(func(r):return r.turn_stage!="BRAKE"))
	check("no same-input secondary BRAKE over half-second",not after.is_empty() and after.all(func(r):return r.turn_stage!="BRAKE"))
	check("physical actor follows exit direction after touch",not after.is_empty() and after.any(func(r):return r.actor_velocity[0]>.25))
	check("distinct reverse accepted through normal input debounce",reverse_samples.any(func(r):return r.accepted[0]<-.9))
	check("completed direction cleared for distinct reverse",reverse_samples.any(func(r):return r.accepted[0]<-.9 and Vector3(r.completed[0],r.completed[1],r.completed[2]).length_squared()<.01))
	check("distinct reverse can enter a new BRAKE transaction",reverse_samples.any(func(r):return r.stage=="BRAKE" and r.accepted[0]<-.9))
	var report:String=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):report=arg.trim_prefix("--output=")
	var ok:bool=checks.all(func(c):return c.passed)
	FileAccess.open(report,FileAccess.WRITE).store_string(JSON.stringify({"passed":ok,"checks":checks,"touch_tick":touch_tick,"input_tick":180,"original_two_second_window_passed":touch_tick>=180 and touch_tick<420,"post_samples":post_samples,"reverse_samples":reverse_samples,"rows":rows,"contacts":contacts,"reverse_scope":"After real EXIT and60same-input follow ticks, ShiftA120ticks; admission and intent reset only, not full reverse contact acceptance.","scope":"Single isolated production3v3 real ShiftW1.5s→ShiftD, same declared start as originalcase. Observe real EXIT contact and60physics ticks thereafter. Not replacement for original11checks2s acceptance, no contact success or motor writes after fixture."},"\t"))
	game.shutdown_audio();game.queue_free()
	for i in 4:await process_frame
	quit(0 if ok else 1)
