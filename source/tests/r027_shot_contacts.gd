extends "res://tests/integration_checks.gd"
var current:Dictionary={}
var results:Array=[]
var camera:Camera3D
func run()->void:
	game=load("res://scenes/match.tscn").instantiate();game.test_mode=true;root.add_child(game)
	await ticks(5);game.start_match(false);await ticks(5)
	game.tactics_bridge.set_physics_process(false)
	game.services.rules.state=game.Rules.State.LIVE;game._sync_rule_phase()
	for actor in game.players:
		actor.set_physics_process(false);actor.foot.cancel("fixture");actor.velocity=Vector3.ZERO;actor.set_move_intent(Vector3.ZERO);actor.position=Vector3(25+actor.team*2,.002,20+actor.jersey*.1)
	camera=Camera3D.new();root.add_child(camera);camera.fov=48
	if native:camera.current=true
	game.contact_hub.contact_resolved.connect(func(e):
		if not current.is_empty() and e.get("actor")==current.actor and e.get("action")=="SHOT" and e.get("success",false):
			var actor:Node3D=current.actor
			current.contacts.append({"side":actor.foot.side,"surface":actor.foot.surface,"sequence":actor.foot.sequence,"ball":game.ball.position,"shoe":actor.foot.toe_world,"gap":actor.foot.toe_world.distance_to(game.ball.position),"reach_error":actor.foot.actual_contact.get("reach_error",-1),"velocity":game.ball.velocity,"elapsed":actor.foot.elapsed})
	)
	var ai:Node3D=game.players[2]
	for spec in [
		{"name":"placed_left","offset":Vector3(-.23,.11,-.40),"aim":Vector3.FORWARD,"side":-1,"power":.8,"human":true,"style":"placed"},
		{"name":"placed_right","offset":Vector3(.23,.11,-.40),"aim":Vector3.FORWARD,"side":1,"power":.8,"style":"placed"},
		{"name":"curve_inside","offset":Vector3(.23,.11,-.40),"aim":Vector3.FORWARD,"side":1,"power":.8,"style":"curve","spin":-1.0,"human":true},
		{"name":"curve_outside","offset":Vector3(.23,.11,-.40),"aim":Vector3.FORWARD,"side":1,"power":.8,"style":"curve","spin":1.0},
		{"name":"placed_escape","offset":Vector3(.23,.11,-.40),"aim":Vector3.FORWARD,"side":1,"power":.8,"style":"placed","escape":true,"human":true}]:
		var actor:Node3D=game.player if spec.get("human",false) else ai
		for other in [game.player,ai]:
			other.foot.cancel("fixture");other.velocity=Vector3.ZERO;other.set_move_intent(Vector3.ZERO);other.position=Vector3(25,.002,25)
		game.ball.clear_control();game.ball.set_held(true)
		await physics_frame;await physics_frame
		actor.position=Vector3(0,.002,5);actor.facing=Vector3.FORWARD;actor.body_facing=Vector3.FORWARD;actor.action_cooldown=0;actor.stop_requested=0
		if actor.is_human:actor.reset_view(0)
		else:actor.face_target=Vector3.FORWARD;actor.pending_kick.clear()
		actor.avatar.visual.global_rotation=Vector3.ZERO # Controlled fixture orientation, before the gesture.
		actor.avatar._plants.clear();actor.avatar._last_contacts.clear();actor.avatar._last_ankles.clear();actor.avatar._last_local_ankles.clear();actor.avatar.invalidate_pose_snapshot();actor.refresh_pose(1.0/120)
		for warm in 35:actor.refresh_pose(1.0/120)
		game.ball.clear_control();game.ball.set_held(false);game.ball.reset(actor.position+spec.offset);game.ball.carrier=actor;game.ball.possession_age=.5;game.ball.pickup_block=0;game.ball.touch_timer=2.0
		if spec.get("moving",false):
			actor.velocity=Vector3.FORWARD*3.0;actor.set_move_intent(Vector3.FORWARD*.54);game.ball.velocity=actor.velocity;game.ball.spin_rads=Vector3.UP.cross(game.ball.velocity)/game.ball.radius
		camera.position=actor.position+Vector3(2,1.1,2.2);camera.look_at(actor.position+Vector3(0,.60,-.18))
		if native:
			if spec.name in ["human_left","moving_left"]:game.player.camera.current=true
			else:camera.current=true
		current={"name":spec.name,"actor":actor,"contacts":[],"samples":[]}
		game.input_bridge.sync_context()
		var accepted:bool=game.request_actor_kick(actor,{"action":"shoot_curve" if spec.get("style","")=="curve" else "shoot_straight","style":spec.get("style","straight"),"direction":spec.aim,"power":spec.get("power",.25),"elevation_deg":34.0 if spec.get("loft",false) else 0.0,"spin":Vector3.UP*float(spec.get("spin",0.0))})
		current.accepted=accepted
		current.initial={"position":actor.position,"facing":actor.facing,"visual":actor.avatar.visual.global_transform}
		if spec.get("escape",false):game.ball.apply_impulse_ns(Vector3.FORWARD*5.16) # Simulated opponent impact after scheduling, not a ball relocation.
		for i in 58:
			await physics_frame
			actor.refresh_pose(1.0/120)
			if spec.name=="moving_left" and i==13:
				print("MOVING_DEBUG ",{"root":actor.position,"velocity":actor.velocity,"target":actor.foot.pose_request(),"visual":actor.avatar.visual.global_transform,"active":actor.avatar.active_socket,"hip":actor.avatar.skeleton.to_global(actor.avatar.skeleton.get_bone_global_pose(actor.avatar.skeleton.find_bone("thigh.L")).origin),"support":actor.avatar.planted_support})
			if not actor.foot.idle():
				var sk:Skeleton3D=actor.avatar.skeleton
				current.samples.append({"t":actor.foot.elapsed,"phase":actor.foot.phase,"side":actor.foot.side,"surface":actor.foot.surface,"point":actor.foot.toe_world,"failure":actor.foot.contact_failure,"hit":actor.foot.hit,"ball":game.ball.position,"hip":sk.get_bone_pose_rotation(sk.find_bone("hips")),"knee":sk.get_bone_pose_rotation(sk.find_bone("shin."+("L" if actor.foot.side<0 else "R"))),"support":actor.avatar.planted_support.get("valid",false)})
			if native and i in [2,5,9,13,19,27]:await capture(spec.name+"_%02d"%i)
		if spec.get("reject",false):check(spec.name,not accepted and current.contacts.is_empty())
		elif spec.get("escape",false):check(spec.name,accepted and current.contacts.is_empty())
		else:
			check(spec.name+" real single contact",accepted and current.contacts.size()==1,{"accepted":accepted,"contacts":current.contacts,"failure":actor.foot.contact_failure})
			if current.contacts.size()==1:
				var c:Dictionary=current.contacts[0]
				check(spec.name+" choice direction reach",c.side==spec.side and c.gap<=game.ball.radius+.065 and (c.velocity as Vector3).normalized().dot(spec.aim)>.7,c)
		current.final={"position":actor.position,"trace":actor.foot.action_trace,"actual":actor.foot.actual_contact,"visual":actor.avatar.visual.global_transform}
		current.erase("actor");results.append(current.duplicate(true));current={}
		FileAccess.open(evidence+"/r027_shot_contacts.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"results":results,"complete":false},"  "))
	game.ball.clear_control();game.ball.set_held(false)
	for direction in [Vector3.FORWARD,Vector3(1,0,-1).normalized()]:
		game.ball.reset(Vector3(0,.1101,0));game.ball.velocity=direction*4;game.ball.spin_rads=Vector3.UP.cross(game.ball.velocity)/game.ball.radius;game.ball.grounded=true;game.ball.visual.quaternion=Quaternion.IDENTITY
		var origin:Vector3=game.ball.position;game.ball.step_physics(.05)
		var travel:Vector3=game.ball.position-origin;travel.y=0
		var expected:=Quaternion(Vector3.UP.cross(travel).normalized(),travel.length()/game.ball.radius)
		check("visual rolling follows actual displacement "+str(direction),game.ball.visual.quaternion.angle_to(expected)<.025,{"travel":travel,"angle_error":game.ball.visual.quaternion.angle_to(expected)})
	FileAccess.open(evidence+"/r027_shot_contacts.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"results":results,"scope":"controlled initial possession fixtures, real shoe movement and one physical impulse; no mid-action ball relocation; not natural AI proof"},"  "))
	game.shutdown_audio();game.queue_free();game=null;camera.queue_free();await process_frame;await process_frame;quit(1 if checks.any(func(c):return not c.passed) else 0)
