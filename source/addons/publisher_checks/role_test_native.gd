extends "res://addons/publisher_checks/role_test_base.gd"
## One short real019 3v3 activation check. No broad QA, render or FPS claim.
var pass_events: Array[Dictionary] = []
var raw_pass: Dictionary = {}
var warm_receives: Array[Dictionary] = []
var warm_samples: Array[Dictionary] = []
var warm_capture_meshes: Array[bool] = []
var desired_keys: Dictionary = {}
var focus_repairs := 0
var previous_eye := Vector3.ZERO
var warm_observer: Camera3D

func fixture() -> void:
	super.fixture()
	# Keep the reused receive fixture's five agents within this smaller pitch.
	for i in game.agents.size():
		var actor: Node3D = game.agents[i]
		actor.position = Vector3(-10.0 if i%2 else 10.0,.002,-14.0+5.0*i)
		actor.target = actor.position
		actor.foot.cancel("role_batch03_fixture")

func _ready() -> void:
	if not "--role-action-check" in OS.get_cmdline_user_args():
		queue_free()
		return
	process_physics_priority = -100
	game = get_parent()
	game.test_mode = true
	native = DisplayServer.get_name() != "headless"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="): evidence = arg.trim_prefix("--evidence=")
	call_deferred("run")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(evidence)
	AudioServer.set_bus_mute(0,true)
	game.ai_enabled = false
	game.contact_hub.contact_resolved.connect(func(event: Dictionary):
		if event.get("actor")==game.player and event.get("action","")=="RECEIVE" and event.get("success",false): warm_receives.append(event.duplicate(true))
		if event.get("actor") == game.player and event.get("action","") == "PASS" and event.get("success",false):
			raw_pass = event.duplicate(true)
			pass_events.append({"sequence":event.get("action_sequence",-1),"point":event.point,"after_velocity":event.after_velocity})
	)
	await ticks(6)
	for actor in game.players: actor.refresh_pose(1.0/120.0) # Menu AI is disabled; exercise actual lazy pose binding.
	var bound: bool = game.players.all(func(actor):return bool(actor.avatar.role_batch_debug().rig_bind_ok))
	check("actual019 six actors/120Hz/shared rig/pass and stance adapters bind",game.players.size()==6 and Engine.physics_ticks_per_second==120 and bound and game.player.avatar.pass_bind_ok)
	game.hud.menu.get_node("StartMatch").pressed.emit()
	var received := await receive()
	await ticks(14)
	game.player.foot.cancel("role_batch03_ready")
	game.player.refresh_pose(0)
	check("live training possession acquired through actual RECEIVE",received and game.phase==game.Phase.PLAY and game.ball.carrier==game.player)
	var before: Vector3 = game.ball.velocity
	var request := {"action":"pass_ground","direction":Vector3.FORWARD,"power":.25,"elevation_deg":0.0,"spin":Vector3.ZERO}
	var accepted: bool = game.player.foot.request_semantic_kick(request)
	check("low-speed short pass accepted without an early ball impulse",accepted and game.ball.velocity==before)
	var observer := Camera3D.new()
	game.add_child(observer)
	observer.global_position = game.player.global_position + Vector3(2,1.4,-2)
	observer.look_at(game.player.global_position + Vector3(0,.85,0))
	observer.current = true
	await capture("before_pass")
	var style_seen := false
	for i in 56:
		await ticks(1)
		style_seen = style_seen or game.player.avatar.pass_pose.samples>0
		if i in [8,18,30]: await capture("pass_phase_"+str(i))
	check("one actual PASS contact/released moving ball/authored body samples",style_seen and pass_events.size()==1 and game.ball.carrier!=game.player and game.ball.velocity.length()>.1,{"events":pass_events,"foot_result":game.player.foot.last_result,"pass_samples":game.player.avatar.pass_pose.samples})
	var audio: Node = game.services.audio
	var audio_id := "impact-foot:%d:%d" % [game.player.get_instance_id(),int(raw_pass.get("action_sequence",-1))]
	var mixes: Array = audio.recent_mix.filter(func(row): return row.event_id == audio_id)
	check("real pass has exactly one audio voice",mixes.size()==1,mixes)
	var expected := "recorded_" if audio.recorded_impacts_enabled else "physical"
	check("A/B selected bank used by actual contact",mixes.size()==1 and String(mixes[0].bank).begins_with(expected))
	var played: int = audio.diagnostics.played
	audio.consume_resolved_contact(raw_pass)
	check("duplicate actual pass event creates no second voice",audio.diagnostics.played==played)
	var old_mode: bool = audio.recorded_impacts_enabled
	key(KEY_F8,true)
	key(KEY_F8,false)
	await ticks(1)
	check("F8 changes only existing director bank",audio.recorded_impacts_enabled!=old_mode and game.services.audio==audio and game.get_node("TurfRollAB").mode=="B")
	key(KEY_F8,true)
	key(KEY_F8,false)
	await ticks(1)
	check("F8 restores audio A/B mode",audio.recorded_impacts_enabled==old_mode)
	for _wait_tick in 120:
		if game.player.foot.idle(): break
		await ticks(1)
	check("pass recovered before independent C stance check",game.player.foot.idle(),{"kind":game.player.foot.kind,"phase":game.player.foot.phase})
	key(KEY_C,true)
	await ticks(24)
	await capture("defence_stance")
	var active_stance: Dictionary = game.player.avatar.role_batch_debug()
	check("off-ball C pressure applies modest defence stance",game.player.foot.idle() and float(active_stance.defence_weight)>.8 and bool(active_stance.pose_applied),{"role":active_stance,"kind":game.player.foot.kind,"phase":game.player.foot.phase,"owns":game.ball.carrier==game.player,"semantic":game.player.semantic_motion})
	key(KEY_C,false)
	await ticks(25)
	await capture("restored_pose")
	observer.current = false
	game.player.camera.current = true
	await capture("first_person")
	var restored: Dictionary = game.player.avatar.role_batch_debug()
	check("pressure release restores base pose and leaves no role override",float(restored.defence_weight)==0.0 and not bool(restored.pose_applied),restored)
	var eye_anchor: Vector3 = game.player.to_local(game.player.camera.global_position)
	previous_eye = eye_anchor
	warm_observer = observer
	for mesh in game.player.avatar.mesh_nodes:
		warm_capture_meshes.append(mesh.visible)
		mesh.visible = true
	key(KEY_W,true)
	await warm_ticks(120,"free_acceleration",eye_anchor)
	key(KEY_SHIFT,true)
	await warm_ticks(72,"free_run",eye_anchor)
	key(KEY_SHIFT,false)
	key(KEY_W,false)
	await warm_ticks(96,"free_stop",eye_anchor)
	var free_rows: Array = warm_samples.filter(func(row):return row.body.get("free_transition_applied",false))
	check("actual offball free walk/run blend applied",not free_rows.is_empty(),free_rows.size())
	check("animated eye finite with no over80mm single120Hz tick jump",warm_samples.all(func(row):return is_finite(float(row.eye_step_m)) and float(row.eye_step_m)<.08),warm_samples.map(func(row):return row.eye_step_m).max())
	check("free blend weights finite and bounded",warm_samples.all(func(row):return is_finite(float(row.body.jog_blend)) and float(row.body.jog_blend)>=0 and float(row.body.jog_blend)<=1 and is_finite(float(row.body.sprint_blend)) and float(row.body.sprint_blend)>=0 and float(row.body.sprint_blend)<=1))
	check("actual offball medium and high speed running",warm_samples.any(func(row):return row.speed>3.5) and warm_samples.any(func(row):return row.speed>5.0),warm_samples.map(func(row):return row.speed).max())
	check("running leans forward and brakes toward upright",warm_samples.any(func(row):return row.stage=="free_run" and float(row.body.free_lean_radians)<-.10) and absf(float(warm_samples[-1].body.free_lean_radians))<.10)
	for i in game.player.avatar.mesh_nodes.size():game.player.avatar.mesh_nodes[i].visible=warm_capture_meshes[i]
	# One declared ball-only receive fixture after warm real actor gait history.
	# Actor/root/feet/pose/proxy history are not reset or relocated.
	game.ball.reset(game.player.global_position+game.player.facing*.58+Vector3.UP*.111)
	game.sync_input_context() # Ball-only fixture must update semantic reach context before Space.
	var count_before: int = warm_receives.size()
	key(KEY_SPACE,true)
	await warm_ticks(1,"warm_receive_request",eye_anchor)
	key(KEY_SPACE,false)
	await warm_ticks(55,"warm_actual_receive",eye_anchor)
	check("warm free gait receives through actual shoe",game.ball.carrier==game.player and warm_receives.size()>count_before,{"contacts":warm_receives.size()-count_before,"owned":game.ball.carrier==game.player,"last":game.player.foot.last_result})
	key(KEY_CTRL,true)
	key(KEY_W,true)
	await warm_ticks(84,"warm_held_close",eye_anchor)
	key(KEY_W,false)
	key(KEY_CTRL,false)
	check("active actual foot actions leave free blend immediately",warm_samples.all(func(row):return row.kind.is_empty() or not bool(row.body.free_transition_applied)))
	check("023 held support interface and methods remain active",game.player.avatar.has_method("get_control_support_snapshot") and warm_samples.any(func(row):return row.body.get("control_phase",{}).get("eligible",false)))
	await capture("warm_free_to_held_first_person")
	var passed := checks.all(func(row):return row.passed)
	FileAccess.open(evidence.path_join("PASS_DEFENCE_MINIMAL_03.json"),FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"checks":checks,"scope":"Combined021 exact EXE short fixture actual RECEIVE/PASS/body samples/C stance restoration; native captures; no performance/fullmatch claim","frames":frames,"warm_samples":warm_samples,"warm_actual_receive_count":warm_receives.size(),"QA_focus_repairs":focus_repairs,"QA_focus_policy":"Synthetic background QA only: context focused and held key sources restored after native OS focus loss; production guards unchanged"},"\t")+"\n")
	print("PASS_DEFENCE_MINIMAL_03_DONE passed=",passed," checks=",checks.size())
	reparent(get_tree().root)
	game.pause_match()
	game.shutdown_audio()
	game.queue_free()
	game = null
	for i in 4: await process_frame
	quit(0 if passed else 1)

