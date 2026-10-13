extends SceneTree
var game: Node
var frames := 0
var checks: Array[Dictionary] = []
var timeline: Array[Dictionary] = []
var rule_events: Array[Dictionary] = []
var evidence := ""
var native := false
var seed := 11
var gesture := ""
var gesture_ticks := 0
var last_state := ""
var state_frames := 0
var max_dead_seconds := 0.0
var max_speed := 0.0
var max_height := 0.0
var finite := true
var clock_valid := true
var attack_flip_seen := false
var capture_serial := 0
var started_us := 0
var play_trace: Array[Dictionary] = []
var contact_actions := {}
var height_events: Array[Dictionary] = []

func _initialize() -> void:
	evidence = ProjectSettings.globalize_path("res://../verification")
	native = DisplayServer.get_name()!="headless"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="): evidence = arg.trim_prefix("--evidence=")
		if arg.begins_with("--seed="): seed = int(arg.trim_prefix("--seed="))
	call_deferred("run")

func key(code: int, down: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func mouse(button: int, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func look_at_point(point: Vector3) -> void:
	var aim := Vector3(point.x-game.player.position.x,0,point.z-game.player.position.z)
	if aim.length()<.05: return
	var desired := atan2(-aim.x,-aim.z)
	var difference := angle_difference(game.player.rotation.y,desired)
	# Supported simulated engine mouse input. No OS or browser control.
	if not native:
		# Headless DisplayServer cannot capture a mouse. Exercise the starter's
		# real joystick look InputMap instead; native runs use mouse motion.
		var joy := InputEventJoypadMotion.new()
		joy.axis = JOY_AXIS_RIGHT_X
		joy.axis_value = clampf(-difference/.4,-1,1)
		Input.parse_input_event(joy)
		Input.flush_buffered_events()
		return
	var event := InputEventMouseMotion.new()
	event.relative = Vector2(-difference/game.player.head.mouse_sensitivity,0)
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func control_tick() -> void:
	if not gesture.is_empty():
		gesture_ticks -= 1
		if gesture_ticks<=0:
			if gesture=="pass": key(KEY_Q,false)
			else: mouse(MOUSE_BUTTON_LEFT,false)
			gesture = ""
	if frames%24!=0: return
	for code in [KEY_W,KEY_C,KEY_E,KEY_SHIFT]: key(code,false)
	if game.is_restart_taker(game.player):
		if gesture.is_empty() and game.player.action_cooldown<=0:
			var teammate: Node3D
			var nearest := INF
			for other in game.agents:
				if other.team!=0 or other.is_goalkeeper: continue
				var distance: float = game.flat_distance(other.position,game.ball.position)
				if distance>3 and distance<nearest:
					nearest = distance
					teammate = other
			if is_instance_valid(teammate):
				var pass_direction: Vector3 = teammate.position-game.ball.position
				pass_direction.y = 0
				pass_direction = pass_direction.normalized()
				var stance: Vector3 = game.ball.position-pass_direction*.46
				if game.flat_distance(game.player.position,stance)>.18:
					look_at_point(stance)
					key(KEY_W,true)
					return
				look_at_point(teammate.position)
				if not game.ball.can_kick(game.player) or game.player.facing.dot(pass_direction)<.92: return
			key(KEY_Q,true)
			gesture = "pass"
			gesture_ticks = 44
		return
	if game.phase!=game.Phase.PLAY:
		var restart: Dictionary = game.services.rules.restart
		if int(restart.get("taker_id",-1))==game.player.get_instance_id() and restart.has("taker_target"):
			look_at_point(restart.taker_target)
			if game.flat_distance(game.player.position,restart.taker_target)>.25: key(KEY_W,true)
		return
	if game.ball.carrier==game.player:
		look_at_point(game.target_goal(0))
		var goal_distance: float = game.flat_distance(game.player.position,game.target_goal(0))
		if goal_distance<23 and game.ball.can_kick(game.player) and gesture.is_empty() and game.player.action_cooldown<=0:
			mouse(MOUSE_BUTTON_LEFT,true)
			gesture = "shot"
			gesture_ticks = 52
		elif gesture.is_empty(): key(KEY_W,true)
	else:
		var destination: Vector3 = game.ball.position
		if is_instance_valid(game.ball.carrier) and game.ball.carrier.team==0:
			destination += Vector3(4.0 if seed%2 else -4.0,0,game.attack_direction(0)*5)
			if frames%180<24: key(KEY_E,true)
		look_at_point(destination)
		if game.flat_distance(game.player.position,destination)>1.0: key(KEY_W,true)
		if game.flat_distance(game.player.position,game.ball.position)<3 and is_instance_valid(game.ball.carrier) and game.ball.carrier.team==1: key(KEY_C,true)
		if not is_instance_valid(game.ball.carrier) and game.flat_distance(game.player.position,game.ball.position)<.95:
			key(KEY_SPACE,true)
			key(KEY_SPACE,false)

func capture(tag: String) -> void:
	if not native: return
	await process_frame
	await RenderingServer.frame_post_draw
	capture_serial += 1
	root.get_texture().get_image().save_png(evidence.path_join("full_%d_%03d_%s.png" % [seed,capture_serial,tag]))

func check(label: String, ok: bool, details: Variant = null) -> void:
	checks.append({"check":label,"passed":ok,"details":details})
	print("PASS " if ok else "FAIL ",label," ",details if details!=null else "")

func run() -> void:
	game = load("res://scenes/match.tscn").instantiate()
	game.test_mode = true
	root.add_child(game)
	game.services.rules_event.connect(func(event: Dictionary): rule_events.append(event.duplicate()))
	game.contact_hub.contact_resolved.connect(func(event: Dictionary):
		var label: String = ("human:" if event.actor==game.player else "ai:")+String(event.get("action",""))+(":hit" if event.get("success",false) else ":miss")
		contact_actions[label] = int(contact_actions.get(label,0))+1)
	game.start_match(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	started_us = Time.get_ticks_usec()
	for _i in 90000:
		await physics_frame
		frames += 1
		control_tick()
		var state: String = game.services.rules.state_name()
		if state!=last_state:
			if last_state not in ["LIVE","RESTART_IN_FLIGHT",""]: max_dead_seconds = maxf(max_dead_seconds,state_frames/120.0)
			timeline.append({"frame":frames,"state":state,"score":game.scores.duplicate(),"half":game.services.rules.half,"elapsed":game.services.rules.half_elapsed,"ball":game.ball.position,"taker":game.services.rules.restart.get("taker_id",-1)})
			last_state = state
			state_frames = 0
			await capture(state)
		state_frames += 1
		if state!="LIVE" and state!="RESTART_IN_FLIGHT" and state_frames>10800:
			print("DEAD_STATE_STALL ",game.services.rules.restart," violations=",game.services.rules.restart_violations()," human=",game.player.position)
			break
		for actor in game.players:
			finite = finite and actor.position.is_finite() and actor.velocity.is_finite()
			max_speed = maxf(max_speed,Vector2(actor.velocity.x,actor.velocity.z).length())
			if actor.position.y>max_height:
				max_height = actor.position.y
				if max_height>.08:
					var peak := {"frame":frames,"name":actor.name,"team":actor.team,"role":actor.role,"position":actor.position,"velocity":actor.velocity,"move_intent":actor.move_intent,"ball":game.ball.position,"ball_velocity":game.ball.velocity,"foot":actor.foot.kind,"invalid_normals":actor.invalid_normal_contacts}
					height_events.append(peak)
					print("HEIGHT_PEAK ",JSON.stringify(peak))
		finite = finite and game.ball.position.is_finite() and game.ball.velocity.is_finite() and game.ball.spin_rads.is_finite()
		clock_valid = clock_valid and game.services.rules.half_elapsed>=0 and game.services.rules.half_elapsed<=120.03
		if game.services.rules.half==2:
			attack_flip_seen = game.attack_direction(0)>0 and game.attack_direction(1)<0
		if frames%1800==0: print("FULL_PROGRESS seed=",seed," simulation_s=",frames/120.0," state=",state," half=",game.services.rules.half," elapsed=",game.services.rules.half_elapsed," stats=",game.stats)
		if frames%60==0:
			var owner: Node3D = game.ball.carrier
			play_trace.append({"frame":frames,"state":state,"ball":game.ball.position,"human_position":game.player.position,"human_yaw":game.player.rotation.y,"speed":game.ball.velocity.length(),"owner":game.players.find(owner),"owner_position":owner.position if is_instance_valid(owner) else Vector3.ZERO,"gap":game.flat_distance(owner.position,game.ball.position) if is_instance_valid(owner) else -1.0,"foot":owner.foot.kind if is_instance_valid(owner) else "","pending":owner.pending_kick.duplicate(true) if is_instance_valid(owner) and not owner.is_human else {},"intent":owner.tactical_intent.duplicate(true) if is_instance_valid(owner) and not owner.is_human else {}})
		if frames<2400 and frames%120==0: await capture("continuous")
		if game.phase==game.Phase.FINISHED: break
	check("full 240-second live-time match finishes",game.phase==game.Phase.FINISHED,{"frames":frames,"state":last_state,"half":game.services.rules.half,"elapsed":game.services.rules.half_elapsed})
	check("half-time switches attack directions",attack_flip_seen)
	check("clock bounded across stoppages",clock_valid)
	check("positions and velocities remain finite",finite)
	check("no actor launch / runaway speed",max_height<.15 and max_speed<9.5,{"height":max_height,"speed":max_speed})
	check("normal AI has actual passes and shots",game.stats.ai_passes>0 and game.stats.ai_shots>0,game.stats)
	check("both teams keep real goalkeeper roles",game.players.filter(func(a): return a.is_goalkeeper).size()==2)
	var final_stats: Dictionary = game.stats.duplicate()
	var final_score: Array = game.scores.duplicate()
	for cycle in range(3):
		game.restart_current()
		for _f in 6: await physics_frame
		check("restart lifecycle %d" % (cycle+1),game.players.size()==22 and game.scores==[0,0] and game.services.rules.half==1 and game.services.rules.state in [game.Rules.State.RESTART_SETUP,game.Rules.State.RESTART_READY])
	var passed: int = checks.filter(func(c): return c.passed).size()
	var report := {"build":"Version A v0.5","seed":seed,"native":native,"physics_hz":120,"default_live_match_seconds":240,"frames":frames,"wall_seconds":(Time.get_ticks_usec()-started_us)/1000000.0,"passed":passed,"failed":checks.size()-passed,"checks":checks,"timeline":timeline,"events":rule_events,"stats":final_stats,"score":final_score,"contacts":contact_actions,"play_trace":play_trace,"height_events":height_events,"max_dead_state_seconds":max_dead_seconds,"scope":"Full normal 11v11 match with simulated human engine key/mouse inputs (upstream joystick look in headless); no AI, rules or World disabled; physical desktop interaction not used."}
	FileAccess.open(evidence.path_join("full_match_%d_%s.json" % [seed,"native" if native else "headless"]),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("FULL_MATCH_END ",passed,"/",checks.size()," score=",final_score," stats=",final_stats)
	game.pause_match()
	game.shutdown_audio()
	OS.delay_msec(100)
	game.queue_free()
	game = null
	for _i in 4: await process_frame
	quit(0 if passed==checks.size() else 1)
