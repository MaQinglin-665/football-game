extends SceneTree
## Publisher-only opt-in fixture on the production match, no keeper demo scene.
var game: Node3D
var host: Node
var keeper: Node3D
var opponent: Node3D
var checks: Array[Dictionary] = []
var evidence := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="): evidence = arg.trim_prefix("--evidence=")
	call_deferred("run")

func ticks(count: int) -> void:
	for i in count: await physics_frame

func check(label: String, ok: bool) -> void:
	checks.append({"label":label,"passed":ok})
	print("PASS " if ok else "FAIL ",label)

func count_event(kind: String) -> int:
	return host.records.filter(func(row): return row.kind == kind).size()

func stage(fast := false, outside := false, backpass := false) -> void:
	game.ball.clear_control(true)
	host.records.clear()
	host.release_blocked_actor = 0
	for state: Dictionary in host.keeper_states: state.backpass_forbidden = false
	game.set_phase(game.Phase.PLAY)
	game.services.rules._second_touch_actor = -1
	game.services.rules._become_live() # Fixture setup only; not production code.
	for actor in game.players:
		actor.set_physics_process(false)
		actor.velocity = Vector3.ZERO
		actor.set_move_intent(Vector3.ZERO)
		actor.position = Vector3(20 + actor.team*3, 0.002, actor.jersey*1.4)
	keeper.position = Vector3(0,.002,34.0 if outside else 44.0)
	keeper.facing = Vector3.FORWARD
	keeper.body_facing = Vector3.FORWARD
	keeper.face_target = Vector3.FORWARD
	keeper.active = true
	keeper.refresh_pose(0)
	keeper.avatar.visual.global_rotation = Vector3.ZERO
	game.ball.reset(keeper.position + Vector3(0,1.30,-1.35))
	game.ball.set_held(false)
	game.ball.apply_impulse_ns((Vector3(0,.90,10.0 if fast else 4.0)-game.ball.velocity)*game.ball.mass_kg)
	game.services.rules.last_touch = {"actor_id":opponent.get_instance_id(),"team":opponent.team,"kind":"shot"}
	if backpass:
		host._on_rule_event({"type":"ball_contact","contact":{"actor_id":game.player.get_instance_id(),"team":keeper.team,"kind":"pass"}})
		# Recipient/body touch and a generic foot clear must not legalize it.
		host._on_rule_event({"type":"ball_contact","contact":{"actor_id":keeper.get_instance_id(),"team":keeper.team,"kind":"body"}})
		host.external_clear("fixture_foot_detach")
	game.pass_receiver = null
	game.pass_receiver_timer = 0.0

func run() -> void:
	if evidence.is_empty(): quit(2); return
	AudioServer.set_bus_mute(0,true)
	game = load("res://scenes/match.tscn").instantiate()
	game.test_mode = true
	game.ai_enabled = false
	root.add_child(game)
	await ticks(3)
	game.start_match(false)
	host = game.get_node("KeeperActions04")
	keeper = game.players.filter(func(a): return a.is_goalkeeper and a.team == 0)[0]
	opponent = game.players.filter(func(a): return a.team != keeper.team)[0]
	check("production match has 22 actors and two keeper states",game.players.size()==22 and host.states.size()==2)
	stage()
	await ticks(150)
	check("production hook catches at one real dual-hand contact",count_event("GK_HAND_CONTACT")==1 and count_event("GK_RETAIN_CONFIRMED")==1)
	check("one actual hand release returns free ball physics",count_event("GK_RELEASE_ACCEPTED")==1 and not game.ball.held and game.ball.carrier==null and host.hand_owner==null)
	stage(true)
	await ticks(65)
	check("fast incoming ball parried once without retain",count_event("GK_PARRY_CONFIRMED")==1 and count_event("GK_RETAIN_CONFIRMED")==0)
	stage(false,true)
	await ticks(65)
	check("outside own penalty area excludes hand contact",count_event("GK_HAND_CONTACT")==0 and host.hand_owner==null)
	stage(false,false,true)
	await ticks(65)
	check("backpass survives own torso contact and foot clear",count_event("GK_HAND_CONTACT")==0 and host.hand_owner==null)
	stage()
	await ticks(55)
	check("cancel test first obtains confirmed hand ownership",host.hand_owner==keeper)
	game.ball.clear_control(true)
	check("external cancel cannot orphan a held GK ball",host.hand_owner==null and not game.ball.held and game.ball.control_mode=="LOOSE")
	stage()
	await ticks(55)
	check("restart test first obtains hand ownership",host.hand_owner==keeper)
	game.services.rules._queue_restart("goal_kick",keeper.team,keeper.position,"fixture_restart")
	check("referee restart takes control without GK owner",host.hand_owner==null and game.ball.held and host.control_state().mode=="RESTART")
	stage()
	await ticks(55)
	check("down test first obtains hand ownership",host.hand_owner==keeper)
	# Current fall API requires confirmed collision evidence; this is a fixture only.
	check("existing physical down-state entry accepts hit",keeper.down_state.enter_hit("keeper038-fixture-hit",Vector3.FORWARD,.45,{"contact":true,"speed":7.0,"cause":"extended_leg"}))
	await ticks(2)
	check("down cancels hand owner and frees actual ball",host.hand_owner==null and not game.ball.held)
	finish()

func finish() -> void:
	DirAccess.make_dir_recursive_absolute(evidence)
	var passed := checks.all(func(row): return row.passed)
	FileAccess.open(evidence.path_join("KEEPER_038_CONTACT.json"),FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"checks":checks,"scope":"Production match hooks; isolated physical trajectory fixture. No natural AI/FPS/native proof.","arm_samples":host.arm_sample_count,"sweeps":host.sweep_query_count},"\t"))
	game.pause_match()
	game.shutdown_audio()
	game.queue_free()
	await ticks(2)
	quit(0 if passed else 1)
