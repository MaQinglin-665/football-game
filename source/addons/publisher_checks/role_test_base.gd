extends Node
var game: Node
var checks: Array[Dictionary] = []
var samples: Array[Dictionary] = []
var contacts: Array[Dictionary] = []
var frames := 0
var captures := 0
var native := false
var evidence := ""

var root: Window:
	get: return get_tree().root
var physics_frame: Signal:
	get: return get_tree().physics_frame
var process_frame: Signal:
	get: return get_tree().process_frame
func quit(code: int) -> void:
	get_tree().quit(code)
func _initialize_unused() -> void:
	native = DisplayServer.get_name()!="headless"
	evidence = ProjectSettings.globalize_path("res://../verification")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="): evidence = arg.trim_prefix("--evidence=")
	call_deferred("run")

func check(label: String, ok: bool, details: Variant = null) -> void:
	checks.append({"check":label,"passed":ok,"details":details})
	print("PASS " if ok else "FAIL ",label," ",details if details!=null else "")

func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func mouse(button: int, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func ticks(count: int, interval := 0, tag := "play") -> void:
	for i in count:
		await physics_frame
		frames += 1
		if frames%12==0:
			samples.append({"frame":frames,"rules":game.services.rules.state_name(),"ball":game.ball.position,"velocity":game.ball.velocity,"spin":game.ball.spin_rads,"human":game.player.position,"foot":game.player.foot.kind,"phase":game.player.foot.phase,"hit":game.player.foot.hit,"shoe":game.player.foot.actual_contact})
		if native and interval>0 and i%interval==0: await capture(tag)

func capture(tag: String) -> void:
	if not native: return
	await process_frame
	await RenderingServer.frame_post_draw
	captures += 1
	root.get_texture().get_image().save_png(evidence.path_join("A_%03d_%s.png" % [captures,tag]))

func release_inputs() -> void:
	for code in [KEY_W,KEY_A,KEY_S,KEY_D,KEY_SHIFT,KEY_CTRL,KEY_SPACE,KEY_C,KEY_Q,KEY_F,KEY_X,KEY_Z,KEY_E]: key(code,false)
	mouse(MOUSE_BUTTON_LEFT,false)
	mouse(MOUSE_BUTTON_RIGHT,false)

func fixture() -> void:
	# Reproducible starting positions; normal 22-player AI and swept World stay on.
	release_inputs()
	game.ball.clear_control()
	game.ball.set_held(false)
	game.player.position = Vector3(0,.002,8)
	game.player.velocity = Vector3.ZERO
	game.player.reset_view(0)
	game.player.action_cooldown = 0
	game.player.tackle_cooldown = 0
	game.player.stop_requested = 0
	game.player.sole_stopped = false
	game.ball.position = Vector3(0,.113,7.42)
	game.ball.previous_position = game.ball.position
	game.ball.velocity = Vector3.ZERO
	game.ball.spin_rads = Vector3.ZERO
	game.ball.pickup_block = 0
	game.ball.touch_timer = 0
	game.ball.control_mode = "LOOSE"
	for i in game.agents.size():
		var agent: Node3D = game.agents[i]
		agent.position = Vector3(-28.0 if i%2 else 28.0,.002,-43.0+4.2*i)
		agent.velocity = Vector3.ZERO
		agent.target = agent.position
	game.sync_input_context()

func receive() -> bool:
	fixture()
	key(KEY_SPACE,true)
	await ticks(1)
	key(KEY_SPACE,false)
	await ticks(25)
	return game.ball.carrier==game.player

func kick(button: int, modifiers: Array = [], hold := 45) -> bool:
	for code in modifiers: key(code,true)
	if button==KEY_Q: key(KEY_Q,true)
	else: mouse(button,true)
	await ticks(hold)
	if button==KEY_Q: key(KEY_Q,false)
	else: mouse(button,false)
	await ticks(40,5,"kick")
	for code in modifiers: key(code,false)
	return game.ball.carrier!=game.player and not game.ball.last_kick_intent.is_empty()

func run() -> void:
	game = load("res://scenes/match.tscn").instantiate()
	game.test_mode = true
	root.add_child(game)
	game.contact_hub.contact_resolved.connect(func(event: Dictionary): contacts.append(event.duplicate()))
	await ticks(6)
	check("22 actors; fixed human blue #10 AM",game.players.size()==22 and game.player.jersey==10 and game.player.role=="attacking_midfielder")
	check("one GK per side",game.agents.filter(func(a): return a.is_goalkeeper and a.team==0).size()==1 and game.agents.filter(func(a): return a.is_goalkeeper and a.team==1).size()==1)
	check("120Hz; sole swept world",Engine.physics_ticks_per_second==120 and not game.player.auto_step and not game.ball.auto_step and game.physics_world.actors.size()==22)
	check("correct shape/mass",game.player.collision_mask==7 and is_equal_approx(game.physics_profile.player_radius_m,.28) and is_equal_approx(game.ball.mass_kg,.43))
	check("new complete skeleton; old legs absent",game.player.avatar.skeleton.get_bone_count()==32 and game.player.get_node_or_null("FootStance")==null)
	await capture("menu")
	game.start_match(false)
	for _i in 2400:
		await ticks(1)
		if game.is_restart_taker(game.player): break
	check("kickoff physically reaches legal readiness",game.is_restart_taker(game.player),game.services.rules.restart_violations())
	key(KEY_Q,true)
	await ticks(50)
	check("charge has no fake ball impulse",game.ball.velocity.length()<.01 and game.stats.passes==0)
	key(KEY_Q,false)
	await ticks(55,5,"kickoff")
	check("real shoe kickoff starts live play",game.phase==game.Phase.PLAY and game.stats.passes==1,game.player.foot.last_result)
	await ticks(600)
	check("AI receives through contact",game.tactical_director.contact_counts.receives>0,game.tactical_director.contact_counts)
	check("two team tactical observations",game.tactics_bridge.team_observation.size()==2)
	check("Space actual-foot receive",await receive(),game.player.foot.actual_contact)
	key(KEY_CTRL,true)
	key(KEY_W,true)
	var before: Vector3 = game.player.position
	await ticks(180,15,"close")
	key(KEY_W,false)
	key(KEY_CTRL,false)
	check("close dribble moves with finite acceleration",game.player.position.distance_to(before)>1.5 and game.player.velocity.length()<4,game.player.position-before)
	check("close dribble real contacts",contacts.any(func(e): return e.actor==game.player and e.get("action","")=="CLOSE" and e.success))
	var gap: float = game.flat_distance(game.player.position,game.ball.position)
	check("close dribble remains within control range",gap<1.5,gap)
	key(KEY_SPACE,true)
	await ticks(1)
	key(KEY_SPACE,false)
	await ticks(55,5,"stop")
	check("stop actual SOLE contact",contacts.any(func(e): return e.actor==game.player and e.get("action","")=="STOP" and e.surface=="SOLE" and e.success))
	check("stop slows ball",Vector2(game.ball.velocity.x,game.ball.velocity.z).length()<1,game.ball.velocity)
	await receive()
	key(KEY_S,true)
	await ticks(110,11,"retreat")
	key(KEY_S,false)
	check("retreat actual sole pull",contacts.any(func(e): return e.actor==game.player and e.get("action","")=="PULL" and e.surface=="SOLE" and e.success))
	check("retreat ball stays forward",Vector3(game.ball.position-game.player.position).dot(game.player.facing)>-.08,game.ball.position-game.player.position)
	check("retreat remains in control",game.ball.carrier==game.player and game.flat_distance(game.player.position,game.ball.position)<1.1,game.flat_distance(game.player.position,game.ball.position))
	await receive()
	check("ground pass release",await kick(KEY_Q,[],30) and game.ball.last_kick_intent.action=="pass_ground")
	await receive()
	check("actual shot mapped speed",await kick(MOUSE_BUTTON_LEFT,[],50) and game.ball.velocity.length()>12,game.ball.velocity.length())
	await receive()
	check("high pass independent loft",await kick(KEY_Q,[KEY_F],40) and game.ball.last_kick_intent.action=="pass_high" and float(game.ball.last_kick_intent.elevation_deg)>0,game.ball.last_kick_intent)
	await receive()
	await kick(MOUSE_BUTTON_LEFT,[KEY_X],50)
	var right_spin: float = game.ball.spin_rads.y
	var right_x: float = game.ball.position.x
	check("right curve negative angular Y",right_spin<-.5,right_spin)
	await receive()
	await kick(MOUSE_BUTTON_LEFT,[KEY_Z],50)
	check("left curve positive angular Y",game.ball.spin_rads.y>.5,game.ball.spin_rads.y)
	check("airborne curve trajectories mirror",right_x>.005 and game.ball.position.x<-.005,{"right_x":right_x,"left_x":game.ball.position.x})
	await receive()
	key(KEY_Q,true)
	await ticks(20)
	game.pause_match()
	var frozen: Vector3 = game.ball.position
	await ticks(30)
	check("pause freezes physics and cancels charge",game.ball.position.distance_to(frozen)<.0001 and game.input_bridge.charge_preview.is_empty())
	key(KEY_Q,false)
	game.resume_match()
	await ticks(30)
	check("paused release cannot kick on resume",game.ball.carrier==game.player)
	fixture()
	game.ball.position = game.player.position+Vector3(0,.11,-1.8)
	game.ball.previous_position = game.ball.position
	game.ball.take(game.player)
	var passes_before: int = game.stats.passes
	await kick(KEY_Q,[],30)
	check("unreachable ball can't be kicked remotely",game.stats.passes==passes_before)
	check("contact data finite",contacts.filter(func(e): return e.success).all(func(e): return e.point.is_finite()))
	check("audio events found; legacy sound node absent",game.get_node_or_null("Sounds")==null and game.services.audio.diagnostics.played>0 and game.services.audio.diagnostics.missing==0,game.services.audio.diagnostics)
	await capture("end")
	var passed: int = checks.filter(func(c): return c.passed).size()
	var report := {"build":"Version A v0.5","native":native,"frames":frames,"passed":passed,"failed":checks.size()-passed,"checks":checks,"samples":samples,"stats":game.stats,"contacts":contacts,"scope":"Engine raw key/mouse events; staged starting positions retain all actors, normal AI and swept World. Independent QA remains separate."}
	FileAccess.open(evidence.path_join("integration_checks_"+("native" if native else "headless")+".json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("INTEGRATION_CHECKS ",passed,"/",checks.size())
	game.queue_free()
	await process_frame
	quit(0 if passed==checks.size() else 1)
