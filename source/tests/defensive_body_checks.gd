extends "res://tests/contact_flow_check.gd"
var body_hits:=0
func run()->void:
	game=load("res://scenes/training_3v3.tscn").instantiate();game.test_mode=true;root.add_child(game)
	await ticks(6);game.hud.menu.get_node("StartMatch").pressed.emit();await ticks(8)
	game.tactics_bridge.set_physics_process(false);game.training_mode.set_physics_process(false)
	game.ai_enabled=false
	for defender in [game.player,game.agents[0]]:
		label="human_screen" if defender.is_human else "ai_screen"
		stage(defender,Vector3(3,0,0),Vector3.ZERO)
		var opponent:Node3D=game.players.filter(func(p):return p.team!=defender.team)[0]
		opponent.position=actor.position+Vector3(.78,0,0);opponent.velocity=Vector3.ZERO;opponent.set_move_intent(Vector3.ZERO)
		actor.velocity=Vector3.RIGHT*2.0;actor.set_move_intent(Vector3.RIGHT*.5)
		body_hits=0
		var capture:Callable=func(other,_n,_j):
			if other==opponent:body_hits+=1
		actor.body_contact.connect(capture)
		await ticks(30)
		actor.body_contact.disconnect(capture)
		check(label+" actual shoulder collision",body_hits>0,{"contacts":body_hits})
		check(label+" torso cannot pass through opponent",actor.position.x<opponent.position.x and actor.position.distance_to(opponent.position)>.45)
		check(label+" body proximity does not award distant ball",game.ball.carrier!=actor and game.ball.last_contact_actor!=actor)
	var passed:bool=checks.all(func(c):return c.ok)
	FileAccess.open("res://../verification/defensive_body_checks.json",FileAccess.WRITE).store_string(JSON.stringify(checks,"  "))
	game.shutdown_audio();game.queue_free();await ticks(3);quit(0 if passed else 1)
