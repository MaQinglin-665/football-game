extends "res://tests/integration_checks.gd"
## Small release check: real engine input and shoe contacts in isolated fixtures.
var current_case := ""
var observations: Array[Dictionary] = []
var resolved: Array[Dictionary] = []

func observe(count: int) -> Dictionary:
	var peak_speed := 0.0
	var peak_owned_speed := 0.0
	var max_gap := 0.0
	var owned_ticks := 0
	for i in count:
		await ticks(1)
		var p: Node3D = game.player
		var gap: float = game.flat_distance(p.position,game.ball.position)
		var actual_speed := Vector2(p.velocity.x,p.velocity.z).length()
		var owned: bool = game.ball.carrier==p
		peak_speed = maxf(peak_speed,actual_speed)
		max_gap = maxf(max_gap,gap)
		if owned:
			owned_ticks += 1
			peak_owned_speed = maxf(peak_owned_speed,actual_speed)
		if i%3==0:
			observations.append({"case":current_case,"frame":frames,"actor_speed_mps":actual_speed,"requested_speed_mps":p.speed,"ball_speed_mps":Vector2(game.ball.velocity.x,game.ball.velocity.z).length(),"gap_m":gap,"owned":owned,"tier":game.input_bridge.shift_policy.get("tier",""),"close_control":p.close_control,"foot":p.foot.kind,"foot_phase":p.foot.phase,"foot_hit":p.foot.hit})
	return {"peak_speed_mps":peak_speed,"peak_owned_speed_mps":peak_owned_speed,"max_gap_m":max_gap,"owned_ticks":owned_ticks,"observed_ticks":count}

func prepare_case(label: String) -> bool:
	current_case = label
	var received := await receive()
	# Allow the previous Shift burst to end without moving or fabricating control.
	await ticks(34)
	return received and game.ball.carrier==game.player

func run() -> void:
	game = load("res://scenes/match.tscn").instantiate()
	game.test_mode = true
	root.add_child(game)
	game.contact_hub.contact_resolved.connect(func(e: Dictionary):
		if e.actor==game.player:
			resolved.append({"case":current_case,"frame":frames,"action":e.action,"success":e.success,"sequence":e.get("action_sequence",-1),"reach_error":e.get("reach_error",-1),"before_speed_mps":Vector2(e.before_velocity.x,e.before_velocity.z).length(),"after_speed_mps":Vector2(e.after_velocity.x,e.after_velocity.z).length()}))
	game.start_match(false)
	for i in 2400:
		await ticks(1)
		if game.is_restart_taker(game.player): break
	key(KEY_Q,true)
	await ticks(50)
	key(KEY_Q,false)
	await ticks(650)
	check("actual kickoff reaches live play",game.phase==game.Phase.PLAY,game.services.rules.state_name())

	var received_close := await prepare_case("no_shift")
	check("noShift fixture receives by real shoe",received_close)
	key(KEY_W,true)
	var close_stats := await observe(180)
	key(KEY_W,false)
	check("noShift uses close policy",observations.any(func(r): return r.case=="no_shift" and r.owned and r.close_control))
	check("noShift actual movement measured",float(close_stats.peak_owned_speed_mps)>1.5,close_stats)

	var received_run := await prepare_case("hold_shift")
	check("hold fixture receives by real shoe",received_run)
	var before_trace: int = game.input_bridge.traces.size()
	key(KEY_SHIFT,true)
	key(KEY_W,true)
	var run_stats := await observe(180)
	var held_pushes: Array = game.input_bridge.traces.slice(before_trace).filter(func(e): return e.action=="push_ball" and e.phase=="commit")
	check("hold Shift selects run without max sprint",game.input_bridge.shift_policy.get("tier","")=="run" and not game.player.sprinting)
	check("hold Shift creates zero automatic heavy requests",held_pushes.is_empty(),held_pushes.size())
	check("hold Shift creates zero automatic SPRINT contacts",resolved.filter(func(e): return e.case=="hold_shift" and e.action=="SPRINT").is_empty())
	check("hold actual speed exceeds close actual speed",float(run_stats.peak_speed_mps)>float(close_stats.peak_owned_speed_mps)+.3,{"close":close_stats,"hold":run_stats})
	key(KEY_SHIFT,false)
	await ticks(2)
	check("release Shift immediately restores walk_jog",game.input_bridge.shift_policy.get("tier","")=="walk_jog")
	key(KEY_W,false)

	var received_double := await prepare_case("double_shift")
	check("double fixture receives by real shoe",received_double)
	before_trace = game.input_bridge.traces.size()
	key(KEY_SHIFT,true)
	await ticks(6)
	key(KEY_SHIFT,false)
	await ticks(6)
	key(KEY_SHIFT,true)
	var double_stats := await observe(90)
	var doubles: Array = game.input_bridge.traces.slice(before_trace).filter(func(e): return e.action=="push_ball" and e.phase=="commit")
	var heavy_hits: Array = resolved.filter(func(e): return e.case=="double_shift" and e.action=="SPRINT" and e.success)
	check("released double emits exactly one heavy request",doubles.size()==1,doubles)
	check("double is one real shoe contact",heavy_hits.size()==1,heavy_hits)
	check("real heavy contact makes a free ball",heavy_hits.size()==1 and game.ball.carrier!=game.player,{"carrier":game.players.find(game.ball.carrier),"stats":double_stats})
	key(KEY_SHIFT,false)

	await prepare_case("pass_unchanged")
	key(KEY_Q,true)
	await ticks(30)
	key(KEY_Q,false)
	await observe(90)
	check("Q pass still has a real shoe contact",resolved.any(func(e): return e.case=="pass_unchanged" and e.action=="PASS" and e.success))

	await prepare_case("no_ball_double")
	game.ball.detach()
	before_trace = game.input_bridge.traces.size()
	key(KEY_SHIFT,true)
	await ticks(6)
	key(KEY_SHIFT,false)
	await ticks(6)
	key(KEY_SHIFT,true)
	await ticks(2)
	check("no ball double does not queue a remote kick",game.input_bridge.traces.slice(before_trace).filter(func(e): return e.action=="push_ball" and e.phase=="commit").is_empty())
	release_inputs()

	var passed: int = checks.filter(func(c): return c.passed).size()
	var report := {"build":"B v0.6.4 full-body/C-shape on frozen0.6.3","passed":passed,"failed":checks.size()-passed,"headless":not native,"checks":checks,"observations":observations,"contacts":resolved,"scope":"Actual engine keyboard events with new full-body layer and required C geometry, unchanged frozen0.6.3 input/physics and normal22 actors/World; initial free-ball fixtures acquire ownership via real shoe reception. WASAPI entry mutes only this test process. No full match, physical desktop input, subjective ball-feel or performance claim."}
	FileAccess.open(evidence.path_join("shift_release_checks.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("SHIFT_RELEASE_CHECKS ",passed,"/",checks.size())
	game.pause_match()
	game.shutdown_audio()
	game.queue_free()
	for i in 4: await process_frame
	quit(0 if passed==checks.size() else 1)
