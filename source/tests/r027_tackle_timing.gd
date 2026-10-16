extends "res://tests/contact_flow_check.gd"
func run()->void:
	game=load("res://scenes/training_3v3.tscn").instantiate();game.test_mode=true;root.add_child(game)
	await ticks(6);game.hud.menu.get_node("StartMatch").pressed.emit();await ticks(8)
	game.tactics_bridge.set_physics_process(false);game.training_mode.set_physics_process(false)
	game.contact_hub.contact_resolved.connect(func(e):
		if e.get("actor")==actor and e.get("success",false):events.append({"case":label,"action":e.get("action",""),"sequence":actor.foot.sequence,"elapsed":actor.foot.elapsed}))
	for side in [-1.0,1.0]:
		for speed in [0.0,3.0]:
			label=str(side)+":"+str(speed)
			stage(game.player,Vector3(side*.30,0,-.40),Vector3.ZERO)
			actor.velocity=Vector3.FORWARD*speed;actor.set_move_intent(Vector3.FORWARD*speed/actor.motor_speed_limit(0))
			var plan:Dictionary=game.standing_tackle_prediction(actor,{"position":game.ball.position,"velocity":game.ball.velocity,"age_s":0.0})
			check(label+" early reachable plan",not plan.is_empty() and float(plan.contact_eta_s)<=.11,plan)
			check(label+" request accepted",game.attempt_tackle(actor))
			await observe(30)
			check(label+" actual single poke",hits().size()==1,hits())
	FileAccess.open("res://../verification/tackle-timing.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"events":events,"traces":traces}))
	game.shutdown_audio();game.queue_free();await ticks(3)
	quit(0 if checks.all(func(c):return c.ok) else 1)
