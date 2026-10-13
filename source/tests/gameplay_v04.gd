extends SceneTree
var m: Node3D
var checks: Array[Dictionary] = []
var simulations: Array[Dictionary] = []
var report_path := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			report_path = arg.trim_prefix("--report=")
	call_deferred("run")

func frames(count: int) -> void:
	for i in range(count):
		await physics_frame

func check(ok: bool, text: String) -> void:
	checks.append({"name":text,"passed":ok})
	print("PASS " if ok else "FAIL ",text)

func action(name: String) -> void:
	var event := InputEventAction.new()
	event.action = name
	event.pressed = true
	root.push_input(event,true)

func click(point: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	root.push_input(event,true)

func clear_inputs() -> void:
	for name in ["move_forward","move_back","move_left","move_right","sprint","shield","close_control"]:
		Input.action_release(name)

func park() -> void:
	for i in range(m.agents.size()):
		m.agents[i].position = Vector3(-17 if i%2==0 else 17,0.92,16+int(i/2)*2.5)
		m.agents[i].velocity = Vector3.ZERO
		m.agents[i].foot.cancel()

func run() -> void:
	m = load("res://scenes/match.tscn").instantiate()
	m.test_mode = true
	m.ai_enabled = false
	root.add_child(m)
	await frames(6)
	check(m.players.size()==10 and m.agents.size()==9,"One fixed human and nine AI actors instantiate")
	check(m.player.has_node("Head/Camera") and m.player.has_node("Sprint"),"Pinned first-person movement and sprint modules are retained")
	m.hud.show_credits()
	check(m.hud.credits.get_node("Notices").text.contains("Dimitar") and m.hud.credits.get_node("Notices").text.contains("Jolt"),"In-game credits contain upstream and engine licenses")
	action("ui_cancel")
	check(not m.hud.credits.visible and m.phase==m.Phase.MENU,"Escape closes credits while preserving the menu")
	click(Vector2(310,367),true)
	await frames(2)
	click(Vector2(310,367),false)
	await frames(2)
	check(m.phase==m.Phase.COUNTDOWN and m.ball.carrier==m.player,"The actual menu button starts a five-a-side kickoff")
	await frames(145)
	check(m.phase==m.Phase.PLAY and m.time_left>119,"Kickoff countdown enters timed play")
	action("ui_cancel")
	var frozen: float = m.time_left
	await frames(20)
	check(m.phase==m.Phase.PAUSED and not m.player.input_enabled and is_equal_approx(frozen,m.time_left),"Pause freezes movement and match time")
	action("ui_cancel")
	check(m.phase==m.Phase.PLAY and m.player.input_enabled,"Escape resumes play")
	m.show_menu()
	await frames(3)
	click(Vector2(310,427),true)
	await frames(2)
	click(Vector2(310,427),false)
	await frames(2)
	check(m.duel_mode and m.agents.filter(func(a):return a.visible).size()==1,"The 1v1 button activates exactly one opponent")
	m.begin_play()
	action("restart_match")
	check(m.duel_mode and m.phase==m.Phase.RESTART and m.flat_distance(m.player.position,m.agents[4].position)>3.5,"R resets 1v1 with usable initial separation")
	m.start_match(true)
	m.begin_play()
	frozen = m.time_left
	await frames(90)
	check(m.practice and not m.duel_mode and m.agents.filter(func(a):return a.visible).is_empty() and is_equal_approx(frozen,m.time_left),"Free practice keeps an empty untimed pitch")

	m.start_match(false)
	m.begin_play()
	park()
	m.player.position = Vector3(0,0.92,0)
	m.player.reset_view(0)
	m.ball.reset(Vector3(0,0,-0.62))
	var touches: int = m.ball.touch_count
	await frames(12)
	check(m.ball.carrier==m.player and m.ball.touch_count>touches,"A loose grounded ball is received by an actual foot contact")
	m.player.position = Vector3(0,0.92,-15)
	m.player.velocity = Vector3.ZERO
	m.player.foot.cancel()
	m.ball.reset(Vector3(0,0,-15.62))
	m.ball.take(m.player)
	m.player.action_cooldown = 0
	m.shot_charge = 0.4
	var shot: bool = m.release_shot()
	check(shot and m.stats.shots==0 and m.ball.carrier==m.player,"Shooting prepares a foot before releasing the ball")
	await frames(12)
	check(m.stats.shots==1 and not is_instance_valid(m.ball.carrier),"Shooting releases and records a shot on actual boot contact")
	await frames(90)
	check(m.scores[0]==1 and m.phase==m.Phase.GOAL,"A physical shot crosses the goal plane and scores")
	await frames(260)
	check(m.phase==m.Phase.PLAY and is_instance_valid(m.ball.carrier) and m.ball.carrier.team==1,"A goal restarts with the conceding team after both delays")
	var score: Array = m.scores.duplicate()
	m.ball.reset(Vector3(4.0,0,-30.4))
	m.ball.previous_position = Vector3(4.0,0.12,-29.9)
	m._check_boundaries()
	check(m.phase==m.Phase.RESTART and m.scores==score,"A shot outside the posts restarts without scoring")
	m.begin_play()
	m.time_left = 0.03
	await frames(4)
	check(m.phase==m.Phase.FINISHED and not m.player.input_enabled,"The match clock reaches a full-time result")
	action("restart_match")
	check(m.phase==m.Phase.COUNTDOWN and m.scores==[0,0],"R starts a fresh match after full time")

	for seed_value in [2077,991,12345]:
		clear_inputs()
		m.ai_enabled = true
		m.start_match(false)
		m.rng.seed = seed_value
		m.begin_play()
		Input.action_press("move_forward")
		var maximum_crowd := 0
		var maximum_pressers := 0
		var human_actions := 0
		var count := 0
		var finite := true
		var observed_states := {}
		while m.phase!=m.Phase.FINISHED and count<10000:
			await frames(1)
			count += 1
			finite = finite and m.ball.position.is_finite() and m.players.all(func(a):return a.position.is_finite() and a.velocity.length()<35)
			if m.phase==m.Phase.PLAY:
				var nearby := 0
				for agent in m.agents:
					if m.flat_distance(agent.position,m.ball.position)<3:
						nearby += 1
					observed_states[agent.defense.state] = true
				maximum_crowd = maxi(maximum_crowd,nearby)
				for team in range(2):
					var pressing := 0
					for agent in m.agents:
						if agent.team==team and is_instance_valid(agent.press_attacker):
							pressing += 1
					maximum_pressers = maxi(maximum_pressers,pressing)
				if m.ball.carrier==m.player and m.player.action_cooldown<=0 and count%75==0:
					if absf(m.player.position.z)<12:
						m.attempt_pass(m.player)
					else:
						m.shot_charge = 0.5
						m.release_shot()
					human_actions += 1
				if count%240==0:
					action("call_ball")
		var result := {"seed":seed_value,"physics_frames":count,"finished":m.phase==m.Phase.FINISHED,"finite":finite,"score":m.scores.duplicate(),"stats":m.stats.duplicate(),"maximum_ai_within_3m":maximum_crowd,"maximum_pressers_per_team":maximum_pressers,"human_actions":human_actions,"defense_states":observed_states.keys()}
		simulations.append(result)
		print("FULL_MATCH ",JSON.stringify(result))
		check(result.finished and finite,"Full 5v5 finishes with bounded physics for seed "+str(seed_value))
		check(result.stats.ai_passes>0 and result.stats.ai_shots>0 and result.stats.ai_tackles>0,"AI passes, shoots and contests possession for seed "+str(seed_value))
		check(maximum_pressers<=1 and maximum_crowd<=4,"One presser and distributed cover avoid a ball crowd for seed "+str(seed_value))
	clear_inputs()
	var failed := checks.filter(func(row):return not row.passed).size()
	var report := {"engine":Engine.get_version_info().string,"passed":checks.size()-failed,"failed":failed,"checks":checks,"simulations":simulations,"scope":"Engine GUI events, foot contacts, physical goals, match lifecycle and continuous input with nine live AI. No physical desktop input playtest."}
	if report_path!="":
		var f := FileAccess.open(report_path,FileAccess.WRITE)
		f.store_string(JSON.stringify(report,"\t"))
	print("MATCH_CHECKS ",checks.size()," FAILURES ",failed)
	quit(0 if failed==0 else 1)
