extends "res://tests/contact_flow_check.gd"
const Sweep:=preload("res://scripts/relative_boot_block.gd")
func run()->void:
	game=load("res://scenes/training_3v3.tscn").instantiate();game.test_mode=true;root.add_child(game)
	await ticks(6);game.hud.menu.get_node("StartMatch").pressed.emit();await ticks(8)
	game.tactics_bridge.set_physics_process(false);game.training_mode.set_physics_process(false)
	# Isolate a single moving boot's continuous contact against a stationary ball.
	# Declared geometry fixture; this is not a natural play or animation test.
	for speed in [0.0,1.0,5.6]:
		stage(game.player,Vector3(.2,0,-.3),Vector3.ZERO)
		var proxy:Node=actor.get_node("LowerBallContacts")
		proxy.update_from_skeleton(0.0)
		var boot:Node3D=proxy.parts["boot.R"]
		for part in proxy.parts.values():part.collision_layer=0
		boot.collision_layer=8
		boot.global_transform=Transform3D(Basis.IDENTITY,Vector3(0,.10,3.0))
		boot.measured_velocity=Vector3.RIGHT*(18.0 if speed>1.0 else speed) # Prior animation-frame velocity differs from this substep.
		actor.velocity=Vector3.RIGHT*speed
		game.ball.position=Vector3(.16,.10,3.0);game.ball.velocity=Vector3.ZERO
		game.ball.last_lower_contact_frame=-100
		var before:Vector3=game.ball.position
		var count:int=game.ball.collision_count
		var body_count:int=game.ball.body_collision_count
		var samples:Array=Sweep.snapshot([actor],game.ball,1.0/120.0)
		boot.global_position+=Vector3.RIGHT*speed/120.0
		if speed>1.0:check("engine collision uses same substep velocity",absf(boot.ball_contact_velocity(game.ball.position).length()-speed)<.001)
		Sweep.settle(game.ball,samples,before,count,1.0/120.0)
		check("stationary ball moving boot "+str(speed),game.ball.body_collision_count==body_count+1 if speed>1.0 else game.ball.velocity.length()<.001,{"samples":samples.size(),"velocity":game.ball.velocity})
		if speed>1.0:
			check("response uses swept substep velocity",game.ball.velocity.length()<7.0,{"speed":game.ball.velocity.length()})
			var settled:Vector3=game.ball.velocity
			Sweep.settle(game.ball,samples,before,count,1.0/120.0)
			check("same swept contact cannot apply twice",game.ball.velocity==settled and game.ball.body_collision_count==body_count+1)
	# Real W + sprint input, no per-frame actor/ball writes after initial setup.
	game.contact_hub.contact_resolved.connect(func(e):
		if e.get("actor")==actor and e.get("success",false):events.append({"case":label,"action":e.get("action",""),"sequence":actor.foot.sequence}))
	for spec in [["loose",0.0,true],["receive",2.0,false],["intercept",2.0,true]]:
		label=spec[0];stage(game.player,Vector3(.16,0,-2.5),Vector3(0,0,spec[1]),spec[2])
		actor.set_physics_process(true)
		key(KEY_W,true);key(KEY_SHIFT,true);key(KEY_SHIFT,false)
		await observe(120)
		key(KEY_W,false)
		check(label+" running approach makes real contact",events.any(func(e):return e.case==label),{"events":events.filter(func(e):return e.case==label),"failure":actor.foot.contact_failure})
	FileAccess.open("res://../verification/running-contact-r026.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"events":events,"traces":traces}))
	game.shutdown_audio();game.queue_free();await ticks(3)
	quit(0 if checks.all(func(c):return c.ok) else 1)


