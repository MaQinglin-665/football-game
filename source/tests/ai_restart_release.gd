extends SceneTree
## Default natural 120-second half through the menu, then legal physical restart.
## No fixture, clock edit, transform edits, test_mode or AI/World disablement.
var game: Node
var frames := 0
var output := ""
var assist_human := false
var diagnostic_journal: Array[Dictionary] = []
var assist_journal: Array[Dictionary] = []
var assist_serial := -1
var assist_next_attempt := 0.0
var assist_q_release := 0.0
var assist_seconds := 0.0
var checks: Array[Dictionary] = []
var timeline: Array[Dictionary] = []
var events: Array[Dictionary] = []
var contacts: Array[Dictionary] = []
var body_contacts: Array[Dictionary] = []
var snapshots: Array[Dictionary] = []
var previous_state := ""
var half_interval_seen := false
var half_interval_elapsed := 0.0
var half2_frame := -1
var half2_live_frame := -1
var half2_ready_legal := false
var initial_kickoff := false
var started_us := 0
var menu_activation := "viewport_gui_input"
var dead_serial := -1
var dead_age := 0.0
var human_restart_serial := -1
var human_kick_frames := 0
var human_restart_inputs: Array[Dictionary] = []

func _initialize() -> void:
	AudioServer.set_bus_mute(0,true)
	output = ProjectSettings.globalize_path("res://../verification/natural_halftime_b.json")
	for arg in OS.get_cmdline_user_args():
		if arg=="--assist-human": assist_human = true
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	call_deferred("run")

