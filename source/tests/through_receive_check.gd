extends "res://tests/integration_checks.gd"
func run()->void:
	game=load("res://scenes/training_3v3.tscn" if "--small" in OS.get_cmdline_user_args() else "res://scenes/match.tscn").instantiate();game.test_mode=true;root.add_child(game)
	await ticks(5);game.start_match(false);await ticks(5)
	game.tactics_bridge.set_physics_process(false)
	game.services.rules.state=game.Rules.State.LIVE;game._sync_rule_phase()
	var mate:Node3D
	for a in game.players:
		a.set_physics_process(false);a.foot.cancel("fixture");a.velocity=Vector3.ZERO;a.position=Vector3(20,.002,20);a.visible=false
		if a.team==0 and not a.is_human and not a.is_goalkeeper and mate==null:mate=a
	game.player.visible=true;mate.visible=true
	game.player.position=Vector3(0,.002,5);game.player.facing=Vector3.FORWARD;game.player.body_facing=Vector3.FORWARD;game.player.reset_view(0)
	game.ball.clear_control();game.ball.reset(Vector3(0,.111,0));game.ball.velocity=Vector3(0,0,-5)
	mate.position=Vector3(.7,.002,.3);mate.facing=Vector3.FORWARD
	check("runner just behind a lead ball is considered",game.tactics_bridge.infer_receive_target(game.player)==mate)
	mate.position=Vector3(18,.002,18)
	check("unreachable teammate is not promised a pass",game.tactics_bridge.infer_receive_target(game.player)==null)
	mate.position=Vector3(.7,.002,.3)
	var d=game.tactical_director
	var row:Dictionary={"id":game.players.find(mate),"team":0,"position":mate.position,"velocity":Vector3.ZERO,"facing":Vector3.FORWARD}
	var members:Array[Dictionary]=[row]
	var snap:Dictionary={"ball_position":game.ball.position,"ball_velocity":game.ball.velocity,"field_half_length":game.field_half_length,"carrier_id":-1}
	check("loose ball gets one claimant despite possession hint",d._pick_presser(0,members,{},0,-1,false,snap)==int(row.id))
	var attack=preload("res://scripts/tactics/team_attack.gd").new()
	var owner:Dictionary={"id":0,"team":0,"human":true,"position":Vector3.ZERO}
	var runner:Dictionary={"id":1,"team":0,"position":Vector3(3,0,-2),"velocity":Vector3.ZERO,"facing":Vector3.FORWARD}
	var protect:Dictionary={"id":2,"team":0,"position":Vector3(0,0,4),"velocity":Vector3.ZERO}
	var small_members:Array[Dictionary]=[owner,runner,protect]
	var opponents:Array[Dictionary]=[]
	var tasks:Dictionary={1:{"point":runner.position,"role":"DIAGONAL","pace":5.4},2:{"point":protect.position,"role":"SAFE","pace":5.4}}
	attack._advance_run(0,owner,small_members,opponents,{"carrier_id":0,"ball_position":Vector3.ZERO,"field_half_length":18.0,"field_half_width":12.0},{0:{"slot":"LF"},1:{"slot":"RF"},2:{"slot":"BACK"}},0,tasks)
	check("human possession offers a forward runner in small sides",tasks[1].role=="FORWARD_RUN",tasks)
	check("forward run retains the rear outlet",tasks[2].role=="SAFE" and tasks[2].point==protect.position)
	game.player.action_cooldown=0;game.player.foot.cancel("fixture");game.player.position=Vector3(0,.002,5)
	game.ball.reset(game.player.position+Vector3(.23,.11,-.4));game.ball.carrier=game.player;game.ball.possession_age=.5;game.ball.touch_timer=2
	mate.position=game.ball.position+Vector3(1.3,0,-8)
	game.assist=true
	var accepted:bool=game.request_player_kick({"action":"pass_ground","direction":Vector3.FORWARD,"power":.35,"elevation_deg":0.0,"spin":Vector3.ZERO})
	check("explicit lead aim survives pass assist",accepted and Vector3(game.player.foot.kick_intent.get("direction",Vector3.ZERO)).dot(Vector3.FORWARD)>.9999,game.player.foot.kick_intent)
	FileAccess.open(evidence+"/through_policy.json",FileAccess.WRITE).store_string(JSON.stringify(checks,"  "))
	game.shutdown_audio();game.queue_free();game=null;await process_frame;await process_frame;quit(1 if checks.any(func(c):return not c.passed) else 0)
