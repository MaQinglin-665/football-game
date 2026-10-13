extends SceneTree
## One explicitly seeded 22-player fixture after a genuine initial kickoff.
## After fixture setup, bodies/ball/AI/world/shoe/rules evolve without edits.
var game: Node
var frame := 0
var checks: Array[Dictionary] = []
var contacts: Array[Dictionary] = []
var trajectory: Array[Dictionary] = []
var wing: Node3D
var receiver: Node3D
var old_id := -1
var cover_id := -1
var pass_frame := -1

func _initialize() -> void:
	call_deferred("run")

func key(code: int, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func vector(v: Vector3) -> Array:
	return [v.x,v.y,v.z]

func check(label: String, ok: bool, details: Variant = null) -> void:
	checks.append({"label":label,"ok":ok,"detail":details})
	print("PASS " if ok else "FAIL ",label)

func sample() -> void:
	var debug: Dictionary = game.tactical_director.defense_debug_snapshot()
	var actors := []
	for id in range(game.players.size()):
		var actor: Node3D = game.players[id]
		var task: Dictionary = debug.tasks.get(id,{})
		actors.append({"id":id,"name":String(actor.name),"jersey":actor.jersey,"team":actor.team,"role":actor.role,"human":actor.is_human,"position":vector(actor.position),"velocity":vector(actor.velocity),"target":vector(actor.position if actor.is_human else actor.target),"task":String(task.get("task","")),"task_target":vector(task.get("target",actor.position)),"target_id":int(task.get("target_id",-1)),"generation":int(task.get("generation",-1))})
	trajectory.append({"frame":frame,"time":frame/120.0,"state":game.services.rules.state_name(),"ball":vector(game.ball.position),"ball_velocity":vector(game.ball.velocity),"carrier_id":game.players.find(game.ball.carrier) if is_instance_valid(game.ball.carrier) else -1,"actors":actors,"task_clock":debug.clock})

func run() -> void:
	game = load("res://scenes/match.tscn").instantiate()
	game.test_mode = true # Declared fixture; avoids headless focus pause only.
	root.add_child(game)
	for _i in 5: await process_frame
	game.hud.menu.get_node("StartMatch").pressed.emit()
	for _i in 3600:
		await physics_frame
		if game.services.rules.state==game.Rules.State.RESTART_READY: break
	key(KEY_Q,true)
	for _i in 50: await physics_frame
	key(KEY_Q,false)
	for _i in 1200:
		await physics_frame
		if game.services.rules.state==game.Rules.State.LIVE: break
	check("legal_initial_kickoff_precedes_fixture",game.services.rules.state==game.Rules.State.LIVE)
	if game.services.rules.state!=game.Rules.State.LIVE:
		await finish()
		return
	var blue := {1:Vector3(0,0,49),3:Vector3(-22,0,28),4:Vector3(-10,0,34),5:Vector3(10,0,34),2:Vector3(22,0,28),14:Vector3(1,0,8),8:Vector3(-4,0,-8),7:Vector3(-26,0,-8),10:Vector3(-3,0,-21),9:Vector3(-5,0,-18),11:Vector3(26,0,-4)}
	# Yellow local left/right rotates with its attack direction: #2 guards
	# negative world x here; #3 and #7 occupy positive world x.
	var yellow := {1:Vector3(0,0,-49),3:Vector3(25,0,-29),4:Vector3(10,0,-34),5:Vector3(-10,0,-34),2:Vector3(-24,0,-12),14:Vector3(-14,0,-14),8:Vector3(0,0,-21),7:Vector3(25,0,5),10:Vector3(10,0,-18),9:Vector3(3,0,8),11:Vector3(-25,0,5)}
	for actor in game.players:
		actor.position = (blue if actor.team==0 else yellow)[actor.jersey]+Vector3(0,.01,0)
		actor.velocity = Vector3.ZERO
		actor.set_move_intent(Vector3.ZERO)
		actor.foot.cancel()
		actor.action_cooldown = 1.0
		actor.tackle_cooldown = 0.0
		if not actor.is_human:
			actor.pending_kick.clear()
			actor.target = actor.position
			actor.facing = Vector3.FORWARD if actor.team==0 else Vector3.BACK
			actor.body_facing = actor.facing
			actor.face_target = actor.facing
		if actor.team==0 and actor.jersey==7: wing = actor
		if actor.team==0 and actor.jersey==8: receiver = actor
	game.pass_receiver = null
	game.pass_receiver_timer = 0
	game.tactical_director.reset()
	wing.facing = Vector3.RIGHT
	wing.body_facing = Vector3.RIGHT
	game.ball.reset(wing.position+Vector3(.50,0,0))
	game.ball.take(wing) # Initial ownership is seeded, never claimed as a touch.
	game.tactics_bridge.refresh_now()
	game.tactics_bridge.clock = .20
	wing.target = wing.position
	wing.face_target = Vector3.RIGHT
	wing.action_cooldown = 0
	# Fixture setup ends here. No more transform, velocity or rule-clock edits.
	var first: Dictionary = game.tactical_director.defense_debug_snapshot()
	for task in first.tasks.values():
		if int(task.team)==1 and task.task=="PRESS": old_id = int(task.owner)
		if int(task.team)==1 and task.task=="COVER": cover_id = int(task.owner)
	check("all_22_ai_world_shoe_rules_active",game.players.size()==22 and game.players.all(func(p): return p.visible and p.is_physics_processing() and (p.is_human or p.active)) and game.ai_enabled and game.physics_world.is_physics_processing() and game.services.rules.state==game.Rules.State.LIVE,{"human_jersey":game.player.jersey,"human_team":game.player.team,"ai_enabled":game.ai_enabled})
	check("wing_start_has_one_pressure_and_cover",old_id>=0 and cover_id>=0 and old_id!=cover_id,{"presser":old_id,"cover":cover_id})
	game.contact_hub.contact_resolved.connect(func(event: Dictionary):
		if not event.get("success",false): return
		var actor: Node3D = event.actor
		contacts.append({"frame":frame,"id":game.players.find(actor),"name":String(actor.name),"action":String(event.get("action","")),"receiver_id":game.players.find(event.get("receiver",null)),"shoe":actor.foot.actual_contact.duplicate(true),"point":vector(event.get("point",Vector3.ZERO)),"ball":vector(game.ball.position),"facing":vector(actor.facing)})
		if actor==wing and String(event.get("action",""))=="PASS" and pass_frame<0: pass_frame = frame)
	sample()
	for _i in 12:
		await physics_frame
		frame += 1
		if frame%6==0: sample()
	var semantic := {"action":"pass_ground","direction":Vector3.RIGHT,"power":.42,"elevation_deg":0.0,"spin":Vector3.ZERO,"receiver_id":game.players.find(receiver),"tactical_action":"PASS"}
	var accepted: bool = game.request_actor_kick(wing,semantic,receiver)
	check("real_lateral_pass_request_accepted",accepted,{"can_kick":game.ball.can_kick(wing),"carrier":game.players.find(game.ball.carrier),"foot_phase":wing.foot.phase})
	for _i in 240:
		await physics_frame
		frame += 1
		if frame%6==0: sample()
		if pass_frame>=0 and frame-pass_frame>=144: break
	sample()
	var final_debug: Dictionary = game.tactical_director.defense_debug_snapshot()
	var exits := []
	for event in final_debug.events:
		if event.event=="EXIT" and int(event.owner)==old_id and event.task=="PRESS": exits.append(event)
	var valid_passes := contacts.filter(func(c): return c.id==game.players.find(wing) and c.action=="PASS" and c.receiver_id==game.players.find(receiver) and c.shoe.get("valid",false) and float(c.shoe.get("reach_error",INF))<.01)
	check("pass_completed_by_actual_shoe_contact",pass_frame>=0 and not valid_passes.is_empty(),contacts)
	var released: bool = not exits.is_empty() and exits[0].reason=="ball_passed"
	check("old_pressure_exits_on_physical_release",released,exits)
	var recovered := false
	var no_reclaim := true
	var cover_safe := true
	var cover_body_safe := true
	var central_min := 22
	var pressure_max := 0
	var exit_sample: Dictionary = {}
	for row in trajectory:
		if pass_frame<0 or int(row.frame)<pass_frame: continue
		var ball := Vector3(row.ball[0],row.ball[1],row.ball[2])
		var central := 0
		var press_count := 0
		for actor in row.actors:
			if int(actor.team)!=1: continue
			var point := Vector3(actor.position[0],actor.position[1],actor.position[2])
			if actor.task=="PRESS": press_count += 1
			if actor.role!="goalkeeper" and absf(point.x)<15 and point.z<ball.z-1: central += 1
			if int(actor.id)==old_id:
				if actor.task=="RECOVER" and exit_sample.is_empty(): exit_sample = {"point":point,"target":Vector3(actor.target[0],actor.target[1],actor.target[2]),"frame":row.frame}
				if released and float(row.task_clock)>=float(exits[0].time) and float(row.task_clock)<float(exits[0].time)+.8: no_reclaim = no_reclaim and actor.task!="PRESS"
			if int(actor.id)==cover_id and actor.task=="COVER":
				var target := Vector3(actor.target[0],actor.target[1],actor.target[2])
				cover_safe = cover_safe and target.z<ball.z-3 and Vector2(target.x-ball.x,target.z-ball.z).length()>4.0
				cover_body_safe = cover_body_safe and point.z<ball.z-2 and Vector2(point.x-ball.x,point.z-ball.z).length()>3.0
		pressure_max = maxi(pressure_max,press_count)
		central_min = mini(central_min,central)
	if not exit_sample.is_empty():
		var actor: Node3D = game.players[old_id]
		var along: float = Vector3(actor.position.x-exit_sample.point.x,0,actor.position.z-exit_sample.point.z).dot(Vector3(exit_sample.target.x-exit_sample.point.x,0,exit_sample.target.z-exit_sample.point.z).normalized())
		recovered = along>.25
		check("old_presser_physically_moves_back_toward_role",recovered,{"exit":exit_sample,"end":vector(actor.position),"along_m":along})
	else: check("old_presser_physically_moves_back_toward_role",false)
	check("exited_presser_not_immediately_reclaimed",released and no_reclaim)
	check("cover_goal_side_target_stays_out_of_ball_chase",cover_safe)
	check("cover_actual_body_stays_goal_side",cover_body_safe)
	check("central_actual_positions_remain_protected",central_min>=3,{"minimum":central_min})
	check("one_primary_presser_throughout",pressure_max<=1,{"maximum":pressure_max})
	await finish()

func finish() -> void:
	var passed := 0
	for item in checks:
		if item.ok: passed += 1
	var report := {"fixture":true,"native_screenshot":false,"initial_fixture_only":true,"post_fixture_transform_edits":0,"passed":passed,"total":checks.size(),"checks":checks,"pass_frame":pass_frame,"old_presser":old_id,"cover_id":cover_id,"contacts":contacts,"trajectory":trajectory,"debug":game.tactical_director.defense_debug_snapshot()}
	var path := ProjectSettings.globalize_path("res://../verification/defense_physical.json")
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("DEFENSE_PHYSICAL ",passed,"/",checks.size()," ",path)
	game.pause_match()
	game.shutdown_audio()
	game.queue_free()
	game = null
	wing = null
	receiver = null
	for _i in 4: await process_frame
	quit(0 if passed==checks.size() else 1)
