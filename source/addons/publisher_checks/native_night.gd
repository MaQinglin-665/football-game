extends "res://addons/publisher_checks/native_dribble.gd"
## Three real FP camera views, F4 fallback, then a short real control chain.
var views: Array[Dictionary] = []
var mode_checks: Array[Dictionary] = []

func set_view(yaw: float, pitch: float) -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	var look := InputEventMouseMotion.new()
	look.relative=Vector2((game.player.head.rot.y-yaw)/game.player.head.mouse_sensitivity,(game.player.head.rot.x-pitch)/game.player.head.mouse_sensitivity)
	Input.parse_input_event(look)
	Input.flush_buffered_events()

func toggle_f4() -> void:
	key(KEY_F4,true)
	key(KEY_F4,false)

func night_state() -> Dictionary:
	var world: WorldEnvironment = game.get_node("MatchEnvironment")
	var main: DirectionalLight3D = game.get_node("MatchSun")
	var rig: Node3D = game.stadium.get_node("NightFixtureRig")
	var lights: Array = game.find_children("*","Light3D",true,false)
	return {"mode":world.get_meta("stadium_lighting_mode",""),"quality":world.get_meta("stadium_night_quality",""),"all_lights":lights.size(),"active_lights":lights.filter(func(l):return l.is_visible_in_tree() and l.light_energy>0).size(),"shadowed_lights":lights.filter(func(l):return l.is_visible_in_tree() and l.shadow_enabled).size(),"main_mask":main.light_cull_mask,"shadow_distance":main.directional_shadow_max_distance,"rig_visible":rig.visible,"bank_count":rig.bank_positions.size(),"cost":rig.cost_contract(),"msaa":root.msaa_3d,"far_enabled":game.stadium.get_meta("far_clarity_enabled",false)}

func snapshot_view(tag: String) -> void:
	for _i in 8:await process_frame
	await capture(tag)
	var screen: Vector2 = game.player.camera.unproject_position(game.ball.global_position)
	views.append({"tag":tag,"state":night_state(),"camera":game.player.camera.global_transform,"fov":game.player.camera.fov,"ball":game.ball.position,"ball_screen":screen,"in_view":not game.player.camera.is_position_behind(game.ball.position) and root.get_visible_rect().has_point(screen),"owned":game.ball.carrier==game.player,"physics_frame":Engine.get_physics_frames(),"time_scale":Engine.time_scale})

