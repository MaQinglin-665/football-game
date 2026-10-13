extends SceneTree
var m: Node3D
var checks: Array[Dictionary] = []
var outcomes: Array[Dictionary] = []
var report_path := ""
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			report_path = arg.trim_prefix("--report=")
	call_deferred("run")
func frames(count: int) -> void:
	for _i in range(count):
		await physics_frame
func check(ok: bool, name: String) -> void:
	checks.append({"name":name,"passed":ok})
	print("PASS " if ok else "FAIL ", name)
func park() -> void:
	for i in range(m.agents.size()):
		m.agents[i].position = Vector3(17 if i % 2 else -17,0.92,16+int(i/2)*2.5)
func snapshot() -> Array:
	return m.players.map(func(p):return Vector2(p.position.x,p.position.z))
func boundary_case(last_team: int, axis: int, clear_nearby: bool) -> void:
	m.ai_enabled = false
	m.start_match(false)
	m.begin_play()
	park()
	m.player.position = Vector3(0,0.92,-12)
	var near_agent: Node3D = m.agents[0] if last_team == 1 else m.agents[4]
	var receiving_team := 1-last_team
	var exit_point := Vector3(20.5,0.16,-5.2) if axis == 0 else Vector3(-7.4,0.16,30.5)
	near_agent.position = Vector3(16.8,0.92,-5.2) if axis == 0 else Vector3(-7.4,0.92,26.8)
	if clear_nearby:
		var other: Node3D = m.agents[4] if last_team == 1 else m.agents[0]
		other.position = Vector3(19.0,0.92,-5.2) if axis == 0 else Vector3(-7.4,0.92,29.0)
	await frames(3)
	var before := snapshot()
	var serial: int = m.formation_serial
	var time: float = m.time_left
	m.ball.carrier = null
	m.ball.last_touch_team = last_team
	m.ball.previous_position = exit_point - Vector3(0.7,0,0) if axis == 0 else exit_point-Vector3(0,0,0.7)
	m.ball.position = exit_point
	m._check_boundaries()
	var allowed: Array[Node3D] = [m.restart_taker]
	allowed.append_array(m.restart_clearances)
	var moved := []
	var unexpected := []
	for i in range(m.players.size()):
		var distance: float = before[i].distance_to(Vector2(m.players[i].position.x,m.players[i].position.z))
		if distance > 0.00001:
			moved.append({"jersey":m.players[i].jersey,"team":m.players[i].team,"distance":distance})
			if m.players[i] not in allowed:
				unexpected.append(m.players[i].name)
	var label := "side" if axis == 0 else "end"
	check(m.phase == m.Phase.RESTART and m.restart_team == receiving_team and m.ball.carrier == near_agent, label+" restart chooses the nearby teammate using last touch "+str(last_team))
	check(m.formation_serial == serial and unexpected.is_empty(), label+" restart preserves every actor except taker and local clearance")
	check(m.restart_taker != m.player and Vector2(m.player.position.x,m.player.position.z) == before[0], label+" restart keeps a distant human and camera in place")
	check(is_equal_approx(m.time_left,time) and m.scores == [0,0], label+" restart preserves match time and score")
	check(m.restart_clearances.size() == (1 if clear_nearby else 0), label+" restart clears only a nearby opponent")
	for cleared in m.restart_clearances:
		var index: int = m.players.find(cleared)
		check(before[index].distance_to(Vector2(cleared.position.x,cleared.position.z)) < 1.65, "Local clearance displacement stays small")
	await frames(45)
	var countdown_preserved := true
	for i in range(m.players.size()):
		if m.players[i] not in allowed and before[i].distance_to(Vector2(m.players[i].position.x,m.players[i].position.z)) > 0.02:
			countdown_preserved = false
	check(countdown_preserved,"Boundary countdown preserves all other on-field positions")
	await frames(30)
	check(m.phase == m.Phase.PLAY and m.ball.carrier == near_agent,"Boundary countdown resumes near the exit without a kickoff reset")
	outcomes.append({"case":"boundary_"+label,"last_touch_team":last_team,"taker":near_agent.jersey,"taker_team":near_agent.team,"moved":moved,"unexpected_movers":unexpected,"formation_serial":serial,"formation_serial_after":m.formation_serial,"ball_position":str(m.ball.position)})
