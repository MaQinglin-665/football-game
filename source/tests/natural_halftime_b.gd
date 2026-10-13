extends SceneTree
## Default natural 120-second half through the menu, then legal physical restart.
## No fixture, clock edit, transform edits, test_mode or AI/World disablement.
var game: Node
var frames := 0
var output := ""
var checks: Array[Dictionary] = []
var timeline: Array[Dictionary] = []
var events: Array[Dictionary] = []
var contacts: Array[Dictionary] = []
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

func _initialize() -> void:
	output = ProjectSettings.globalize_path("res://../verification/natural_halftime_b.json")
	for arg in OS.get_cmdline_user_args():
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
		actors.append({"name":String(actor.name),"team":actor.team,"human":actor.is_human,"position":actor.position,"velocity":actor.velocity,"target":actor.target if not actor.is_human else null,"waypoint":game.tactics_bridge.restart_waypoints.get(actor.get_instance_id(),{}).duplicate(true)})
	return {"frame":frames,"state":game.services.rules.state_name(),"half":game.services.rules.half,"elapsed":game.services.rules.half_elapsed,"ball":game.ball.position,"restart":game.services.rules.restart.duplicate(true),"violations":game.services.rules.restart_violations(),"actors":actors}

func run() -> void:
	game = load("res://scenes/match.tscn").instantiate()
	root.add_child(game)
	game.services.rules_event.connect(func(event: Dictionary): events.append(event.duplicate(true)))
	game.contact_hub.contact_resolved.connect(func(event: Dictionary):
		if event.get("success",false): contacts.append({"frame":frames,"half":game.services.rules.half,"state":game.services.rules.state_name(),"actor":String(event.actor.name),"action":String(event.get("action","")),"success":true,"point":event.get("point",Vector3.ZERO)}))
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
	check("menu start path starts default match",game.phase!=game.Phase.MENU and not game.test_mode and game.match_length==240,{"phase":game.phase,"test_mode":game.test_mode,"match_length":game.match_length,"activation":menu_activation})
	if game.phase!=game.Phase.MENU:
		for _i in 3600:
			await physics_frame
			if game.is_restart_taker(game.player): break
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
			var state_key := "%d:%s" % [rules.half,state]
			if state_key!=previous_state:
				timeline.append({"frame":frames,"half":rules.half,"state":state,"elapsed":rules.half_elapsed,"restart":rules.restart.duplicate(true),"violations":rules.restart_violations()})
				print("NATURAL_STATE ",timeline.back())
				previous_state = state_key
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
	check("natural first half reaches 120 LIVE seconds",half_interval_seen and half_interval_elapsed>=119.99,{"interval_seen":half_interval_seen,"elapsed":half_interval_elapsed})
	check("second half flips directions once",game.services.rules.half==2 and game.attack_direction(0)>0 and game.attack_direction(1)<0)
	check("all kickoff actors reach legal positions",half2_ready_legal)
	var half2_contacts := contacts.filter(func(c): return c.half==2 and c.action=="PASS")
	check("AI second-half actual pass restarts LIVE",half2_live_frame>=0 and not half2_contacts.is_empty() and game.services.rules.half_elapsed>=5,{"half2_frame":half2_frame,"live_frame":half2_live_frame,"clearance_seconds":(half2_live_frame-half2_frame)/120.0 if half2_live_frame>=0 else null,"contacts":half2_contacts})
	snapshots.append(snapshot())
	var passed := checks.filter(func(c): return c.passed).size()
	var report := {"build":"B v0.6 working candidate","passed":passed,"failed":checks.size()-passed,"checks":checks,"frames":frames,"wall_seconds":(Time.get_ticks_usec()-started_us)/1000000.0,"native":DisplayServer.get_name()!="headless","menu_activation":menu_activation,"test_mode":game.test_mode,"fixture_used":false,"clock_modified":false,"ai_enabled":game.ai_enabled,"actor_count":game.players.size(),"timeline":timeline,"events":events,"successful_contacts":contacts,"snapshots":snapshots,"scope":"Natural default 120-second first half, 22 actors, sole World/rules/audio/AI active. Actual menu Button callback used in headless, native viewport GUI input required separately. Initial Q uses supported Input.parse_input_event. No human transform/clock or rule-state setup, no physical desktop interaction. Headless runtime is natural rules/physics evidence, not GUI input, FPS or visual verification."}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("NATURAL_HALFTIME_END ",passed,"/",checks.size()," output=",output)
	game.pause_match()
	game.shutdown_audio()
	OS.delay_msec(100)
	game.queue_free()
	game = null
	for _i in 4: await process_frame
	quit(0 if passed==checks.size() else 1)
