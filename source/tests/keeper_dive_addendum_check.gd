extends SceneTree
## Publisher-only direct production-hook contact + empty-dive recovery fixture.
var game: Node3D
var host: Node
var keeper: Node3D
var evidence := ""
var checks: Array[Dictionary] = []
var floor_min := INF
var floor_samples := 0
var trace: Array = []
var output: String = ""
var body_contacts: Array = []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="): evidence = arg.trim_prefix("--evidence=")
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	call_deferred("run")

func check(label: String, ok: bool) -> void:
	checks.append({"label":label,"passed":ok})
	print("PASS " if ok else "FAIL ",label)

func events(kind: String) -> Array:
	return host.records.filter(func(row):return row.kind==kind)

func ticks(count: int) -> void:
	for i in count:
		await physics_frame
		if keeper.keeper_dive.active():
			var body: RefCounted = keeper.keeper_dive.body
			floor_min = minf(floor_min,float(body.last_floor)-keeper.keeper_dive.ground_y)
			floor_samples += 1
			if trace.size()<100:
				var state: Dictionary = host.states[keeper.get_instance_id()]
				trace.append({"frame":Engine.get_physics_frames(),"ball":game.ball.position,"velocity":game.ball.velocity,"keeper":keeper.position,"dive_phase":keeper.keeper_dive.phase,"host_phase":state.phase,"target":state.target_world,"pose":state.get("pose_debug",{}).duplicate(true),"floor_correction":body.floor_correction})

func stage(sign_side: float, height: float, grounded := false) -> void:
	game.ball.clear_control(true)
	host.records.clear()
	host.release_blocked_actor = 0
	for state: Dictionary in host.keeper_states: state.backpass_forbidden = false
	keeper.keeper_dive.cooldown = 0.0
	game.set_phase(game.Phase.PLAY)
	game.services.rules._second_touch_actor = -1
	game.services.rules._become_live() # Fixture only: production performs no bypass.
	for actor in game.players:
		actor.set_physics_process(false)
		actor.velocity = Vector3.ZERO
		actor.set_move_intent(Vector3.ZERO)
		actor.position = Vector3(22+actor.team*3,.002,actor.jersey)
	keeper.position = Vector3(0,.002,44)
	keeper.active = true
	keeper.facing = Vector3.FORWARD
	keeper.body_facing = Vector3.FORWARD
	keeper.face_target = Vector3.FORWARD
	keeper.refresh_pose(0)
	keeper.avatar.visual.global_rotation = Vector3.ZERO
	var time := .43
	var initial_y: float = height if grounded else height+.5*game.physics_profile.gravity_mps2*time*time
	game.ball.reset(keeper.position+Vector3(sign_side*1.05,initial_y,-.42-4.0*time))
	game.ball.set_held(false)
	game.ball.apply_impulse_ns((Vector3(0,0,4)-game.ball.velocity)*game.ball.mass_kg)
	game.services.rules.last_touch = {"actor_id":game.players.filter(func(a):return a.team!=keeper.team)[0].get_instance_id(),"team":1-keeper.team,"kind":"shot"}
	floor_min = INF
	floor_samples = 0

func run() -> void:
	if evidence.is_empty(): quit(2); return
	AudioServer.set_bus_mute(0,true)
	game = load("res://scenes/match.tscn").instantiate()
	game.test_mode = true
	game.ai_enabled = false
	root.add_child(game)
	await physics_frame
	game.start_match(false)
	game.contact_hub.body_contact.connect(func(event):
		if event.get("kind","")=="BODY_CONTACT":
			var actor=event.get("actor")
			body_contacts.append({"frame":Engine.get_physics_frames(),"action":event.get("action"),"actor":actor.name if is_instance_valid(actor) else "invalid","point":event.get("point"),"impulse":event.get("impulse"),"ball_contact":event.get("ball_contact",false)}))
	host = game.get_node("KeeperActions04")
	keeper = game.players.filter(func(a):return a.is_goalkeeper and a.team==0)[0]
	check("two actual GK drivers; no outfield body overlay",host.keeper_states.size()==2 and host.keeper_states.all(func(s):return s.has("dive_driver")))
	stage(1.0,.40)
	await ticks(210)
	check("low-mid incoming ball starts one full-body side dive",events("GK_DIVE_BEGIN").size()==1 and events("GK_DIVE_PUSH").size()==1 and events("GK_DIVE_LAND").size()==1)
	check("dive real hand path produces one contact result",events("GK_HAND_CONTACT").size()==1 and events("GK_PARRY_CONFIRMED").size()+events("GK_RETAIN_CONFIRMED").size()==1)
	check("dual-hand retain, if confirmed, releases once after body recovery",events("GK_RETAIN_CONFIRMED").is_empty() or events("GK_RELEASE_ACCEPTED").size()==1)
	check("C mesh influence bounds stay above turf during body/arm samples",floor_samples>0 and floor_min>=.014)
	check("contact dive restores upright and free ball",not keeper.keeper_dive.active() and keeper.down_state.state=="IDLE" and not game.ball.held and host.hand_owner==null and keeper.avatar.visual.global_basis.y.normalized().y>.99)
	var contact_events: Array = host.records.duplicate(true)
	stage(-1.0,.124,true)
	# Let the production host choose a low dive, then move the actual ball away
	# with one physical impulse. No body/ball position edits after launch.
	for i in 30:
		await ticks(1)
		if not events("GK_DIVE_BEGIN").is_empty(): break
	check("reachable low-ball trajectory naturally starts dive",events("GK_DIVE_BEGIN").size()==1)
	game.ball.apply_impulse_ns(Vector3.LEFT*9.0*game.ball.mass_kg)
	await ticks(180)
	check("empty dive does not manufacture hand contact or ownership",events("GK_HAND_CONTACT").is_empty() and events("GK_RETAIN_CONFIRMED").is_empty() and host.hand_owner==null)
	check("empty dive recovers once without stuck SLIDE",events("GK_DIVE_END").filter(func(row):return row.reason=="recovered").size()==1 and not keeper.keeper_dive.active() and keeper.down_state.state=="IDLE")
	check("empty dive also restores upright and floor protection",floor_samples>0 and floor_min>=.014 and keeper.avatar.visual.global_basis.y.normalized().y>.99)
	var passed := checks.all(func(row):return row.passed)
	DirAccess.make_dir_recursive_absolute(evidence)
	FileAccess.open(output if not output.is_empty() else evidence.path_join("KEEPER_DIVE_ADDENDUM.json"),FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"checks":checks,"contact_events":contact_events,"miss_events":host.records,"trace":trace,"body_contacts":body_contacts,"scope":"Production wiring + isolated physical trajectory fixture; not natural AI game/FPS/native visual acceptance"},"\t"))
	game.pause_match()
	game.shutdown_audio()
	game.queue_free()
	for i in 3: await process_frame
	quit(0 if passed else 1)
