extends "res://tests/integration_checks.gd"
var a:Node3D
var events:Array=[]
var outcomes:Array=[]
var label:String=""
var duplicate_accepts:=0
var motion_trace:Array=[]
var wall_setups:Array=[]
func make_wall(center:Vector3)->StaticBody3D:
	var wall:=StaticBody3D.new();wall.collision_layer=1;wall.collision_mask=0
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(1,.42,.04);shape.shape=box;wall.add_child(shape);game.add_child(wall);wall.global_position=center
	return wall
func record_wall(wall:StaticBody3D)->Dictionary:
	var half:=Vector3(.5,.21,.02);var toe:Vector3=a.foot.toe_world;var relative:Vector3=toe-wall.global_position
	var ball_relative:Vector3=game.ball.position-wall.global_position
	var row:Dictionary={"case":label,"initial_toe":toe,"ball":game.ball.position,"wall_center":wall.global_position,"wall_size":half*2,"shoe_inside":absf(relative.x)<=half.x and absf(relative.y)<=half.y and absf(relative.z)<=half.z,"ball_wall_surface_gap":ball_relative.distance_to(ball_relative.clamp(-half,half))-game.ball.radius}
	wall_setups.append(row);return row
func stage(actor:Node3D,offset:Vector3)->void:
	a=actor;release_inputs();game.ball.clear_control();game.ball.set_held(false)
	game.set_phase(game.Phase.PLAY);game.services.rules._second_touch_actor=-1;game.services.rules._become_live()
	for p in game.players:
		p.set_physics_process(false);p.foot.cancel("fixture");p.velocity=Vector3.ZERO;p.set_move_intent(Vector3.ZERO);p.position=Vector3(10+p.team*2,.002,10+p.jersey*.1)
		if not p.is_human:p.pending_kick.clear()
	a.position=Vector3(0,.002,4);a.facing=Vector3.FORWARD;a.body_facing=Vector3.FORWARD;a.action_cooldown=0;a.tackle_cooldown=0
	if not a.is_human:
		a.face_target=Vector3.FORWARD;a.active=true;a.target=a.position
	else:a.reset_view(0)
	a.avatar._plants.clear();a.avatar._last_contacts.clear();a.refresh_pose(1.0/120.0)
	game.ball.reset(a.position+offset);game.ball.position.y=game.ball.radius+.001;game.ball.previous_position=game.ball.position;game.ball.pickup_block=0;game.ball.touch_timer=0
	a.set_physics_process(true)
func capture_action(n:int)->void:
	for i in n:
		await physics_frame
		if a.foot.kind=="TACKLE" and a.foot.phase in [FootballFootAction.Phase.PREPARE,FootballFootAction.Phase.CONTACT]:motion_trace.append({"case":label,"frame":Engine.get_physics_frames(),"sequence":a.foot.sequence,"elapsed":a.foot.elapsed,"phase":a.foot.phase,"previous_toe":a.foot.previous_toe,"toe":a.foot.toe_world,"blocked":a.foot.tackle_motion_blocked,"first_block_elapsed":a.foot.tackle_motion_blocked_elapsed})
	outcomes.append({"case":label,"foot_hit":a.foot.hit,"result":a.foot.last_result,"failure":a.foot.contact_failure,"phase":a.foot.phase,"events":events.filter(func(e):return e.case==label),"ball":game.ball.position,"actor":a.position,"cooldown":a.tackle_cooldown})