func run() -> void:
	m = load("res://scenes/match.tscn").instantiate()
	m.test_mode = true
	m.ai_enabled = false
	root.add_child(m)
	await frames(5)
	for spec in [[0,0,false],[1,0,true],[0,2,true],[1,2,false]]:
		await boundary_case(spec[0],spec[1],spec[2])
	# A human near the boundary may take it without moving the whole squad.
	m.start_match(false)
	m.begin_play()
	park()
	m.player.position = Vector3(-18.5,0.92,2)
	m.ball.carrier = null
	m.ball.last_touch_team = 1
	m.ball.previous_position = Vector3(-19.9,0.16,2)
	m.ball.position = Vector3(-20.4,0.16,2)
	var serial: int = m.formation_serial
	m._check_boundaries()
	check(m.restart_taker == m.player and m.player.facing.x > 0.99 and m.formation_serial == serial, "A nearby human restarts inward with a close foot ball")

	# Live AI receives a player's pass, advances, then honors the E call.
	m.ai_enabled = true
	m.start_match(false)
	m.begin_play()
	park()
	m.player.position = Vector3(0,0.92,4)
	m.player.reset_view(0)
	m.ball.reset(Vector3(0,0,3.28))
	m.ball.take(m.player)
	var teammate: Node3D = m.agents[0]
	# Exercise an unobstructed return lane; opposition is covered by full-match tests.
	for other in m.agents:
		if other!=teammate:
			other.visible = false
			other.active = false
			other.collision_layer = 0
			other.collision_mask = 1
	teammate.position = Vector3(-2,0.92,-3)
	teammate.home = Vector3(-12,0.92,8)
	m.player.action_cooldown = 0
	var passed: bool = m.attempt_pass(m.player)
	var received := false
	var receiver_z := teammate.position.z
	for _i in range(100):
		await frames(1)
		if m.ball.carrier == teammate:
			received = true
			receiver_z = teammate.position.z
			break
	check(passed and received, "Live teammate actively moves to receive the human's rolling pass")
	await frames(110)
	var progressed: bool = teammate.position.z < receiver_z-1.8
	var holds: bool = m.ball.carrier == teammate
	print("RECEIVER_PROGRESS ",JSON.stringify({"start_z":receiver_z,"current":str(teammate.position),"holds":holds,"ball":str(m.ball.position),"mode":m.ball.control_mode,"age":m.ball.possession_age}))
	check(progressed and holds,"The receiving teammate carries the ball forward instead of waiting around it")
	# Move the human by real action input into a return lane; E uses the actual action event.
	Input.action_press("move_right")
	await frames(35)
	Input.action_release("move_right")
	await frames(15)
	var input := InputEventAction.new()
	input.action = "call_ball"
	input.pressed = true
	root.push_input(input,true)
	var targeted_human: bool = m.pass_receiver == m.player
	var returned := false
	var return_frames := 0
	for _i in range(240):
		await frames(1)
		return_frames += 1
		targeted_human = targeted_human or m.pass_receiver == m.player
		if _i % 30 == 0:
			print("RETURN_PROGRESS ",JSON.stringify({"frame":_i,"ball":str(m.ball.position),"velocity":str(m.ball.velocity),"carrier":str(m.ball.carrier),"call":m.call_timer,"receiver":str(m.pass_receiver),"prepare":teammate.pass_prepare,"pass_target":str(teammate.pass_target),"mode":m.ball.control_mode,"passes":m.stats.ai_passes}))
		if m.ball.carrier == m.player:
			returned = true
			break
	check(targeted_human and returned, "E call targets the human and the physical return pass is received")
	outcomes.append({"case":"pass_run_call_return","received":received,"receiver_advanced":progressed,"targeted_human":targeted_human,"return_received":returned,"return_seconds":return_frames/60.0,"stats":m.stats.duplicate(),"teammate":str(teammate.position),"human":str(m.player.position)})
	var failed := checks.filter(func(x):return not x.passed).size()
	var report := {"engine":Engine.get_version_info().string,"passed":checks.size()-failed,"failed":failed,"checks":checks,"outcomes":outcomes,"scope":"Actual football motion, live receiving AI, action-input call and position snapshots; no physical desktop input playtest"}
	if report_path != "":
		var file := FileAccess.open(report_path,FileAccess.WRITE)
		file.store_string(JSON.stringify(report,"\t"))
	print("COOP_AND_BOUNDARIES ",JSON.stringify(report))
	quit(0 if failed == 0 else 1)
