extends SceneTree
var game:Node
var actor:Node3D
var label:=""
var checks:Array=[]
var events:Array=[]
var traces:Array=[]
var auto_seen:=false
var duplicates:=0
func _initialize()->void:call_deferred("run")
func ticks(n:int)->void:
	for i in n:await physics_frame
func key(code:int,pressed:bool)->void:
	var event:=InputEventKey.new();event.physical_keycode=code;event.keycode=code;event.pressed=pressed
	Input.parse_input_event(event);Input.flush_buffered_events()
func check(name:String,ok:bool,detail:Variant={})->void:
	checks.append({"name":name,"ok":ok,"detail":detail});print("PASS " if ok else "FAIL ",name," ",detail)
func stage(who:Node3D,offset:Vector3,velocity:Vector3,enemy:bool=true)->void:
	actor=who;auto_seen=false
	game.ball.clear_control();game.ball.set_held(false)
	game.set_phase(game.Phase.PLAY);game.services.rules._second_touch_actor=-1;game.services.rules._become_live()
	for p in game.players:
		p.set_physics_process(false);p.foot.cancel("fixture");p.velocity=Vector3.ZERO;p.set_move_intent(Vector3.ZERO);p.position=Vector3(10+p.team*2,.002,10+p.jersey*.1)
		if not p.is_human:p.pending_kick.clear()
	actor.position=Vector3(0,.002,4);actor.facing=Vector3.FORWARD;actor.body_facing=Vector3.FORWARD;actor.action_cooldown=0;actor.tackle_cooldown=0
	if not actor.is_human:actor.active=true;actor.face_target=Vector3.FORWARD;actor.tactical_intent.clear()
	else:actor.reset_view(0);actor.semantic_motion=Vector3.ZERO;actor.move_requested=false
	actor.avatar._plants.clear();actor.avatar._last_contacts.clear();actor.refresh_pose(1./120.)
	game.ball.reset(actor.position+offset);game.ball.position.y=game.ball.radius+.001;game.ball.previous_position=game.ball.position;game.ball.velocity=velocity
	game.ball.pickup_block=0;game.ball.touch_timer=0;game.ball.last_touch_team=1-actor.team if enemy else actor.team
func observe(n:int)->void:
	for i in n:
		await physics_frame
		auto_seen=auto_seen or actor.foot.kind=="TACKLE" and bool(actor.foot.touch_plan.get("automatic",false))
		traces.append({"case":label,"t":i/120.,"phase":actor.foot.phase,"kind":actor.foot.kind,"ball":game.ball.position,"velocity":game.ball.velocity,"toe":actor.foot.toe_world,"failure":actor.foot.contact_failure,"hit":actor.foot.hit})
