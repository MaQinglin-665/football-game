extends "res://tests/integration_checks.gd"
var kicker:Node3D
var launch:Dictionary={}
func run()->void:
	game=load("res://scenes/match.tscn").instantiate();game.test_mode=true;root.add_child(game)
	await ticks(5);game.start_match(false);await ticks(5)
	game.tactics_bridge.set_physics_process(false)
	game.services.rules.state=game.Rules.State.LIVE;game._sync_rule_phase()
	for actor in game.players:
		actor.set_physics_process(false);actor.foot.cancel("fixture");actor.velocity=Vector3.ZERO;actor.set_move_intent(Vector3.ZERO)
		actor.position=Vector3(28+actor.team*2,.002,20+actor.jersey*.1)
		if not actor.is_human and not actor.is_goalkeeper and kicker==null:kicker=actor
	kicker.position=Vector3(0,.002,10);kicker.target=kicker.position;kicker.facing=Vector3.FORWARD;kicker.body_facing=Vector3.FORWARD;kicker.face_target=Vector3.FORWARD;kicker.active=true;kicker.action_cooldown=0;kicker.pending_kick.clear();kicker.tactical_pace=0
	kicker.avatar._plants.clear();kicker.avatar._last_contacts.clear();kicker.refresh_pose(1.0/120)
	game.ball.clear_control();game.ball.set_held(false);game.ball.reset(kicker.position+Vector3(0,game.ball.radius+.001,-.48));game.ball.pickup_block=0
	kicker.set_physics_process(true)
	game.contact_hub.contact_resolved.connect(func(e):
		if e.get("actor")==kicker and e.get("success",false) and e.get("action","")=="PASS":launch={"position":game.ball.position,"velocity":game.ball.velocity,"frame":Engine.get_physics_frames(),"sequence":e.get("action_sequence",-1)}
	)
	check("long-pass fixture starts real receive",kicker.foot.begin("RECEIVE",Vector3.FORWARD,Vector3.ZERO,0,.18))
	await ticks(65)
	check("long-pass fixture acquired through real shoe",game.ball.carrier==kicker)
	var intent:Dictionary={"action":"pass_high","direction":Vector3.FORWARD,"power":1.0,"elevation_deg":34.0,"spin":Vector3.ZERO,"plan_kick_id":123,"ai_loft_speed":26.0,"tactical_action":"PASS","receiver_id":-1}
	var accepted:bool=false
	for i in 90:
		if not accepted:accepted=game.request_actor_kick(kicker,intent)
		await physics_frame
		if not launch.is_empty():break
	check("long pass accepted by original foot action",accepted)
	check("long pass has actual foot contact",not launch.is_empty())
	var landing:Dictionary={}
	var windows:int=0
	var window_misses:int=0
	if not launch.is_empty():
		check("launch matches bounded 26mps request",absf((launch.velocity as Vector3).length()-26)<.2,launch)
		for i in 500:
			await physics_frame
			if i%12==0 and i>24 and game.ball.velocity.y>0:
				windows+=1
				var forecast:Array=preload("res://scripts/tactics/receive_motion.gd").ball_samples(game.ball.position,game.ball.velocity,game.ball.spin_rads,game.physics_profile)
				if not forecast.any(func(s):return s.point.y<=.42 and absf(s.point.z)<51.9):window_misses+=1
			if game.ball.position.y<game.ball.radius+.04 and Engine.get_physics_frames()-int(launch.frame)>30:
				landing={"position":game.ball.position,"time":float(Engine.get_physics_frames()-int(launch.frame))/Engine.physics_ticks_per_second,"distance":Vector2(game.ball.position.x-launch.position.x,game.ball.position.z-launch.position.z).length()};break
		game.tactics_bridge._build_loft_table()
		var expected:Dictionary={}
		for entry in game.tactics_bridge.aerial_delivery:
			if entry.get("launch_speed",0)==26.0:expected=entry
		check("actual flight exceeds old 20m limit",not landing.is_empty() and float(landing.distance)>28,landing)
		check("predicted aerial landing matches real flight",not landing.is_empty() and not expected.is_empty() and absf(float(landing.distance)-float(expected.distance))<1.2 and absf(float(landing.time)-float(expected.time))<.15,{"actual":landing,"predicted":expected})
	check("airborne forecast retains real foot-height landing windows",windows>0 and window_misses==0,{"windows":windows,"misses":window_misses})
	var regression:Array=preload("res://scripts/tactics/receive_motion.gd").ball_samples(Vector3(2.157285,1.464013,-4.979814),Vector3(-17.82385,11.81554,6.791829),Vector3.ZERO,game.physics_profile)
	check("observed fast descent does not mask reachable post-bounce window",regression.any(func(s):return s.point.y<=.42 and s.speed<=14 and absf(s.point.x)<33.4))
	FileAccess.open(evidence+"/long_contact_check.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"launch":launch,"landing":landing,"scope":"isolated real receive and shoe pass, no forced possession or mid-flight ball writes; no natural tactical claim"},"  "))
	game.shutdown_audio();game.queue_free();game=null
	for i in 4:await process_frame
	quit(1 if checks.any(func(c):return not c.passed) else 0)
