extends "res://tests/integration_checks.gd"
## Same physical starting fixture, actual keyboard gestures, normal 22 AI/World.
## Record real shoe outcomes and complete ball paths rather than intention only.
var case_id := ""
var paths: Array[Dictionary] = []
var case_results: Array[Dictionary] = []
var case_contacts: Array[Dictionary] = []

func xyz(v: Vector3) -> Array: return [v.x,v.y,v.z]

func observe_ticks(count: int, tag: String) -> void:
	for i in count:
		await ticks(1)
		if i%3==0:
			var p: Node3D = game.player
			paths.append({"case":case_id,"frame":frames,"seconds":frames/120.0,"ball":xyz(game.ball.position),"ball_velocity":xyz(game.ball.velocity),"spin":xyz(game.ball.spin_rads),"actor":xyz(p.position),"actor_velocity":xyz(p.velocity),"yaw":p.rotation.y,"relative_ball":xyz(p.global_basis.inverse()*(game.ball.position-p.position)),"carrier":game.players.find(game.ball.carrier) if is_instance_valid(game.ball.carrier) else -1,"foot":p.foot.kind,"foot_phase":p.foot.phase,"surface":p.foot.surface,"side":p.foot.side,"foot_direction":xyz(p.foot.foot_direction),"socket":xyz(p.foot.actual_contact.get("point",Vector3.ZERO)),"target":xyz(p.foot.contact_target),"weight_shift":xyz(p.avatar.weight_shift),"hit":p.foot.hit,"reach_error":p.foot.actual_contact.get("reach_error",-1.0),"rules":game.services.rules.state_name()})
			if native and i%6==0: await capture(tag)

func prepare(lateral := 0.0) -> bool:
	fixture()
	game.ball.position.x += lateral
	game.ball.previous_position = game.ball.position
	key(KEY_SPACE,true)
	await ticks(1)
	key(KEY_SPACE,false)
	await ticks(30)
	return game.ball.carrier==game.player

func nudge_case(name: String, movement: int, lateral: float, moving := false) -> void:
	case_id = name
	case_contacts.clear()
	var received := await prepare(lateral)
	if moving:
		key(KEY_CTRL,true)
		key(KEY_W,true)
		await ticks(72)
		for _i in 40:
			if not game.player.foot.idle(): break
			await ticks(1)
		key(KEY_W,false)
	var initially_busy: bool = not game.player.foot.idle()
	var start_ball: Vector3 = game.ball.position
	var start_actor: Vector3 = game.player.position
	var start_yaw: float = game.player.rotation.y
	var trace_start: int = game.input_bridge.traces.size()
	key(KEY_CTRL,true)
	key(movement,true)
	key(KEY_SPACE,true)
	await ticks(2)
	key(KEY_SPACE,false)
	key(movement,false)
	key(KEY_CTRL,false)
	await observe_ticks(120,name)
	var nudge_events: Array = game.input_bridge.traces.slice(trace_start).filter(func(e): return e.action=="nudge" and e.phase=="commit")
	var hit_events := case_contacts.filter(func(e): return e.success and e.action=="TURN")
	var signed: float = -1.0 if movement==KEY_A else 1.0
	var peak := 0.0
	for row in paths:
		if row.case!=name: continue
		peak = maxf(peak,(float(row.ball[0])-start_ball.x)*signed)
	case_results.append({"case":name,"received":received,"initially_busy":initially_busy,"nudge_intents":nudge_events,"true_turn_hits":hit_events,"all_contacts":case_contacts.duplicate(true),"peak_signed_ball_x_m":peak,"actor_displacement":xyz(game.player.position-start_actor),"yaw_change_rad":game.player.rotation.y-start_yaw,"final_ball":xyz(game.ball.position),"final_relative":xyz(game.player.global_basis.inverse()*(game.ball.position-game.player.position))})
	check(name+" actual input emits nudge",received and nudge_events.size()>0,nudge_events)
	check(name+" actual shoe changes ball laterally",hit_events.size()>0 and peak>.15,{"contacts":hit_events,"peak":peak})
	check(name+" touch independent of body turning",absf(game.player.rotation.y-start_yaw)<.001 and absf(game.player.position.x-start_actor.x)<.12)
	if moving: check(name+" tested real busy dribble touch",initially_busy)