func run() -> void:
	game=load("res://scenes/match.tscn").instantiate()
	game.test_mode=true
	root.add_child(game)
	for _i in 3:await tick()
	game.ai_enabled=false
	game.services.rules.state=game.Rules.State.LIVE
	game.services.rules.restart.clear()
	game.set_phase(game.Phase.PLAY)
	game.services.configuration.half_seconds=600
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	for agent in game.agents:
		agent.refresh_pose(0)
		agent.pose_updates_enabled=false
	game.contact_hub.contact_resolved.connect(func(e:Dictionary):
		if e.actor==game.player:touch_events.append({"action":e.action,"success":e.success,"point":e.point,"sequence":e.get("action_sequence",-1)}))
	fixture()
	stage="initial_receive"
	key(KEY_SPACE,true);await tick();key(KEY_SPACE,false)
	for _i in 45:await tick()
	check("night acquires through one actual RECEIVE",game.ball.carrier==game.player and touch_events.any(func(e):return e.action=="RECEIVE" and e.success))
	var initial := night_state()
	check("ordinary night LOW one main zero new dynamic eight banks",initial.mode=="night" and initial.quality=="low" and initial.all_lights==1 and initial.active_lights==1 and initial.shadowed_lights==1 and initial.bank_count==8 and initial.cost.geometry_instances==2 and initial.cost.triangles==356,initial)
	check("farstands AA0 roster22 physics120 inherited",initial.far_enabled and root.msaa_3d==Viewport.MSAA_DISABLED and game.players.size()==22 and Engine.physics_ticks_per_second==120 and is_equal_approx(Engine.time_scale,1.0))
	# Freeze only simulation for exact mode/camera still comparison. Head._input
	# and F4 stay real; live controls below resume the same ball without a reset.
	game.set_process(false)
	game.set_physics_process(false)
	game.physics_world.set_physics_process(false)
	game.ball.set_physics_process(false)
	for actor in game.players:actor.set_physics_process(false)
	game.hud.visible=false
	if "--lamp-only" in OS.get_cmdline_user_args():
		stage="roof_bank"
		set_view(deg_to_rad(60.0),deg_to_rad(36.0))
		await snapshot_view("night_roof_bank_first")
		check("one actualEXE lamp view saved",capture_records.size()==1 and capture_records[0].result==OK)
		var lamp_report := {"passed":checks.all(func(c):return c.passed),"total":checks.size(),"checks":checks,"views":views,"captures":capture_records,"gpu":RenderingServer.get_video_adapter_name(),"focus_recoveries":focus_recoveries,"physics_hz":Engine.physics_ticks_per_second,"ticket":ticket,"scope":"First single actualEXE FP roof view only; metadata checks not aesthetic acceptance. Inspect this image before full3views/performance."}
		FileAccess.open(evidence.path_join("native_night_lamp_first.json"),FileAccess.WRITE).store_string(JSON.stringify(lamp_report,"\t")+"\n")
		print("NATIVE_NIGHT_LAMP_DONE valid=",lamp_report.passed)
		release_inputs();game.pause_match();game.shutdown_audio();game.queue_free();game=null
		for _i in 4:await process_frame
		quit(0 if lamp_report.passed else 1)
		return
	var state_before := {"player":game.player.position,"ball":game.ball.position,"velocity":game.ball.velocity,"carrier":game.ball.carrier,"kind":game.player.foot.kind,"sequence":game.player.foot.sequence,"elapsed":game.player.foot.elapsed}
	for view in [{"name":"ball_down","yaw":0.0,"pitch":deg_to_rad(-48.0)},{"name":"midfield_goal","yaw":0.0,"pitch":deg_to_rad(-3.0)},{"name":"roof_bank","yaw":deg_to_rad(60.0),"pitch":deg_to_rad(36.0)}]:
		stage=view.name
		set_view(view.yaw,view.pitch)
		await snapshot_view("night_"+view.name)
		toggle_f4()
		var day := night_state()
		check("F4 daylight restores light/layers and hides banks "+view.name,day.mode=="daylight" and not day.rig_visible and day.main_mask!=(1<<19) and day.far_enabled and day.active_lights==1,day)
		await snapshot_view("day_"+view.name)
		toggle_f4()
		var night := night_state()
		check("F4 returns to same LOW budget "+view.name,night.mode=="night" and night.rig_visible and night.all_lights==1 and night.active_lights==1 and night.shadowed_lights==1 and night.bank_count==8 and night.msaa==0,night)
		mode_checks.append({"view":view.name,"day":day,"night":night})
	var state_after := {"player":game.player.position,"ball":game.ball.position,"velocity":game.ball.velocity,"carrier":game.ball.carrier,"kind":game.player.foot.kind,"sequence":game.player.foot.sequence,"elapsed":game.player.foot.elapsed}
	check("mode fallback preserves frozen physics/contact state",state_after==state_before)
	check("low-ball actualFP projection inside viewport",views.any(func(v):return v.tag=="night_ball_down" and v.in_view and v.owned))
	set_view(0,deg_to_rad(-48.0))
	game.set_process(true)
	game.set_physics_process(true)
	game.physics_world.set_physics_process(true)
	game.ball.set_physics_process(true)
	for actor in game.players:actor.set_physics_process(true)
	var live_start := path.size()
	var contacts_start := touch_events.size()
	var live_from: Vector3 = game.player.position
	stage="night_live_turn"
	for i in 360:
		if i==0:inputs([KEY_W])
		if i==120:inputs([KEY_W,KEY_D])
		if i==240:inputs([KEY_W,KEY_SHIFT])
		await tick()
		if i==180:await snapshot_view("night_live_turn")
	inputs([])
	var live_rows: Array = path.slice(live_start)
	var live_hits: Array = touch_events.slice(contacts_start).filter(func(e):return e.success)
	check("night real input/contact chain keeps ball after mode views",not live_hits.is_empty() and live_rows.all(func(r):return r.owned and r.gap<1.1) and game.player.position.distance_to(live_from)>1.0,{"contacts":live_hits.size(),"movement_m":game.player.position.distance_to(live_from)})
	check("night native stills written",capture_records.size()==7 and capture_records.all(func(c):return c.result==OK))
	var report := {"passed":checks.all(func(c):return c.passed),"total":checks.size(),"checks":checks,"views":views,"captures":capture_records,"mode_checks":mode_checks,"live_rows":live_rows,"contacts":touch_events,"focus_recoveries":focus_recoveries,"gpu":RenderingServer.get_video_adapter_name(),"physics_hz":Engine.physics_ticks_per_second,"time_scale":Engine.time_scale,"roster":game.players.size(),"ticket":ticket,"scope":"Actual exported EXE, actual playerFP camera and injected MouseMotion/F4/RECEIVE/W/WD/Shift edges. Six deterministic day/night stills at3camera views, then a3sim-second real contact chain from the same ball. Only still comparison pauses physics;22physical bodies,AI decisions/distant pose updates off for functional imagery. Full-resolution screenshots and camera projection require separate visual review; not whole-match performance. No actor/ball/ownership resets after initial RECEIVE."}
	FileAccess.open(evidence.path_join("native_night_012.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("NATIVE_NIGHT_DONE valid=",report.passed," checks=",checks.size())
	release_inputs();game.pause_match();game.shutdown_audio();game.queue_free();game=null
	for _i in 4:await process_frame
	quit(0 if report.passed else 1)
