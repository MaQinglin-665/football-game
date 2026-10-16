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
		boot.measured_velocity=Vector3.RIGHT*speed
		actor.velocity=Vector3.RIGHT*speed
		game.ball.position=Vector3(.16,.10,3.0);game.ball.velocity=Vector3.ZERO
		game.ball.last_lower_contact_frame=-100
		var before:Vector3=game.ball.position
		var count:int=game.ball.collision_count
		var body_count:int=game.ball.body_collision_count
		var samples:Array=Sweep.snapshot([actor],game.ball,1.0/120.0)
		boot.global_position+=Vector3.RIGHT*speed/120.0
		Sweep.settle(game.ball,samples,before,count,1.0/120.0)
		check("stationary ball moving boot "+str(speed),game.ball.body_collision_count==body_count+1 if speed>1.0 else game.ball.velocity.length()<.001,{"samples":samples.size(),"velocity":game.ball.velocity})
		if speed>1.0:
			var settled:Vector3=game.ball.velocity
			Sweep.settle(game.ball,samples,before,count,1.0/120.0)
			check("same swept contact cannot apply twice",game.ball.velocity==settled and game.ball.body_collision_count==body_count+1)
	# Opponent-owned slow ball meets a real boot, with no tackle/pressure action.
	for defender in [game.player,game.players[1]]:
		stage(defender,Vector3(.2,0,-.3),Vector3.ZERO)
		var owner:Node3D=game.players.filter(func(p):return p.team!=defender.team)[0]
		game.ball.take(owner)
		var proxy:Node=defender.get_node("LowerBallContacts")
		proxy.update_from_skeleton(0.0)
		for part in proxy.parts.values():part.collision_layer=0
		var boot:Node3D=proxy.parts["boot.R"]
		boot.collision_layer=8;boot.global_transform=Transform3D(Basis.IDENTITY,Vector3(0,.10,3.0))
		boot.measured_velocity=Vector3.RIGHT*3;defender.velocity=Vector3.RIGHT*3
		game.ball.position=Vector3(.16,.10,3);game.ball.velocity=Vector3.ZERO;game.ball.last_lower_contact_frame=-100
		var before:Vector3=game.ball.position;var count:int=game.ball.collision_count
		var samples:Array=Sweep.snapshot([defender],game.ball,1.0/120.0)
		check("nearby alone does not steal "+str(defender.is_human),game.ball.carrier==owner)
		boot.global_position+=Vector3.RIGHT*3/120.0
		Sweep.settle(game.ball,samples,before,count,1.0/120.0)
		check("physical block breaks old possession "+str(defender.is_human),game.ball.carrier==null and game.ball.velocity.length()>.1 and defender.foot.idle())
		check("block does not award possession",game.ball.carrier!=defender)
	FileAccess.open("res://../verification/passive-contact.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks}))
	game.shutdown_audio();game.queue_free();await ticks(3)
	quit(0 if checks.all(func(c):return c.ok) else 1)
