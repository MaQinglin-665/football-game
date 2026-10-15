extends "res://tests/contact_flow_check.gd"
var request_tick:int=0
func run()->void:
	game=load("res://scenes/training_3v3.tscn").instantiate();game.test_mode=true;root.add_child(game)
	await ticks(6);game.hud.menu.get_node("StartMatch").pressed.emit();await ticks(8)
	game.tactics_bridge.set_physics_process(false);game.training_mode.set_physics_process(false)
	game.contact_hub.contact_resolved.connect(func(e):
		if e.get("actor")==actor and e.get("success",false):events.append({"case":label,"action":e.get("action",""),"sequence":actor.foot.sequence,"delay_ticks":Engine.get_physics_frames()-request_tick}))
	for side in [-1,1]:
		label="heel_"+str(side)
		stage(game.agents[0],Vector3(side*.22,0,.16),Vector3.ZERO)
		game.ball.carrier=actor;game.ball.possession_age=.5;game.ball.touch_timer=2.0
		actor.avatar.visual.global_rotation=Vector3.ZERO
		for warm in 35:actor.refresh_pose(1./120.)
		check(label+" legal pass without front receive",game.ball.can_pass(actor) and not game.ball.reception_ready(actor))
		actor.pending_kick={"action":"pass_ground","direction":Vector3.BACK,"power":.12,"elevation_deg":0.0,"spin":Vector3.ZERO}
		actor.pending_age=0;actor.target=actor.position;actor.tactical_pace=0;actor.set_physics_process(true)
		request_tick=Engine.get_physics_frames()
		await observe(65)
		var contacts:Array=events.filter(func(e):return e.case==label and e.action=="PASS")
		check(label+" pending pass reaches one actual contact",contacts.size()==1,{"contacts":contacts,"failure":actor.foot.contact_failure})
		actor.set_physics_process(false)
	var ok:bool=checks.all(func(c):return c.ok)
	game.shutdown_audio();game.queue_free();await ticks(3);quit(0 if ok else 1)