func pass_case(name: String, modifiers: Array) -> void:
	case_id = name
	case_contacts.clear()
	var received := await prepare()
	var initial: Vector3 = game.ball.position
	for code in modifiers: key(code,true)
	key(KEY_Q,true)
	await ticks(90)
	key(KEY_Q,false)
	await observe_ticks(360,name)
	for code in modifiers: key(code,false)
	var hits := case_contacts.filter(func(e): return e.success and e.action=="PASS")
	var peak_height := 0.0
	var peak_side := 0.0
	for row in paths:
		if row.case!=name: continue
		peak_height = maxf(peak_height,float(row.ball[1]))
		peak_side = maxf(peak_side,absf(float(row.ball[0])-initial.x))
	case_results.append({"case":name,"received":received,"pass_contacts":hits,"semantic_intent":game.ball.last_kick_intent.duplicate(true),"peak_height_m":peak_height,"peak_lateral_m":peak_side,"final_ball":xyz(game.ball.position)})
	check(name+" actual shoe pass",received and hits.size()>0,hits)
	if name=="high": check("high pass has actual airborne arc",peak_height>1.0,peak_height)
	if name=="high_spin_left": check("airborne spin bends actual path",peak_height>1.0 and peak_side>.30,{"height":peak_height,"lateral":peak_side})

func run() -> void:
	game = load("res://scenes/match.tscn").instantiate()
	game.test_mode = true
	root.add_child(game)
	game.contact_hub.contact_resolved.connect(func(e: Dictionary):
		if e.actor==game.player: case_contacts.append({"case":case_id,"frame":frames,"action":e.action,"surface":e.surface,"success":e.success,"point":xyz(e.point),"before":xyz(e.before_velocity),"after":xyz(e.after_velocity),"spin":xyz(game.ball.spin_rads),"reach_error":e.get("reach_error",-1.0)}))
	game.start_match(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	for _i in 2400:
		await ticks(1)
		if game.is_restart_taker(game.player): break
	key(KEY_Q,true)
	await ticks(50)
	key(KEY_Q,false)
	await ticks(650)
	await nudge_case("left_outside",KEY_A,0.0)
	await nudge_case("right_outside",KEY_D,0.0)
	await nudge_case("right_ball_inward_left",KEY_A,.28)
	await nudge_case("left_ball_inward_right",KEY_D,-.28)
	await nudge_case("moving_busy_left",KEY_A,0.0,true)
	await nudge_case("moving_busy_right",KEY_D,0.0,true)
	await pass_case("ground",[])
	await pass_case("high",[KEY_F])
	await pass_case("ground_spin_left",[KEY_Z])
	await pass_case("high_spin_left",[KEY_F,KEY_Z])
	var passed: int = checks.filter(func(c): return c.passed).size()
	var report := {"build":"B v0.6 integration work","native":native,"passed":passed,"failed":checks.size()-passed,"checks":checks,"cases":case_results,"paths":paths,"scope":"Physical start fixtures only; actual Ctrl+A/D+Space tap with body yaw unchanged, actual Q/F/Z pass gestures, normal 22 AI, single World and rules. No fake ball ownership, contact, score or disabled opponents. Lateral body key is released after 2 physics ticks."}
	FileAccess.open(evidence.path_join("control_feedback_%s.json" % ("native" if native else "headless")),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("CONTROL_FEEDBACK ",passed,"/",checks.size())
	game.pause_match()
	game.shutdown_audio()
	OS.delay_msec(100)
	game.queue_free()
	game = null
	for _i in 4: await process_frame
	quit(0 if passed==checks.size() else 1)