func hits()->Array:return events.filter(func(e):return e.case==label and e.action=="TACKLE")
func run()->void:
	game=load("res://scenes/training_3v3.tscn").instantiate();game.test_mode=true;root.add_child(game)
	await ticks(6);game.hud.menu.get_node("StartMatch").pressed.emit();await ticks(8)
	game.tactics_bridge.set_physics_process(false);game.training_mode.set_physics_process(false)
	game.ai_enabled=true
	game.contact_hub.contact_resolved.connect(func(e):
		if e.get("actor")==actor and e.get("success",false):
			events.append({"case":label,"action":e.get("action",""),"sequence":actor.foot.sequence,"before":e.get("before_velocity"),"after":e.get("after_velocity"),"point":e.get("point")})
			if e.get("action","")=="TACKLE" and game.resolve_tackle_contact(actor,actor.facing,actor.foot.toe_world):duplicates+=1)
	for spec in [["right_pass",.47,4.0],["left_pass",-.47,4.0],["slow_pass",.42,.9],["fast_pass",-.40,10.0]]:
		label=spec[0];stage(game.player,Vector3(spec[1],0,-.90 if spec[2]>2 else -.43),Vector3(0,0,spec[2]))
		var root_before:Vector3=actor.position;var view_before:Vector3=actor.rotation
		await observe(80)
		check(label+" automatic reachable leg contact",auto_seen and hits().size()==1,{"auto":auto_seen,"hits":hits().size(),"failure":actor.foot.contact_failure})
		check(label+" no auto root or camera steering",actor.position.distance_to(root_before)<.015 and actor.rotation==view_before)
	label="ai_pass";stage(game.agents[0],Vector3(.47,0,-.9),Vector3(0,0,4));await observe(80)
	check("AI shares real automatic intercept",auto_seen and hits().size()==1)
	label="moving_human";stage(game.player,Vector3(.55,0,-.85),Vector3(0,0,4));actor.set_physics_process(true)
	key(KEY_D,true);await observe(14);key(KEY_D,false)
	check("moving human intercept does not turn hips or redirect input",auto_seen and actor.velocity.x>.15 and absf(actor.hip_yaw)<.015 and actor.semantic_motion.x>.5,{"automatic":auto_seen,"velocity":actor.velocity,"hip_yaw":actor.hip_yaw,"intent":actor.semantic_motion})
	actor.set_physics_process(false)
	label="moving_ai";stage(game.agents[0],Vector3(.55,0,-.85),Vector3(0,0,4));actor.target=actor.position+Vector3.RIGHT*5;actor.tactical_pace=2.8;actor.set_physics_process(true)
	await observe(14)
	check("moving AI intercept keeps tactical heading",auto_seen and actor.velocity.x>.15 and actor.facing.dot(Vector3.FORWARD)>.999,{"automatic":auto_seen,"velocity":actor.velocity,"facing":actor.facing})
	actor.set_physics_process(false)
	label="outside_reach";stage(game.player,Vector3(1.6,0,-.9),Vector3(0,0,4));await observe(80)
	check("outside reach stays a free pass",not auto_seen and hits().is_empty())
	label="departing";stage(game.player,Vector3(.5,0,-.8),Vector3(0,0,-5));await observe(60)
	check("departing ball no automatic chase",not auto_seen and hits().is_empty())
	label="teammate";stage(game.player,Vector3(.47,0,-.9),Vector3(0,0,4),false);await observe(60)
	check("teammate pass keeps reception priority",not auto_seen)
	label="stationary_enemy";stage(game.player,Vector3(.4,0,-.3),Vector3.ZERO)
	actor.move_requested=true;game.schedule_receiving()
	check("settled opponent loose ball can still be received",actor.foot.kind=="RECEIVE")
	label="manual_side";stage(game.player,Vector3(.4,0,-.3),Vector3.ZERO)
	check("manual side poke accepted",game.attempt_tackle(actor));await observe(70)
	check("manual side poke uses actual contact",hits().size()==1)
	label="owned_side";stage(game.player,Vector3(.4,0,-.30),Vector3.ZERO)
	var owner:Node3D=game.agents.filter(func(p):return p.team!=actor.team)[0]
	owner.position=Vector3(.4,.002,3.15);owner.facing=Vector3.BACK;owner.body_facing=Vector3.BACK;owner.refresh_pose(1./120.)
	game.ball.carrier=owner # Initial controlled-ball fixture, no forced ownership after setup.
	check("reachable opponent-foot challenge begins",game.attempt_tackle(actor));await observe(65)
	check("opponent-foot challenge is a real single touch",hits().size()==1,{"failure":actor.foot.contact_failure,"hits":hits().size()})
	label="blocked";stage(game.player,Vector3(.4,0,-.65),Vector3.ZERO)
	var wall:=StaticBody3D.new();wall.collision_layer=1;wall.collision_mask=0
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(1.4,.6,.04);shape.shape=box;wall.add_child(shape);game.add_child(wall);wall.position=Vector3(0,.25,3.62)
	await ticks(2)
	check("blocked shoe route rejects challenge",not game.attempt_tackle(actor));await observe(45)
	check("wall cannot be intercepted through",hits().is_empty());wall.queue_free();await ticks(2)
	label="withdraw";stage(game.player,Vector3(.4,0,-.75),Vector3(0,0,2))
	check("withdraw fixture starts a finite challenge",game.attempt_tackle(actor))
	await ticks(2)
	var before_weight:float=preload("res://scripts/tackle_motion.gd").new().weight(actor.foot.pose_request())
	actor.foot.begin_tackle_withdraw()
	var after_weight:float=preload("res://scripts/tackle_motion.gd").new().weight(actor.foot.pose_request())
	check("early withdraw retains current body load",absf(before_weight-after_weight)<.0001,{"before":before_weight,"after":after_weight})
	actor.refresh_pose(0)
	var cache_error:=0.0
	for side in ["L","R"]:
		var visible_point:Vector3=actor.avatar.skeleton.to_global(actor.avatar.skeleton.get_bone_global_pose(actor.avatar.cached_bone_id("foot."+side)).origin)
		cache_error=maxf(cache_error,visible_point.distance_to(actor.avatar._last_ankles[side].point))
	check("tackle support caches final visible shoes",cache_error<.0001,cache_error)
	await observe(40)
	check("withdraw releases the action promptly",actor.foot.idle())
	check("each tackle settles at most once",duplicates==0)
	var passed:bool=checks.all(func(c):return c.ok)
	var path:="res://../verification/contact_flow.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):path=arg.trim_prefix("--out=")
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"checks":checks,"events":events,"traces":traces,"scope":"Initial-position fixtures, real ball/shoe sweeps; not natural-match or frame-time evidence"},"  "))
	game.shutdown_audio();game.queue_free();await ticks(3);quit(0 if passed else 1)