func warm_ticks(count: int, tag: String, eye_anchor: Vector3) -> void:
	for i in count:
		await ticks(1)
		var body: Dictionary = game.player.avatar.get_full_body_debug()
		var current_eye: Vector3 = game.player.to_local(game.player.camera.global_position)
		var eye_error: float = current_eye.distance_to(eye_anchor)
		var eye_step: float = current_eye.distance_to(previous_eye)
		previous_eye = current_eye
		warm_samples.append({"stage":tag,"tick":Engine.get_physics_frames(),"kind":game.player.foot.kind,"phase":game.player.foot.phase,"body":body,"speed":game.player.velocity.length(),"owned":game.ball.carrier==game.player,"eye_error_m":eye_error,"eye_step_m":eye_step})

	if tag in ["free_acceleration","free_run","free_stop"] and is_instance_valid(warm_observer):
		warm_observer.global_position=game.player.global_position+Vector3(2.8,1.3,.6)
		warm_observer.look_at(game.player.global_position+Vector3(0,.9,0))
		warm_observer.current=true
		await capture(tag+"_side")
		warm_observer.current=false
		game.player.camera.current=true

func ensure_qa_focus() -> void:
	if not is_instance_valid(game) or not is_instance_valid(game.input_bridge): return
	var bridge: Node = game.input_bridge
	if not bridge.focused or not bool(bridge.adapter.router.context.get("focused",true)):
		focus_repairs += 1
		bridge.focused = true
		bridge.sync_context()
		for code in desired_keys: super.key(int(code),true)
func _physics_process(_dt: float) -> void:
	ensure_qa_focus()
func key(code: int, pressed: bool) -> void:
	ensure_qa_focus()
	if pressed: desired_keys[code] = true
	else: desired_keys.erase(code)
	super.key(code,pressed)
