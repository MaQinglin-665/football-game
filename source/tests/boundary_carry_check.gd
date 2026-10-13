extends "res://tests/integration_checks.gd"
var rows:Array=[]
func run()->void:
	game=load("res://scenes/match.tscn").instantiate();game.test_mode=true;root.add_child(game)
	await ticks(5);game.start_match(false);await ticks(5)
	game.tactics_bridge.set_physics_process(false)
	game.services.rules.restart.clear();game.services.rules.state=game.Rules.State.LIVE
	game.restart_plan.clear();game.restart_taker=null;game.set_phase(game.Phase.PLAY)
	var a:Node3D
	for actor in game.players:
		actor.set_physics_process(false);actor.foot.cancel("initial_fixture");actor.velocity=Vector3.ZERO;actor.set_move_intent(Vector3.ZERO)
		actor.position=Vector3(60+actor.team*4,.002,actor.jersey*2)
		if actor!=game.player and actor.team==0 and not actor.is_goalkeeper and a==null:a=actor
	a.position=Vector3(18,.002,-game.field_half_length+7);a.target=a.position;a.facing=Vector3.FORWARD;a.body_facing=a.facing;a.face_target=a.facing;a.active=true;a.action_cooldown=0;a.pending_kick.clear()
	a.refresh_pose(1.0/120.0)
	game.ball.clear_control();game.ball.set_held(false);game.ball.reset(a.position+Vector3(0,game.ball.radius+.001,-.48));game.ball.pickup_block=0
	a.set_physics_process(true);a.foot.begin("RECEIVE",Vector3.FORWARD,Vector3.ZERO,0,.18)
	await ticks(65)
	check("initial real reception owns ball",game.ball.carrier==a)
	var guard:bool=not "--before-boundary" in OS.get_cmdline_user_args()
	var inside:bool=true;var turned:bool=false;var min_z:float=game.ball.position.z
	for i in 480:
		game.tactical_director.clock+=1.0/Engine.physics_ticks_per_second
		var intent:Dictionary={"action":"NONE","role":"winger","move_target":Vector3(18,0,-game.field_half_length+.1),"face_direction":Vector3.FORWARD,"pace":5.0,"carry_run":true,"close_control":false,"shield":false,"reason":"fixture_forward"}
		if guard:game.tactical_director._guard_carry_boundary({"id":game.players.find(a),"team":0,"position":a.position,"velocity":a.velocity},intent,{"ball_position":game.ball.position,"ball_velocity":game.ball.velocity,"field_half_width":game.field_half_width,"field_half_length":game.field_half_length})
		if intent.reason=="keep_ball_inside_before_line":turned=true
		a.tactical_intent=intent;a.target=intent.move_target;a.face_target=intent.face_direction;a.tactical_pace=intent.pace;a.close_control=false;a.shielding=false
		await physics_frame
		min_z=minf(min_z,game.ball.position.z)
		if absf(game.ball.position.z)>game.field_half_length+game.ball.radius:inside=false
		if i%12==0:rows.append({"frame":i,"ball":game.ball.position,"body":a.position,"owned":game.ball.carrier==a,"speed":a.velocity.length(),"guard":intent.reason,"failure":a.foot.contact_failure})
	check("braking reserve selects inward route",turned if guard else true)
	check("ball stays inside goal line during physical turn",inside)
	FileAccess.open("res://../verification/boundary_"+("after" if guard else "before")+".json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"min_z":min_z,"rows":rows,"scope":"one declared initial fixture; actual reception, motor, shoe contacts and ball physics; not natural game"},"  "))
	game.quit_game()
