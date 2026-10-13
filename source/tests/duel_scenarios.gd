extends SceneTree
var m: Node3D
var folder := ""
var failures: Array[String] = []
var checks := 0
var rows: Array[Dictionary] = []
var outcomes: Array[Dictionary] = []
var case_name := ""
var tick := 0
var defender: FootballAgent
var touch_start := 0
var lost := 0
var maximum_gap := 0.0
var maximum_step := 0.0
var previous_ball := Vector3.ZERO
var states := {}
var attempts_start := 0
var hits_start := 0
var touches_valid := true

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report-dir="):
			folder = arg.trim_prefix("--report-dir=")
	if folder=="":
		folder = ProjectSettings.globalize_path("res://../verification/duel")
	DirAccess.make_dir_recursive_absolute(folder)
	call_deferred("run")

func require(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures.append(text)
	print("PASS " if ok else "FAIL ",text)

func vector(v: Vector3) -> Array:
	return [snappedf(v.x,0.0001),snappedf(v.y,0.0001),snappedf(v.z,0.0001)]

func release_inputs() -> void:
	for action in ["move_forward","move_back","move_left","move_right","sprint","shield","close_control"]:
		Input.action_release(action)

func frames(count: int, record := false) -> void:
	for i in range(count):
		await physics_frame
		if record:
			sample()

func reset_case(name: String, live := false) -> void:
	release_inputs()
	m.ai_enabled = live
	if live:
		m.start_duel()
	else:
		m.start_match(false)
	m.begin_play()
	for i in range(m.agents.size()):
		var agent: FootballAgent = m.agents[i]
		agent.position = Vector3(-17 if i%2==0 else 17,0.92,16+int(i/2)*2.5)
		agent.velocity = Vector3.ZERO
		agent.foot.cancel()
		agent.defense.reset()
		agent.tackle_cooldown = 0
	m.player.position = Vector3(0,0.92,0)
	m.player.velocity = Vector3.ZERO
	m.player.reset_view(0)
	m.player.foot.cancel()
	m.player.sole_stopped = false
	m.player.stop_requested = 0
	m.ball.reset(Vector3(0,0,-m.tuning.rest_distance))
	m.ball.take(m.player)
	if live:
		defender.position = Vector3(0,0.92,-3.0)
		defender.target = defender.position
		defender.home = defender.position
		defender.facing = Vector3.BACK
		m.assign_ai()
	await frames(8)
	case_name = name
	tick = 0
	lost = 0
	maximum_gap = 0
	maximum_step = 0
	previous_ball = m.ball.position
	touch_start = m.ball.touch_count
	attempts_start = defender.foot.attempts
	hits_start = defender.foot.hits
	states.clear()
	touches_valid = true

func sample() -> void:
	var gap: float = m.flat_distance(m.player.position,m.ball.position)
	maximum_gap = maxf(maximum_gap,gap)
	maximum_step = maxf(maximum_step,m.ball.position.distance_to(previous_ball))
	previous_ball = m.ball.position
	if m.ball.carrier!=m.player:
		lost += 1
	states[defender.defense.state] = true
	var contact_error: float = m.ball.last_contact_position.distance_to(m.ball.last_foot_position)
	if m.ball.touch_count>touch_start and contact_error>0.28:
		touches_valid = false
	rows.append({"case":case_name,"frame":tick,"player":vector(m.player.position),"ball":vector(m.ball.position),"velocity":vector(m.ball.velocity),"player_velocity":vector(m.player.velocity),"gap":gap,"owner":"human" if m.ball.carrier==m.player else "none" if not is_instance_valid(m.ball.carrier) else str(m.ball.carrier.jersey),"mode":m.ball.control_mode,"foot":m.player.foot.kind,"foot_phase":m.player.foot.phase,"toe":vector(m.player.foot.toe_world),"touches":m.ball.touch_count,"contact_error":contact_error,"defender":vector(defender.position),"defender_state":defender.defense.state,"defender_foot":defender.foot.kind,"defender_phase":defender.foot.phase})
	tick += 1

func finish_case(extra := {}) -> Dictionary:
	var result := {"case":case_name,"frames":tick,"lost_frames":lost,"max_gap":maximum_gap,"max_step":maximum_step,"end_gap":m.flat_distance(m.ball.position,m.player.position),"touches":m.ball.touch_count-touch_start,"end_player":vector(m.player.position),"end_ball":vector(m.ball.position),"defender_attempts":defender.foot.attempts-attempts_start,"defender_hits":defender.foot.hits-hits_start,"states":states.keys(),"contacts_at_feet":touches_valid}
	result.merge(extra)
	outcomes.append(result)
	print("DUEL_RESULT ",JSON.stringify(result))
	return result

func turn(angle: float) -> void:
	m.player.head.mouse_axis = Vector2(-angle/m.player.head.mouse_sensitivity,0)
	m.player.head.camera_rotation()

func run() -> void:
	m = load("res://scenes/match.tscn").instantiate()
	m.test_mode = true
	m.ai_enabled = false
	root.add_child(m)
	defender = m.agents[m.team_size-1]
	await frames(6)
	await reset_case("no_passive_steal")
	defender.position = Vector3(0.65,0.92,-0.62)
	await frames(24,true)
	require(m.ball.carrier==m.player and m.stats.ai_tackles==0,"A nearby opponent cannot steal a controlled ball without a foot action")
	finish_case()

	await reset_case("human_tackle")
	defender.position = Vector3(0,0.92,-1.35)
	defender.facing = Vector3.BACK
	m.ball.reset(Vector3(0,0,-0.72))
	m.ball.take(defender)
	var accepted: bool = m.attempt_tackle(m.player)
	require(accepted and m.ball.carrier==defender and m.stats.tackles==0,"Space commits a foot action without instant ownership or scoring")
	await frames(6,true)
	require(m.ball.carrier==defender and m.stats.tackles==0,"The ball remains untouched during tackle preparation")
	await frames(8,true)
	require(m.stats.tackles==1 and not is_instance_valid(m.ball.carrier),"Actual foot contact pokes a free ball rather than granting ownership")
	require(m.player.foot.hit and m.player.foot.recovery==m.tuning.tackle_hit_recover,"A successful tackle enters shared short recovery")
	finish_case()

	await reset_case("body_blocks_tackle")
	m.player.position = Vector3(0,0.92,1.0)
	defender.position = Vector3(0,0.92,0.45)
	defender.facing = Vector3.FORWARD
	m.ball.reset(Vector3(0,0,-0.12))
	m.ball.take(defender)
	require(not m.can_reach_ball(m.player),"A carrier body blocks a foot reaching through to a far-side ball")
	m.attempt_tackle(m.player)
	await frames(45,true)
	require(m.stats.tackles==0 and m.ball.carrier==defender,"Standing tackle does not pass through the carrier capsule")
	finish_case()

	await reset_case("miss_and_recovery")
	defender.position = Vector3(0,0.92,-1.35)
	defender.facing = Vector3.BACK
	m.ball.reset(Vector3(0,0,-0.72))
	m.ball.take(defender)
	m.player.reset_view(PI/2)
	m.attempt_tackle(m.player)
	var locked: Vector3 = m.player.foot.direction
	m.player.reset_view(0)
	await frames(19,true)
	Input.action_press("move_forward")
	await frames(14,true)
	require(m.player.foot.direction==locked and m.stats.tackles==0,"Changing camera aim cannot redirect a committed missed tackle")
	require(Vector2(m.player.velocity.x,m.player.velocity.z).length()<1.0,"A missed tackle limits movement during recovery")
	await frames(17,true)
	require(m.player.foot.misses>0,"An exposed miss produces a real recovery window")
	finish_case()

	await reset_case("shared_ai_tackle")
	defender.position = Vector3(0,0.92,-1.35)
	defender.facing = Vector3.BACK
	m.ball.reset(Vector3(0,0,-0.72))
	m.ball.take(m.player)
	m.attempt_tackle(defender)
	require(defender.foot.windup==m.tuning.tackle_prepare and defender.tackle_cooldown==m.tuning.tackle_cooldown,"AI and human use identical tackle timing and cooldown")
	await frames(14,true)
	require(m.stats.ai_tackles==1 and not is_instance_valid(m.ball.carrier),"AI also needs actual foot contact and creates a free ball")
	finish_case()

	for name in ["normal","close","sprint"]:
		await reset_case(name)
		Input.action_press("move_forward")
		if name=="close":
			Input.action_press("close_control")
		elif name=="sprint":
			Input.action_press("sprint")
		await frames(30,true)
		var half_second_speed := Vector2(m.player.velocity.x,m.player.velocity.z).length()
		await frames(150,true)
		var result := finish_case({"speed_at_half_second":half_second_speed})
		require(result.touches>=4 and result.end_gap<1.7,name+" supports repeated feet-based control and recollection")
		require(result.max_step<0.25 and result.contacts_at_feet,name+" contacts align with visible feet and remain continuous")
		if name=="normal":
			require(half_second_speed>3 and half_second_speed<4.8,"Starting motion accelerates progressively before reaching top speed")
		if name=="sprint":
			require(result.lost_frames>0,"A long push releases the ball into interceptible space")

	for spec in [["turn90",PI/2],["turn180",PI]]:
		await reset_case(spec[0])
		Input.action_press("move_forward")
		Input.action_press("close_control")
		await frames(65,true)
		turn(spec[1])
		await frames(150,true)
		release_inputs()
		await frames(40,true)
		var result := finish_case()
		require(result.end_gap<1.25 and result.touches>8 and result.contacts_at_feet,spec[0]+" turns and collects through foot contacts")

	await reset_case("stop_and_restart")
	Input.action_press("move_forward")
	await frames(80,true)
	release_inputs()
	var stop_ok: bool = m.ball.stop_at_foot(m.player)
	await frames(36,true)
	require(stop_ok and m.player.sole_stopped and Vector2(m.ball.velocity.x,m.ball.velocity.z).length()<0.2,"Space plants the ball after a timed near-foot contact")
	Input.action_press("move_right")
	await frames(100,true)
	var stopped := finish_case()
	require(stopped.end_player[0]>2 and stopped.touches>5 and stopped.end_gap<1.3,"A planted ball can start again in a new direction")

	for side in [-1,1]:
		await reset_case("duel_left" if side<0 else "duel_right",true)
		Input.action_press("move_forward")
		Input.action_press("close_control")
		await frames(22,true)
		Input.action_release("move_forward")
		Input.action_press("move_left" if side<0 else "move_right")
		await frames(32,true)
		Input.action_release("close_control")
		Input.action_press("move_forward")
		Input.action_press("sprint")
		await frames(75,true)
		Input.action_release("move_left" if side<0 else "move_right")
		await frames(30,true)
		var result := finish_case()
		var separation: float = m.flat_distance(m.player.position,defender.position)
		require(result.contacts_at_feet and result.max_step<0.55,"Live 1v1 has physical touches and continuous ball motion")
		require("JOCKEY" in result.states or "APPROACH" in result.states,"The defender chooses goal-side jockey or approach states")
		require(result.end_gap<1.7 and m.ball.position.z<defender.position.z-2.0,"A timed lateral change followed by a push can beat the defender with the ball")
		print("DUEL_SEPARATION ",case_name," ",separation)

	await reset_case("duel_patient_guard",true)
	Input.action_press("shield")
	await frames(150,true)
	var guard := finish_case()
	require(m.ball.carrier==m.player and guard.defender_attempts==0,"Patient goal-side defense does not blindly tackle a stationary protected ball")
	require(m.flat_distance(m.player.position,defender.position)>1.3,"A patient defender maintains a meaningful standoff distance")
	release_inputs()
	m.set_phase(m.Phase.MENU)
	var f := FileAccess.open(folder.path_join("report.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"failures":failures,"outcomes":outcomes}, "\t"))
	f.close()
	f = FileAccess.open(folder.path_join("trajectory.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify(rows))
	f.close()
	print("DUEL_CHECKS ",checks," FAILURES ",failures.size())
	quit(0 if failures.is_empty() else 1)
