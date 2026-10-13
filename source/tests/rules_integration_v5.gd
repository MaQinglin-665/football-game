extends SceneTree
var game: Node
var checks: Array[Dictionary] = []
var events: Array[Dictionary] = []
var evidence := ""
var native := false
var frames := 0

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

func mouse(down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	Input.parse_input_event(e)
	Input.flush_buffered_events()

func look(point: Vector3) -> void:
	var direction := Vector3(point.x-game.player.position.x,0,point.z-game.player.position.z)
	if direction.length()<.05: return
	var diff := angle_difference(game.player.rotation.y,atan2(-direction.x,-direction.z))
	if native:
		var e := InputEventMouseMotion.new()
		e.relative = Vector2(-diff/game.player.head.mouse_sensitivity,0)
		Input.parse_input_event(e)
	else:
		var e := InputEventJoypadMotion.new()
		e.axis = JOY_AXIS_RIGHT_X
		e.axis_value = clampf(-diff/.35,-1,1)
		Input.parse_input_event(e)
	Input.flush_buffered_events()

func ticks(count: int) -> void:
	for _i in count:
		await physics_frame
		frames += 1

func check(label: String, ok: bool, details: Variant = null) -> void:
	checks.append({"check":label,"passed":ok,"details":details})
	print("PASS " if ok else "FAIL ",label," ",details if details!=null else "")

func capture(label: String) -> void:
	if not native: return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(evidence.path_join("rules_"+label+".png"))

func fresh_live() -> void:
	key(KEY_W,false)
	key(KEY_Q,false)
	key(KEY_SPACE,false)
	mouse(false)
	var joy := InputEventJoypadMotion.new()
	joy.axis = JOY_AXIS_RIGHT_X
	joy.axis_value = 0
	Input.parse_input_event(joy)
	if is_instance_valid(game):
		game.pause_match()
		game.shutdown_audio()
		# Headless fixed-fps frames may outrun the separate real-time mixer.
		OS.delay_msec(100)
		game.queue_free()
		game = null
		for _i in 4: await process_frame
	game = load("res://scenes/match.tscn").instantiate()
	game.test_mode = true
	root.add_child(game)
	game.services.rules_event.connect(func(e: Dictionary): events.append(e.duplicate(true)))
	game.start_match(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	for _i in 2400:
		await ticks(1)
		if game.is_restart_taker(game.player): break
	key(KEY_Q,true)
	await ticks(40)
	key(KEY_Q,false)
	await ticks(55)
	check("fresh match enters LIVE by actual kickoff",game.phase==game.Phase.PLAY)
	# Let a different real player touch the kickoff before starting a new
	# physical fixture; otherwise its human receiver is an illegal second touch.
	await ticks(600)

func fixture(at: Vector3, yaw: float) -> void:
	# Starting positions only. No disabled AI, rule state, contact or physics.
	game.ball.clear_control()
	game.ball.set_held(false)
	game.player.position = at
	game.player.velocity = Vector3.ZERO
	game.player.reset_view(yaw)
	game.player.action_cooldown = 0
	game.player.stop_requested = 0
	game.player.sole_stopped = false
	game.ball.position = at+game.player.facing*.5+Vector3.UP*.111
	game.ball.previous_position = game.ball.position
	game.ball.velocity = Vector3.ZERO
	game.ball.spin_rads = Vector3.ZERO
	game.ball.pickup_block = 0
	game.ball.touch_timer = 0
	for i in game.agents.size():
		var actor: Node3D = game.agents[i]
		actor.position = Vector3(-28.0 if i%2 else 28.0,.002,-42+4.0*i)
		actor.velocity = Vector3.ZERO
		actor.target = actor.position
		actor.pending_kick.clear()
	game.sync_input_context()

func receive() -> bool:
	key(KEY_SPACE,true)
	await ticks(1)
	key(KEY_SPACE,false)
	await ticks(28)
	return game.ball.carrier==game.player

func shot() -> void:
	mouse(true)
	await ticks(50)
	mouse(false)
	await ticks(80)

func wait_live(limit := 12000) -> bool:
	var gesture := 0
	for i in limit:
		await ticks(1)
		if gesture>0:
			gesture -= 1
			if gesture==0: key(KEY_Q,false)
		if i%24==0:
			key(KEY_W,false)
			var restart: Dictionary = game.services.rules.restart
			if int(restart.get("taker_id",-1))==game.player.get_instance_id():
				if game.is_restart_taker(game.player):
					if gesture==0 and game.player.action_cooldown<=0:
						look(game.ball.position+restart.get("inward",Vector3.FORWARD)*10)
						key(KEY_Q,true)
						gesture = 42
				elif restart.has("taker_target"):
					look(restart.taker_target)
					if game.flat_distance(game.player.position,restart.taker_target)>.28: key(KEY_W,true)
		if game.phase==game.Phase.PLAY:
			key(KEY_W,false)
			return true
	print("RESTART_STALL ",game.services.rules.restart," violations=",game.services.rules.restart_violations())
	for actor in game.players:
		print("STALL_ACTOR ",JSON.stringify({"name":actor.name,"id":actor.get_instance_id(),"team":actor.team,"jersey":actor.jersey,"position":actor.position,"velocity":actor.velocity,"move_intent":actor.move_intent,"target":actor.target if not actor.is_human else Vector3.ZERO,"invalid_normals":actor.invalid_normal_contacts}))
	return false

func run() -> void:
	await fresh_live()
	fixture(Vector3(2.65,.002,-49.0),0)
	for actor in game.agents:
		if actor.team==1 and actor.is_goalkeeper: actor.position = Vector3(-3,.002,-50.7)
	check("goal fixture receives through actual shoe",await receive())
	await shot()
	check("actual human shot crosses full goal sphere once",game.stats.shots==1 and game.scores==[1,0],{"score":game.scores,"shot":game.stats.shots,"ball":game.ball.position})
	await capture("goal")
	var dead_clock: float = game.services.rules.half_elapsed
	var original: Vector3 = game.player.position
	key(KEY_A,true)
	await ticks(80)
	key(KEY_A,false)
	check("goal celebration allows human movement",game.player.position.distance_to(original)>.5)
	check("goal celebration stops match clock",absf(game.services.rules.half_elapsed-dead_clock)<.02)
	await capture("goal_free_motion")
	check("goal returns to LIVE through actual AI restart",await wait_live(),game.services.rules.restart)
	check("score does not double count celebration/restart",game.scores==[1,0],game.scores)
	await capture("after_goal_restart")

	await fresh_live()
	fixture(Vector3(32.9,.002,0),-PI*.5)
	check("throw fixture receives through actual shoe",await receive())
	await shot()
	check("actual sideline crossing awards opposing throw",String(game.services.rules.restart.get("kind",""))=="throw_in" and int(game.services.rules.restart.get("team",-1))==1,game.services.rules.restart)
	var before_passes: int = game.stats.passes
	key(KEY_Q,true)
	await ticks(30)
	key(KEY_Q,false)
	await ticks(5)
	check("non-taker cannot kick held throw ball",game.stats.passes==before_passes)
	await capture("throw_setup")
	check("throw actually enters field and resumes LIVE",await wait_live(),game.services.rules.restart)
	check("out does not teleport all 22 into kickoff formation",game.agents.any(func(a): return a.position.distance_to(a.home)>12))

	await fresh_live()
	fixture(Vector3(18,.002,-50.8),0)
	check("goal-kick fixture receives through actual shoe",await receive())
	await shot()
	check("attacker last touch over end line gives opponent goal kick",String(game.services.rules.restart.get("kind",""))=="goal_kick" and int(game.services.rules.restart.get("team",-1))==1,game.services.rules.restart)
	check("goal kick physically resumes LIVE",await wait_live(),game.services.rules.restart)
	await capture("goal_kick_live")

	await fresh_live()
	fixture(Vector3(18,.002,50.8),PI)
	check("corner fixture receives through actual shoe",await receive())
	await shot()
	check("defender last touch over own end line gives opponent corner",String(game.services.rules.restart.get("kind",""))=="corner" and int(game.services.rules.restart.get("team",-1))==1,game.services.rules.restart)
	check("corner physically resumes LIVE",await wait_live(),game.services.rules.restart)
	await capture("corner_live")
	check("all actors remain finite and World registered",game.players.size()==22 and game.physics_world.actors.size()==22 and game.players.all(func(a): return a.position.is_finite() and a.velocity.is_finite()))
	var passed: int = checks.filter(func(c): return c.passed).size()
	FileAccess.open(evidence.path_join("rules_integration_"+("native" if native else "headless")+".json"),FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failed":checks.size()-passed,"checks":checks,"events":events,"frames":frames,"native":native,"scope":"Real input receive/shot, full sphere boundary detection and real physical restart; all 22 AI and swept World stay active. Starting positions only are fixtures. Native uses mouse, headless joystick look."},"\t"))
	print("RULES_INTEGRATION ",passed,"/",checks.size())
	game.pause_match()
	game.shutdown_audio()
	OS.delay_msec(100)
	game.queue_free()
	game = null
	for _i in 4: await process_frame
	quit(0 if passed==checks.size() else 1)
