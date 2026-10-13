extends "res://tests/integration_checks.gd"
var a:Node3D
var recipient:Node3D
var passes:Array=[]
var receives:Array=[]
func setup_ai_source(id:String)->Dictionary:
	release_inputs();a.foot.cancel("fixture");a.pending_kick.clear();a.action_cooldown=0;a.stop_requested=0
	a.position=Vector3(0,.002,4);a.target=a.position;a.velocity=Vector3.ZERO;a.facing=Vector3.FORWARD;a.body_facing=Vector3.FORWARD;a.face_target=Vector3.FORWARD;a.locomotion="idle";a.set_move_intent(Vector3.ZERO)
	a.avatar._plants.clear();a.avatar._last_contacts.clear();a.avatar._last_ankles.clear();a.avatar._last_local_ankles.clear();a.refresh_pose(1.0/120.0)
	game.ball.clear_control();game.ball.set_held(false);game.ball.position=a.position+Vector3.FORWARD*1.35;game.ball.position.y=game.ball.radius+.0005;game.ball.previous_position=game.ball.position;game.ball.velocity=Vector3.BACK*3.0;game.ball.spin_rads=Vector3.UP.cross(game.ball.velocity)/game.ball.radius;game.ball.pickup_block=0;game.ball.touch_timer=0
	game.tactical_director.clock=10.0
	var plan:Dictionary={"pass_id":id,"passer_id":game.players.find(recipient),"team":a.team,"state":"IN_FLIGHT","receiver_id":game.players.find(a),"next_action":"PASS","next_receiver_id":game.players.find(recipient),"next_direction":Vector3.FORWARD,"next_target":a.position+Vector3.FORWARD*5.0,"next_valid_until":10.8}
	game.tactical_director.receive_plan.active=plan.duplicate(true)
	passes.clear();receives.clear();return {"receive_plan":plan}
func run()->void:
	game=load("res://scenes/training_3v3.tscn").instantiate();game.test_mode=true;root.add_child(game)
	await ticks(6);game.hud.menu.get_node("StartMatch").pressed.emit();await ticks(8)
	game.tactics_bridge.set_physics_process(false)
	for actor in game.agents:
		actor.set_physics_process(false);actor.foot.cancel("fixture");actor.pending_kick.clear();actor.velocity=Vector3.ZERO;actor.set_move_intent(Vector3.ZERO)
		if actor.team==game.player.team and a==null:a=actor
		actor.position=Vector3(-9 if actor.team==0 else 9,.002,-10)
	recipient=game.player;recipient.position=Vector3(0,.002,-3)
	a.active=true;a.set_physics_process(true)
	game.contact_hub.contact_resolved.connect(func(e):
		if e.get("actor")==a and e.get("success",false):
			if e.get("action","")=="PASS":passes.append(e.duplicate())
			if e.get("action","")=="RECEIVE":receives.append(e.duplicate()))
	var intent:Dictionary=setup_ai_source("fixture-source-one")
	var offered:bool=game.tactics_bridge._dispatch_receive_continuation(a,intent)
	check("AI source plan offers one finite reservation",offered and a.foot.has_receive_pass())
	check("same source identity does not reserve twice",not game.tactics_bridge._dispatch_receive_continuation(a,intent))
	await ticks(75)
	check("AI actual shoe makes one direct PASS without prior RECEIVE",passes.size()==1 and receives.is_empty(),{"passes":passes,"receives":receives,"foot_result":a.foot.last_result,"failure":a.foot.contact_failure})
	intent=setup_ai_source("fixture-source-cancel")
	check("new source can reserve",game.tactics_bridge._dispatch_receive_continuation(a,intent))
	game.tactical_director.receive_plan.active.clear()
	await ticks(90)
	check("source supersession cancels without delayed PASS",passes.is_empty() and not a.foot.has_receive_pass(),{"passes":passes,"receives":receives})
	var ok:bool=checks.all(func(c):return c.passed)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE).store_string(JSON.stringify({"passed":ok,"checks":checks,"scope":"Declared3v3 IN_FLIGHT source plan/public adapter consumer; actualAI motor/pose/foot/World/ball, fixed own-position target and facing. Planner bridge disabled to isolate consumer. Not natural planner creation, half-time transform or nativefeel/FPS."},"\t"))
	game.pause_match();game.shutdown_audio();game.queue_free();game=null
	for i in 4:await process_frame
	quit(0 if ok else 1)
