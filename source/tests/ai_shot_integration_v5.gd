extends SceneTree
var game: Node
var checks: Array[Dictionary] = []
var samples: Array[Dictionary] = []
var contacts: Array[Dictionary] = []
var evidence := ""
var native := false
var frames := 0
var striker: Node3D
var case_id := ""

func _initialize() -> void:
	evidence = ProjectSettings.globalize_path("res://../verification")
	native = DisplayServer.get_name()!="headless"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="): evidence = arg.trim_prefix("--evidence=")
	call_deferred("run")

func key(code: int, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = down
	Input.parse_input_event(e)
	Input.flush_buffered_events()

func ticks(count: int, observe := false) -> void:
	for _i in count:
		await physics_frame
		frames += 1
		if observe and frames%6==0:
			samples.append({"case":case_id,"frame":frames,"state":game.services.rules.state_name(),"actor":striker.position,"velocity":striker.velocity,"facing":striker.facing,"gap":game.flat_distance(striker.position,game.ball.position),"ball":game.ball.position,"ball_velocity":game.ball.velocity,"owned":game.ball.carrier==striker,"can_kick":game.ball.can_kick(striker),"intent":striker.tactical_intent.duplicate(true),"pending":striker.pending_kick.duplicate(true),"foot":striker.foot.kind,"phase":striker.foot.phase,"hit":striker.foot.hit,"shoe":striker.foot.actual_contact.duplicate(),"weight_shift":striker.avatar.weight_shift})
			if native:
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(evidence.path_join("ai_shot_%s_%05d.png" % [case_id,frames]))

func check(label: String, ok: bool, details: Variant = null) -> void:
	checks.append({"check":label,"passed":ok,"details":details})
	print("PASS " if ok else "FAIL ",label," ",details if details!=null else "")

func fresh() -> void:
	if is_instance_valid(game):
		game.pause_match()
		game.shutdown_audio()
		OS.delay_msec(100)
		game.queue_free()
		game = null
		for _i in 4: await process_frame
	game = load("res://scenes/match.tscn").instantiate()
	game.test_mode = true
	root.add_child(game)
	game.contact_hub.contact_resolved.connect(func(e: Dictionary):
		if e.actor==striker: contacts.append({"case":case_id,"frame":frames,"kind":e.kind,"action":e.action,"surface":e.surface,"success":e.success,"before_velocity":e.before_velocity,"after_velocity":e.after_velocity,"point":e.point,"normal":e.normal,"reach_error":e.get("reach_error",-1.0)}))
	game.start_match(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	for _i in 2400:
		await ticks(1)
		if game.is_restart_taker(game.player): break
	key(KEY_Q,true)
	await ticks(40)
	key(KEY_Q,false)
	await ticks(655)

func fixture(team: int, moving: bool) -> void:
	# Only legal starting transforms/velocities, never ownership or rule writes.
	game.ball.clear_control()
	game.ball.set_held(false)
	for actor in game.agents:
		actor.position = Vector3(-27 if actor.jersey%2 else 27,.002,(actor.jersey-7)*3)
		actor.velocity = Vector3.ZERO
		actor.pending_kick.clear()
		actor.action_cooldown = 0
		actor.stop_requested = 0
		if actor.team==team and actor.jersey==9: striker = actor
	var attack: float = game.attack_direction(team)
	striker.position = Vector3(1.8 if team==0 else -1.8,.002,attack*39)
	striker.facing = Vector3(0,0,attack)
	striker.body_facing = striker.facing
	striker.face_target = striker.facing
	striker.target = striker.position
	striker.velocity = striker.facing*3.2 if moving else Vector3.ZERO
	for actor in game.agents:
		if actor.is_goalkeeper:
			actor.position = Vector3(-1.5 if actor.team!=team else 1.5,.002,-game.attack_direction(actor.team)*50.6)
	game.player.position = striker.position-striker.facing*6
	game.player.reset_view(0 if team==0 else PI)
	game.player.velocity = Vector3.ZERO
	game.ball.position = striker.position+striker.facing*.47+Vector3.UP*.111
	game.ball.previous_position = game.ball.position
	game.ball.velocity = striker.velocity
	game.ball.spin_rads = Vector3.ZERO
	game.ball.pickup_block = 0
	game.ball.touch_timer = 0
	game.sync_input_context()
	if native:
		var e := InputEventMouseMotion.new()
		e.relative = Vector2(0,(-.10-game.player.head.rot.x)/-game.player.head.mouse_sensitivity)
		Input.parse_input_event(e)
		Input.flush_buffered_events()

func run() -> void:
	for test_case in [{"team":0,"moving":false,"id":"blue_still"},{"team":1,"moving":false,"id":"yellow_still"},{"team":0,"moving":true,"id":"blue_moving"}]:
		striker = null
		case_id = test_case.id
		await fresh()
		fixture(test_case.team,test_case.moving)
		await ticks(600,true)
		var actual_shots: Array = contacts.filter(func(e): return e.case==case_id and e.action=="SHOT" and e.success)
		check(case_id+" actual shoe receive",contacts.any(func(e): return e.case==case_id and e.action=="RECEIVE" and e.success))
		check(case_id+" normal planner requests shot",samples.any(func(s): return s.case==case_id and s.intent.get("action","")=="SHOT"))
		check(case_id+" actual finite shoe shot",not actual_shots.is_empty(),actual_shots)
		check(case_id+" keeps 22 normal actors and World",game.players.size()==22 and game.physics_world.actors.size()==22 and game.ai_enabled)
	var passed: int = checks.filter(func(c): return c.passed).size()
	FileAccess.open(evidence.path_join("ai_shot_integration_"+("native" if native else "headless")+".json"),FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failed":checks.size()-passed,"checks":checks,"samples":samples,"contacts":contacts,"native":native,"scope":"Only starting physical transforms/velocities. No ball ownership, score, planner intent, contact event or rule state injected. Real automatic foot reception, original director decisions and finite foot kicks; all 22 actors/World/rules active."},"\t"))
	print("AI_SHOT_INTEGRATION ",passed,"/",checks.size())
	game.pause_match()
	game.shutdown_audio()
	OS.delay_msec(100)
	game.queue_free()
	game = null
	striker = null
	for _i in 4: await process_frame
	quit(0 if passed==checks.size() else 1)