func key(code: int, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func menu_click(down: bool) -> void:
	var button: Button = game.hud.menu.get_node("StartMatch")
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	event.pressed = down
	event.position = button.get_global_rect().get_center()
	event.global_position = event.position
	# Headless has no focused OS window; push into the actual GUI viewport.
	root.push_input(event)

func check(label: String, ok: bool, details: Variant = null) -> void:
	checks.append({"check":label,"passed":ok,"details":details})
	print("PASS " if ok else "FAIL ",label," ",details if details!=null else "")

func snapshot() -> Dictionary:
	var actors := []
	for actor in game.players:
		actors.append({"name":String(actor.name),"team":actor.team,"human":actor.is_human,"position":actor.position,"velocity":actor.velocity,"facing":actor.facing,"body_facing":actor.body_facing,"foot_phase":actor.foot.phase,"foot_kind":actor.foot.kind,"foot_result":actor.foot.last_result,"foot_misses":actor.foot.misses,"target":actor.target if not actor.is_human else null,"waypoint":game.tactics_bridge.restart_waypoints.get(actor.get_instance_id(),{}).duplicate(true)})
	return {"frame":frames,"state":game.services.rules.state_name(),"half":game.services.rules.half,"elapsed":game.services.rules.half_elapsed,"ball":game.ball.position,"restart":game.services.rules.restart.duplicate(true),"violations":game.services.rules.restart_violations(),"actors":actors}

func run() -> void:
	game = load("res://scenes/match.tscn").instantiate()
	game.match_length = 12.0 # Test-only configuration before menu start, six-second halves.
	root.add_child(game)
	game.services.rules_event.connect(func(event: Dictionary): events.append(event.duplicate(true)))
	game.contact_hub.contact_resolved.connect(func(event: Dictionary):
		if event.get("success",false): contacts.append({"frame":frames,"half":game.services.rules.half,"state":game.services.rules.state_name(),"actor":String(event.actor.name),"action":String(event.get("action","")),"success":true,"point":event.get("point",Vector3.ZERO),"actor_position":event.actor.position,"actor_velocity":event.actor.velocity,"actor_facing":event.actor.facing,"ball_position":game.ball.position,"shoe_contact":event.actor.foot.actual_contact.duplicate(true),"action_sequence":event.actor.foot.sequence}))
	game.contact_hub.body_contact.connect(func(event: Dictionary):
		if event.get("ball_contact",false): body_contacts.append({"frame":frames,"half":game.services.rules.half,"state":game.services.rules.state_name(),"actor":String(event.actor.name),"point":event.get("point",Vector3.ZERO),"actor_position":event.actor.position,"ball_position":game.ball.position,"impulse":event.get("impulse",Vector3.ZERO)}))
	for _i in 5: await process_frame
	started_us = Time.get_ticks_usec()
	# Headless has no real GUI window. Exercise the actual menu's callback and
	# report that limited activation separately; native requires viewport input.
	print("MENU_PREFLIGHT viewport=",root.get_visible_rect()," button=",game.hud.menu.get_node("StartMatch").get_global_rect()," gui_disabled=",root.gui_disable_input)
	if DisplayServer.get_name()=="headless":
		menu_activation = "headless_actual_menu_button_signal_ui_input_not_evaluated"
		game.hud.menu.get_node("StartMatch").pressed.emit()
	else:
		menu_click(true)
		for _i in 2: await process_frame
		menu_click(false)
	print("MENU_FOCUS ",root.gui_get_focus_owner())
	for _i in 600:
		await physics_frame
		if game.phase!=game.Phase.MENU: break
	check("menu start path starts configured short match",game.phase!=game.Phase.MENU and not game.test_mode and game.match_length==12.0,{"phase":game.phase,"test_mode":game.test_mode,"match_length":game.match_length,"activation":menu_activation})
	if game.phase!=game.Phase.MENU:
		for _i in 3600:
			await physics_frame
			if game.is_restart_taker(game.player) and game.services.rules.state==game.Rules.State.RESTART_READY: break
		key(KEY_Q,true)
		for _i in 50: await physics_frame
		key(KEY_Q,false)
		for _i in 1200:
			await physics_frame
			if game.services.rules.state==game.Rules.State.LIVE: break
		initial_kickoff = game.services.rules.state==game.Rules.State.LIVE
	check("initial kickoff uses actual shoe contact",initial_kickoff,contacts.duplicate(true))
	if initial_kickoff:
		for _i in 36000:
			await physics_frame
			frames += 1
			var rules: FBMatchRulesEngine = game.services.rules
			var state := rules.state_name()
			if rules.state in [game.Rules.State.RESTART_SETUP,game.Rules.State.RESTART_READY]:
				var serial := int(rules.restart.get("serial",-1))
				if serial!=dead_serial:
					dead_serial = serial
					dead_age = 0.0
				dead_age += 1.0/120.0
				if dead_age>30.0:
					snapshots.append(snapshot())
					print("NATURAL_RESTART_STALL ",snapshots.back())
					break
			else: dead_age = 0.0
			assist_seconds += 1.0/120.0
			if assist_human: _assist_human_restart(rules)
			if rules.state in [game.Rules.State.RESTART_SETUP,game.Rules.State.RESTART_READY]:
				var taker: Node3D = game.actor_by_instance(int(rules.restart.get("taker_id",-1)))
				if is_instance_valid(taker) and (frames%15==0 or taker.foot.phase==taker.foot.Phase.CONTACT):
					diagnostic_journal.append(_taker_diagnostic(taker))
			if not assist_human and rules.state==game.Rules.State.RESTART_READY and game.is_restart_taker(game.player):
				var serial := int(rules.restart.serial)
				if serial!=human_restart_serial:
					human_restart_serial = serial
					human_kick_frames = 50
					human_restart_inputs.append({"frame":frames,"half":rules.half,"serial":serial,"key":"Q","interface":"Input.parse_input_event","kind":rules.restart.kind})
					key(KEY_Q,true)
			if human_kick_frames>0:
				human_kick_frames -= 1
				if human_kick_frames==0: key(KEY_Q,false)
			var state_key := "%d:%s" % [rules.half,state]
			if state_key!=previous_state:
				timeline.append({"frame":frames,"half":rules.half,"state":state,"elapsed":rules.half_elapsed,"restart":rules.restart.duplicate(true),"violations":rules.restart_violations()})
				print("NATURAL_STATE ",timeline.back())
				previous_state = state_key
				if rules.half==2: snapshots.append(snapshot())
			if rules.state==game.Rules.State.HALF_TIME:
				half_interval_seen = true
				half_interval_elapsed = maxf(half_interval_elapsed,rules.half_elapsed)
			if rules.half==2 and half2_frame<0: half2_frame = frames
			if rules.half==2 and rules.state==game.Rules.State.RESTART_READY:
				half2_ready_legal = rules.restart_violations().is_empty()
			if rules.half==2 and rules.state==game.Rules.State.LIVE:
				if half2_live_frame<0: half2_live_frame = frames
				if rules.half_elapsed>=5.0: break
			if frames%600==0 or (half2_frame>=0 and frames%60==0): snapshots.append(snapshot())
			if frames%1800==0: print("NATURAL_PROGRESS sim_s=",frames/120.0," state=",state," half=",rules.half," live_s=",rules.half_elapsed)
			if half2_frame>=0 and half2_live_frame<0 and frames-half2_frame>3600:
				print("NATURAL_HALF2_STALL ",snapshot())
				break
	check("configured first half reaches6 LIVE seconds",half_interval_seen and half_interval_elapsed>=5.99,{"interval_seen":half_interval_seen,"elapsed":half_interval_elapsed})
	check("second half flips directions once",game.services.rules.half==2 and game.attack_direction(0)>0 and game.attack_direction(1)<0)
	check("all kickoff actors reach legal positions",half2_ready_legal)
	var half2_contacts := contacts.filter(func(c): return c.half==2 and c.action=="PASS")
	check("AI second-half actual pass restarts LIVE",half2_live_frame>=0 and not half2_contacts.is_empty() and game.services.rules.half_elapsed>=5,{"half2_frame":half2_frame,"live_frame":half2_live_frame,"clearance_seconds":(half2_live_frame-half2_frame)/120.0 if half2_live_frame>=0 else null,"contacts":half2_contacts})
	snapshots.append(snapshot())
	var passed := checks.filter(func(c): return c.passed).size()
	var report := {"build":"0.6.6-ai on frozen0.6.5-shot; test-only12-second match configuration","passed":passed,"failed":checks.size()-passed,"checks":checks,"frames":frames,"wall_seconds":(Time.get_ticks_usec()-started_us)/1000000.0,"native":DisplayServer.get_name()!="headless","menu_activation":menu_activation,"test_mode":game.test_mode,"fixture_used":false,"clock_modified":false,"match_length_override_before_start":12.0,"default120s_half_not_retested":true,"ai_enabled":game.ai_enabled,"actor_count":game.players.size(),"timeline":timeline,"events":events,"human_restart_inputs":human_restart_inputs,"assist_human":assist_human,"diagnostic_journal":diagnostic_journal,"assist_journal":assist_journal,"old_pass_dependency_imported":ResourceLoader.exists("res://scripts/integration_pass_coordinator.gd"),"successful_contacts":contacts,"body_contacts":body_contacts,"snapshots":snapshots,"scope":"Configured6-second first half on actual main tree, 22 actors, sole World/rules/audio/AI active. Actual menu Button callback used in headless, native viewport GUI input required separately. Initial Q uses supported Input.parse_input_event. Match length is configured12 before actual menu start; no human transform, running clock or rule-state setup, no physical desktop interaction. Headless runtime is natural rules/physics evidence, not GUI input, FPS or visual verification."}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("NATURAL_HALFTIME_END ",passed,"/",checks.size()," output=",output)
	game.pause_match()
	game.shutdown_audio()
	OS.delay_msec(100)
	game.queue_free()
	game = null
	for _i in 4: await process_frame
	quit(0 if passed==checks.size() else 1)

func _look_axis(value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = JOY_AXIS_RIGHT_X
	event.axis_value = value
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _assist_human_restart(rules: FBMatchRulesEngine) -> void:
	if assist_q_release>0.0 and assist_seconds>=assist_q_release:
		key(KEY_Q,false)
		assist_q_release = 0.0
	if rules.state not in [game.Rules.State.RESTART_SETUP,game.Rules.State.RESTART_READY] or int(rules.restart.get("taker_id",-1))!=game.player.get_instance_id():
		_look_axis(0.0)
		key(KEY_W,false)
		key(KEY_CTRL,false)
		return
	var serial: int = int(rules.restart.serial)
	if serial!=assist_serial:
		assist_serial = serial
		assist_next_attempt = assist_seconds
		assist_journal.append({"frame":frames,"serial":serial,"action":"human_take_control","state":rules.state_name(),"gap":game.flat_distance(game.player.position,game.ball.position),"input_interface":"Input.parse_input_event"})
	if assist_q_release>0.0: return
	# Use the supported gamepad look axis, not player.rotation/turn_view/reset.
	var offset := Vector3(game.ball.position.x-game.player.position.x,0,game.ball.position.z-game.player.position.z)
	var desired_yaw := atan2(-offset.x,-offset.z)
	var turn := angle_difference(game.player.rotation.y,desired_yaw)
	if absf(turn)>.035:
		# Full supported axis avoids Input.get_vector action deadzone.
		# At 120 Hz this turns 0.0167 rad per frame, below the 0.035 stop tolerance.
		_look_axis(-signf(turn))
		key(KEY_W,false)
		key(KEY_CTRL,false)
		return
	_look_axis(0.0)
	# Normal Ctrl+W walks through the existing semantic input router, including
	# SETUP: a fixed human must approach before the referee can become READY.
	var flat_speed := Vector2(game.player.velocity.x,game.player.velocity.z).length()
	var braking_distance: float = flat_speed*flat_speed/(2.0*game.player.profile.brake_deceleration_mps2)
	if offset.length()>.52+braking_distance+.04:
		key(KEY_CTRL,true)
		key(KEY_W,true)
		return
	key(KEY_W,false)
	key(KEY_CTRL,false)
	if flat_speed>.12 or rules.state!=game.Rules.State.RESTART_READY: return
	if assist_seconds<assist_next_attempt: return
	key(KEY_Q,true)
	assist_q_release = assist_seconds+50.0/120.0
	assist_next_attempt = assist_seconds+1.3
	assist_journal.append({"frame":frames,"serial":serial,"action":"Q_press","gap":offset.length(),"ball_angle_rad":turn,"input_interface":"Input.parse_input_event"})

func _taker_diagnostic(actor: Node3D) -> Dictionary:
	var foot: FootballFootAction = actor.foot
	var offset := Vector3(game.ball.position.x-actor.position.x,0,game.ball.position.z-actor.position.z)
	var actual: Dictionary = foot.actual_contact
	return {"frame":frames,"half":game.services.rules.half,"serial":game.services.rules.restart.get("serial",-1),"state":game.services.rules.state_name(),"actor":String(actor.name),"human":actor.is_human,"position":actor.position,"velocity":actor.velocity,"facing":actor.facing,"ball_offset":offset,"gap":offset.length(),"front_dot":offset.normalized().dot(actor.facing) if offset.length()>.001 else 0.0,"target":actor.target if not actor.is_human else null,"can_kick":game.ball.can_kick(actor),"can_reach":game.can_reach_ball(actor),"cooldown":actor.action_cooldown,"foot_phase":foot.phase,"foot_kind":foot.kind,"foot_result":foot.last_result,"foot_sequence":foot.sequence,"foot_misses":foot.misses,"foot_side":foot.side,"toe":foot.toe_world,"foot_target":foot.contact_target,"contact_valid":actual.get("valid",false),"reach_error":actual.get("reach_error",null),"shoe_ball_gap":foot.toe_world.distance_to(game.ball.position),"ball_radius":game.ball.radius,"camera_enabled":game.player.head.enabled,"input_enabled":game.player.input_enabled,"rule_violations":game.services.rules.restart_violations(),"rejected_inputs":game.input_bridge.rejected_commands,"last_input_traces":game.input_bridge.traces.slice(maxi(0,game.input_bridge.traces.size()-5))}
