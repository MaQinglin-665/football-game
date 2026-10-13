extends "res://tests/integration_checks.gd"
var rows:Array=[]
var steps:Array=[]
var stage_name:String=""
var transitions:Array=[]
var request_id:=0
func sample_motion(n:int)->void:
	for i in n:
		await physics_frame
		var p=game.player
		rows.append({"stage":stage_name,"frame":Engine.get_physics_frames(),"velocity":p.velocity,"debug":p.avatar.get_full_body_debug(),"left":p.avatar.get_foot_contact(-1,"SOLE").point,"right":p.avatar.get_foot_contact(1,"SOLE").point,"camera_basis":p.camera.global_basis,"visual_basis":p.avatar.visual.global_basis,"action":p.foot.kind,"phase":p.foot.phase})
func run()->void:
	seed(3902);game=load("res://scenes/training_3v3.tscn").instantiate();game.test_mode=true;root.add_child(game)
	await ticks(6);game.hud.menu.get_node("StartMatch").pressed.emit();await ticks(8);game.tactics_bridge.set_physics_process(false)
	for a in game.agents:
		a.set_physics_process(false);a.foot.cancel("fixture");a.set_move_intent(Vector3.ZERO);a.velocity=Vector3.ZERO;a.position=Vector3(9+a.team,.002,10+a.jersey*.01)
	release_inputs();game.player.position=Vector3(0,.002,5);game.player.velocity=Vector3.ZERO;game.player.reset_view(0);game.player.foot.cancel("fixture")
	game.ball.clear_control();game.ball.set_held(false);game.ball.reset(Vector3(-9,.12,-9))
	game.player.avatar.ground_step.connect(func(e):steps.append({"stage":stage_name,"frame":Engine.get_physics_frames(),"event":e}))
	if game.player.avatar.has_signal("locomotion_transition"):
		game.player.avatar.locomotion_transition.connect(func(e):
			if e.event=="REQUEST":request_id+=1
			transitions.append({"stage":stage_name,"request_id":request_id,"frame":Engine.get_physics_frames(),"speed":game.player.velocity.length(),"event":e.duplicate(true)}))
	for c in [{"name":"free_run","keys":[KEY_SHIFT,KEY_W],"ticks":240},{"name":"cut90","keys":[KEY_SHIFT,KEY_A],"ticks":240}]:
		release_inputs();stage_name=c.name
		for code in c.keys:key(code,true)
		await sample_motion(c.ticks)
	release_inputs()
	check("actual finite motor and both soles",rows.all(func(r):return (r.velocity as Vector3).is_finite() and (r.left as Vector3).is_finite() and (r.right as Vector3).is_finite()))
	check("90 input begins with real high forward speed",rows.filter(func(r):return r.stage=="free_run")[-1].velocity.length()>4.0)
	check("cut90 actual CUT request observed",transitions.any(func(r):return r.stage=="cut90" and r.event.event=="REQUEST" and r.event.kind=="CUT" and r.event.variant_degrees==90))
	check("cut90 matching CUT request completes two real landings",transitions.any(func(r):return r.stage=="cut90" and r.event.event=="COMPLETE" and r.event.kind=="CUT" and r.event.variant_degrees==90 and r.event.confirmed>=2))
	check("complete never precedes two real landings",transitions.all(func(r):return r.event.event!="COMPLETE" or r.event.confirmed>=2))

	var ok:bool=checks.all(func(c):return c.passed)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE).store_string(JSON.stringify({"passed":ok,"checks":checks,"rows":rows,"steps":steps,"transitions":transitions,"scope":"Isolated3v3 realhuman ShiftW 2s then ShiftA90 2s before field boundary; real shared motor and real skeleton support producer. Initial setup only, no assigned velocity or camera rotation during movement. Checks require CUT90 request in high-speed cut90 stage, not START90 or later slow strafe. Not native visual/fullmatch acceptance."},"\t"))
	game.pause_match();game.shutdown_audio();game.queue_free();game=null
	for i in 4:await process_frame
	quit(0 if ok else 1)
