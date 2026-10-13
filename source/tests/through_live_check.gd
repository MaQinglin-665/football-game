extends "res://tests/integration_checks.gd"
var trace:Array=[]
var hits:Array=[]
func run()->void:
	var small:bool="--small" in OS.get_cmdline_user_args()
	game=load("res://scenes/training_3v3.tscn" if small else "res://scenes/match.tscn").instantiate();game.test_mode=true;root.add_child(game)
	await ticks(5);game.start_match(false);await ticks(5)
	game.services.rules.state=game.Rules.State.LIVE;game._sync_rule_phase()
	game.tactical_director.reset();game.tactics_bridge.clock=0
	var mate:Node3D
	for a in game.players:
		a.foot.cancel("fixture");a.velocity=Vector3.ZERO;a.position=Vector3((4+a.jersey%4)*(-1 if a.team==0 else 1),.002,7+a.jersey%3)
		if not a.is_human:a.pending_kick.clear()
		if a.team==0 and not a.is_human and not a.is_goalkeeper and mate==null:mate=a
	game.player.set_physics_process(false);game.player.position=Vector3(0,.002,2);game.player.reset_view(0);game.player.facing=Vector3.FORWARD;game.player.body_facing=Vector3.FORWARD;game.player.action_cooldown=0
	game.player.avatar.visual.global_rotation=Vector3.ZERO;game.player.avatar._plants.clear();game.player.avatar.invalidate_pose_snapshot()
	for warm in 35:game.player.refresh_pose(1.0/120)
	mate.position=Vector3(1.5,.002,-1);mate.facing=Vector3.FORWARD;mate.body_facing=Vector3.FORWARD
	if "--lead" in OS.get_cmdline_user_args():mate.position=Vector3(2.5,.002,-8)
	var origin:Vector3=mate.position
	game.ball.clear_control();game.ball.set_held(false);game.ball.reset(game.player.position+Vector3(.23,.11,-.4));game.ball.carrier=game.player;game.ball.possession_age=.5;game.ball.touch_timer=2;game.ball.pickup_block=0
	game.contact_hub.contact_resolved.connect(func(e):
		if e.get("success",false):hits.append({"actor":game.players.find(e.get("actor")),"action":e.get("action"),"ball":game.ball.position,"receiver":game.players.find(game.player.foot.receiver)})
	)
	game.assist=true
	game.input_bridge.sync_context()
	var accepted:bool=game.request_player_kick({"action":"pass_ground","direction":Vector3.FORWARD,"power":.65 if "--lead" in OS.get_cmdline_user_args() else .30,"elevation_deg":0.0,"spin":Vector3.ZERO})
	var first_move:int=-1;var plan_seen:bool=false;var max_speed:float=0;var progress:float=0;var received:bool=false
	for i in 420:
		await physics_frame
		game.player.refresh_pose(1.0/120)
		if mate.position.distance_to(origin)>.20 and first_move<0:first_move=i
		plan_seen=plan_seen or int(game.tactical_director.receive_plan.active.get("receiver_id",-1))==game.players.find(mate)
		max_speed=maxf(max_speed,mate.velocity.length());progress=maxf(progress,origin.z-mate.position.z)
		received=received or game.ball.carrier==mate
		if i%6==0:trace.append({"frame":i,"ball":game.ball.position,"mate":mate.position,"velocity":mate.velocity,"target":mate.target,"reason":mate.tactical_intent.get("reason",""),"owner":game.players.find(game.ball.carrier),"foot":mate.foot.kind,"plan":game.tactical_director.receive_plan.active.get("receiver_id",-1)})
		if native and i in [50,140,260]:await capture("through_"+str(game.players.size())+"_"+str(i))
	check("real pass is released once",accepted and hits.filter(func(h):return h.actor==0 and h.action=="PASS").size()==1,{"accepted":accepted,"hits":hits,"failure":game.player.foot.contact_failure,"trace":game.player.foot.action_trace})
	check("actual flight assigns intended runner",plan_seen)
	check("runner moves promptly",first_move>=0 and first_move<65,{"physics_frames":first_move})
	check("runner advances into lead space",progress>1.0 and max_speed>2.0,{"forward_m":progress,"speed":max_speed,"controlled":received})
	FileAccess.open(evidence+"/through_live_"+("long_" if "--lead" in OS.get_cmdline_user_args() else "")+("3" if small else "11")+".json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"trace":trace,"contacts":hits,"received":received,"scope":"controlled starting layout, real human kick and normal AI decisions/movement/contact afterwards; not a natural-match proof"},"  "))
	game.shutdown_audio();game.queue_free();game=null;await process_frame;await process_frame;quit(1 if checks.any(func(c):return not c.passed) else 0)