func run()->void:
	game=load("res://scenes/training_3v3.tscn").instantiate();game.test_mode=true;root.add_child(game)
	await ticks(6);game.hud.menu.get_node("StartMatch").pressed.emit();await ticks(8);game.tactics_bridge.set_physics_process(false)
	game.contact_hub.contact_resolved.connect(func(e):
		if e.get("actor")==a and e.get("action","")=="TACKLE" and e.get("success",false):
			var before:Vector3=e.get("before_velocity",Vector3.ZERO);var after:Vector3=e.get("after_velocity",Vector3.ZERO)
			events.append({"case":label,"sequence":a.foot.sequence,"dv":after-before,"owner_null":game.ball.carrier==null,"reach_error":e.get("reach_error",-1),"point":e.get("point")})
			if game.resolve_tackle_contact(a,a.facing,a.foot.toe_world):duplicate_accepts+=1)
	label="front";stage(game.player,Vector3(0,0,-.43))
	check("public human standing tackle begins",game.attempt_tackle(a))
	await capture_action(100)
	check("front boot produces one actual poke",events.filter(func(e):return e.case=="front").size()==1)
	label="side";stage(game.player,Vector3(.40,0,-.22))
	check("side fixture lies outside former30degree cone",a.facing.dot(Vector3(.40,0,-.22).normalized())<cos(deg_to_rad(30)))
	check("side tackle starts without fake control",game.attempt_tackle(a) and game.ball.carrier==null)
	await capture_action(100)
	check("outside-cone actual boot produces one poke",events.filter(func(e):return e.case=="side").size()==1)
	label="miss";stage(game.player,Vector3(0,0,-1.8))
	check("out-of-reach human swing starts and pays recovery",game.attempt_tackle(a))
	await capture_action(110)
	check("miss recovers without contact or ownership",events.filter(func(e):return e.case=="miss").is_empty() and a.foot.idle() and game.ball.carrier==null)
	label="wall_block";stage(game.player,Vector3(0,0,-.62))
	var wall:=make_wall(a.position+Vector3(0,.21,-.33))
	await physics_frame
	check("standing tackle against real wall begins finite swing",game.attempt_tackle(a))
	record_wall(wall)
	await capture_action(110)
	check("real intervening wall blocks boot settlement",events.filter(func(e):return e.case=="wall_block").is_empty() and a.foot.idle() and game.ball.carrier==null)
	wall.queue_free();await physics_frame;await physics_frame
	label="wall_traverse";stage(game.player,Vector3(0,0,-.62));check("traverse case starts same real tackle",game.attempt_tackle(a))
	wall=make_wall(Vector3(0,.212,(a.foot.toe_world.z+a.foot.contact_target.z)*.5));var traversed:Dictionary=record_wall(wall)
	check("traverse fixture shoe and ball begin outside wall",not traversed.shoe_inside and float(traversed.ball_wall_surface_gap)>.001)
	await capture_action(110)
	check("real PREPARE wall crossing rejects settlement and recovers",events.filter(func(e):return e.case=="wall_traverse").is_empty() and a.foot.idle() and a.foot.tackle_motion_blocked and a.foot.contact_failure=="body_blocked")
	wall.queue_free();await physics_frame;await physics_frame
	label="wall_embedded";stage(game.player,Vector3(0,0,-.62));check("embedded case starts finite tackle",game.attempt_tackle(a))
	wall=make_wall(Vector3(a.foot.toe_world.x,.212,a.foot.toe_world.z));var embedded:Dictionary=record_wall(wall)
	check("embedded fixture shoe begins inside but ball outside wall",embedded.shoe_inside and float(embedded.ball_wall_surface_gap)>.001)
	await capture_action(110)
	check("initial embedded shoe rejects settlement and recovers",events.filter(func(e):return e.case=="wall_embedded").is_empty() and a.foot.idle() and a.foot.tackle_motion_blocked and a.foot.contact_failure=="body_blocked")
	wall.queue_free();await physics_frame;await physics_frame
	var ai:Node3D=game.agents[0]
	label="ai_side";stage(ai,Vector3(.40,0,-.22))
	check("stale AI observation rejected",not game.attempt_tackle(a,{"position":game.ball.position,"velocity":Vector3.ZERO,"age_s":.36}))
	check("fresh AI observation starts bounded action",game.attempt_tackle(a,{"position":game.ball.position,"velocity":Vector3.ZERO,"age_s":.1}))
	await capture_action(100)
	check("AI uses same real boot settlement",events.filter(func(e):return e.case=="ai_side").size()==1)
	check("all actual poke delta velocities remain bounded",not events.is_empty() and events.all(func(e):return (e.dv as Vector3).length()<=game.tuning.tackle_poke+.0001 and absf((e.dv as Vector3).y)<.0001))
	check("successful poke leaves actual free ownership",events.all(func(e):return e.owner_null))
	check("reentrant same-action second settlement rejected",duplicate_accepts==0)
	var ok:bool=checks.all(func(c):return c.passed)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE).store_string(JSON.stringify({"passed":ok,"checks":checks,"outcomes":outcomes,"events":events,"wall_setups":wall_setups,"motion_trace":motion_trace,"scope":"3v3 declared free-ball front/side/miss/original real wall/known PREPARE crossing/initial embedded shoe/fresh and stale AI observations; actual public entry/boot/World. No forced contacts/carrier. Does not verify opponent shin contact/foul order or natural tactical scheduling; wall shoe visual clipping remains outside this fix."},"\t"))
	game.pause_match();game.shutdown_audio();game.queue_free();game=null
	for i in 4:await process_frame
	quit(0 if ok else 1)
