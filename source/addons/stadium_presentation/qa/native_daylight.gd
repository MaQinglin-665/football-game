extends Node
## Baseline-balanced vs sky/palette/low. Same gameplay, resolution and inputs; render quality differences are recorded.
## Wall-clock sampling; no fixed-fps, pose disabling, or mid-run gameplay resets.
var game: Node3D
var evidence := ""
var condition := ""
@onready var root: Window = get_tree().root
@onready var process_frame: Signal = get_tree().process_frame
@onready var physics_frame: Signal = get_tree().physics_frame
var runs: Array[Dictionary] = []
var ticket := ""
var held: Array[int] = []
var mode := "native"
var pass_contacts := 0
var pass_receives := 0
var pass_start := 0
var last_stamp := 0
var last_physics := 0
var rows: Array[Array] = []
var captures_list: Array[Dictionary] = []
var run_valid := true

func _ready() -> void:
	evidence = ProjectSettings.globalize_path("res://../verification/native_daylight")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="): evidence = arg.trim_prefix("--evidence=")
		if arg.begins_with("--exclusive-render-ticket="): ticket = arg.trim_prefix("--exclusive-render-ticket=")
		if arg.begins_with("--profile="): mode = arg.trim_prefix("--profile=")
		if arg.begins_with("--condition="): condition = arg.trim_prefix("--condition=")
	if DisplayServer.get_name()=="headless" or ticket.is_empty():
		print("Native test requires exclusive release GPU ticket")
		quit(2)
		return
	if condition not in ["on","off"]:
		print("Daylight probe requires --condition=on or off; render quality is deliberately different")
		quit(2)
		return
	root.set_meta("release_visual_baseline",condition=="off")
	call_deferred("run")

func quit(code: int = 0) -> void:
	get_tree().quit(code)

func keys(next: Array) -> void:
	for code in held:
		if not next.has(code): key(code,false)
	for code in next:
		if not held.has(code): key(code,true)
	held.clear()
	for code in next: held.append(code)

func p(values: Array, fraction: float) -> float:
	if values.is_empty(): return 0.0
	var ordered := values.duplicate()
	ordered.sort()
	return float(ordered[clampi(ceili(ordered.size()*fraction)-1,0,ordered.size()-1)])

func metrics(values: Array) -> Dictionary:
	if values.is_empty(): return {}
	var total: float = values.reduce(func(a,b): return a+b,0.0)
	return {"mean":total/values.size(),"p50":p(values,.5),"p95":p(values,.95),"p99":p(values,.99),"max":p(values,1.0)}

func run() -> void:
	DirAccess.make_dir_recursive_absolute(evidence)
	AudioServer.set_bus_mute(0,true)
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	var entries := [{"enabled":false,"name":"A1_off"},{"enabled":true,"name":"B1_on"},{"enabled":true,"name":"B2_on"},{"enabled":false,"name":"A2_off"}]
	if mode=="carry": entries = entries.slice(0,2)
	if condition in ["on","off"]: entries = [{"enabled":condition=="on","name":condition}]
	if mode=="visual": entries = []
	for entry in entries:
		await perf_pass(entry)
	if mode!="carry": await visual_pass()
	var combined := {}
	for enabled in [false,true]:
		var all_rows: Array[Array] = []
		for item in runs:
			if item.daylight_enabled == enabled: all_rows.append_array(item.samples)
		combined["on" if enabled else "off"] = summarize(all_rows)
	var report := {"engine":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),
		"render_method":RenderingServer.get_current_rendering_method(),"reservation":ticket,
		"resolution":root.get_visible_rect().size,"physics_hz":Engine.physics_ticks_per_second,"profile":mode,
		"vsync":"disabled for both conditions","max_fps":0,"passes":runs,"combined":combined,
		"captures":captures_list,"fixture_valid":run_valid,
		"columns":["wall_frame_ms","engine_frame_cpu_ms","physics_iteration_cpu_ms","viewport_render_cpu_ms","viewport_render_gpu_ms","render_setup_cpu_ms","draw_calls","physics_steps_in_frame","human_owned","actors_moving_over_0_1_mps","input_stage","human_ball_gap_m"],
		"scope":"Single native renderer; deliberate render-quality differences are included in each pass, baseline-balanced vs sky/palette/low; independent process per pass in release replay. Same seeded fresh 22-player scene, AI/World/poses/audio systems active, identical wall-timed W/WA/WD/W+Shift/W inputs. One initial LIVE/spatial fixture and real RECEIVE per pass, no subsequent ball/actor/ownership reset. Warmup and scene load excluded and separately recorded; no screenshot reads during measured passes.",
		"limits":["Opt-in runtime probe; release EXE run must be identified by launcher evidence. Not human feel/full-match acceptance.","Input timeline is identical but AI/physics state can diverge with actual frame pacing; per-pass simulation ticks, contacts, ownership and movement recorded.","Engine CPU/physics monitors are aggregate and may be delayed. Physics iteration includes GDScript and native physics; no separate whole-match script/Jolt attribution.","Zero renderer timing readouts are unavailable, not zero GPU/CPU cost.","Fixed-camera paused screenshot fixture occurs after timing; screenshots do not establish live FPS."]}
	FileAccess.open(evidence.path_join("FRAME_TIME_ABBA.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("PERF_COMBINED ",JSON.stringify(combined))
	print("NATIVE_DONE valid=",run_valid)
	quit(0 if run_valid else 1)

func summarize(data: Array[Array]) -> Dictionary:
	var times := data.map(func(r): return r[0])
	var total: float = times.reduce(func(a,b): return a+b,0.0)
	return {"frames":data.size(),"wall_seconds":total/1000.0,"average_fps":data.size()*1000.0/maxf(total,.001),
		"frame_ms":metrics(times),"over_16_67_ms":times.filter(func(v):return v>16.6667).size(),
		"over_33_33_ms":times.filter(func(v):return v>33.3333).size(),"over_50_ms":times.filter(func(v):return v>50.0).size(),
		"over_100_ms":times.filter(func(v):return v>100.0).size(),
		"engine_frame_cpu_ms":metrics(data.map(func(r):return r[1])),
		"physics_iteration_cpu_ms":metrics(data.map(func(r):return r[2])),
		"viewport_render_cpu_ms":metrics(data.map(func(r):return r[3])),
		"viewport_render_gpu_ms":metrics(data.map(func(r):return r[4])),
		"render_setup_cpu_ms":metrics(data.map(func(r):return r[5])),
		"draw_calls":metrics(data.map(func(r):return r[6])),
		"physics_steps_in_frame":metrics(data.map(func(r):return r[7])),
		"human_owned_fraction":float(data.filter(func(r):return r[8]).size())/maxi(1,data.size()),
		"actors_moving":metrics(data.map(func(r):return r[9]))}

func perf_pass(entry: Dictionary) -> void:
	seed(20261003)
	keys([])
	pass_contacts = 0
	pass_receives = 0
	var load_start := Time.get_ticks_usec()
	game = load("res://scenes/match.tscn").instantiate()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	await process_frame
	game.start_match(false)
	game.services.configuration.half_seconds = 600.0
	game.services.rules.state = game.Rules.State.LIVE
	game.services.rules.restart.clear()
	game.rule_snapshot = game.services.rules.snapshot()
	game.set_phase(game.Phase.PLAY)
	fixture()
	game.player.position.z = 30.0
	game.ball.position = Vector3(0,.113,29.42)
	game.ball.previous_position = game.ball.position
	game.player.head.rotation.x = deg_to_rad(-8.0)
	game.contact_hub.contact_resolved.connect(func(e: Dictionary):
		if e.actor==game.player and e.success:
			pass_contacts += 1
			if e.action=="RECEIVE": pass_receives += 1)
	key(KEY_SPACE,true)
	await physics_frame
	key(KEY_SPACE,false)
	for _i in 45: await physics_frame
	var acquired: bool = game.ball.carrier==game.player and pass_receives>0
	run_valid = run_valid and acquired and game.players.size()==22 and game.ai_enabled
	var load_ms := (Time.get_ticks_usec()-load_start)/1000.0
	keys([KEY_W])
	var warmup_start := Time.get_ticks_usec()
	while Time.get_ticks_usec()-warmup_start<(1200000 if mode=="carry" else 2000000): await process_frame
	var starts: Array[Vector3] = []
	for actor in game.players: starts.append(actor.position)
	var physics_start := Engine.get_physics_frames()
	rows.clear()
	pass_start = Time.get_ticks_usec()
	last_stamp = pass_start
	last_physics = physics_start
	while Time.get_ticks_usec()-pass_start<(10000000 if mode=="carry" else 18000000):
		var elapsed := (Time.get_ticks_usec()-pass_start)/1000000.0
		var stage_id := 0 if elapsed<6.0 else 1 if elapsed<9.0 else 2 if elapsed<12.0 else 3 if elapsed<15.0 else 4
		if mode=="carry": stage_id = 0 if elapsed<1.0 else 1 if elapsed<2.0 else 2 if elapsed<3.0 else 3 if elapsed<5.0 else 4
		keys([KEY_W] if stage_id in [0,4] else [KEY_W,KEY_A] if stage_id==1 else [KEY_W,KEY_D] if stage_id==2 else [KEY_W,KEY_SHIFT])
		# Same view trajectory on both conditions; no actor position/ball reset.
		game.player.turn_view(.12*sin(elapsed*.8))
		await process_frame
		var stamp := Time.get_ticks_usec()
		var moving := 0
		for actor in game.players:
			if Vector2(actor.velocity.x,actor.velocity.z).length()>.1: moving += 1
		var pf := Engine.get_physics_frames()
		rows.append([(stamp-last_stamp)/1000.0,Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0,
			RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()),
			RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),
			RenderingServer.get_frame_setup_time_cpu(),Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			pf-last_physics,game.ball.carrier==game.player,moving,stage_id,game.flat_distance(game.player.position,game.ball.position)])
		last_stamp = stamp
		last_physics = pf
	keys([])
	var displaced := 0
	for index in starts.size():
		if game.players[index].position.distance_to(starts[index])>.3: displaced += 1
	var ownership_by_stage := {}
	for stage_id in 5:
		var at := rows.filter(func(row): return row[10]==stage_id)
		ownership_by_stage[str(stage_id)] = {"frames":at.size(),"owned_frames":at.filter(func(row):return row[8]).size()}
	var record := {"player_instance_id":game.player.get_instance_id(),"ball_instance_id":game.ball.get_instance_id(),"initial_physics_frame":physics_start,"render_config":{"msaa":root.msaa_3d,"quality":game.get_node("MatchEnvironment").get_meta("daylight_profile","baseline_balanced"),"shadow_distance":game.get_node("MatchSun").directional_shadow_max_distance,"seat_near":game.stadium.seat_lod_near_distance,"seat_mid":game.stadium.seat_lod_mid_distance,"grass_close_detail":game.services.materials.slots.pitch_grass.get_shader_parameter("close_detail_enabled")},"name":entry.name,"daylight_enabled":entry.enabled,"scene_and_acquisition_wall_ms":load_ms,
		"real_receive":acquired,"real_human_contacts":pass_contacts,"ai_enabled":game.ai_enabled,"roster":game.players.size(),
		"actors_displaced_over_0_3m":displaced,"simulation_ticks":Engine.get_physics_frames()-physics_start,
		"ownership_by_stage":ownership_by_stage,
		"input_stages":rows.map(func(r):return r[10]),
		"summary":summarize(rows),"samples":rows.duplicate(true)}
	runs.append(record)
	print("PERF_PASS ",entry.name," ",JSON.stringify(record.summary))
	game.pause_match()
	game.shutdown_audio()
	game.queue_free()
	game = null
	for _i in 4: await process_frame

func visual_pass() -> void:
	keys([])
	Engine.max_fps = 60
	game = load("res://scenes/match.tscn").instantiate()
	game.test_mode = true
	root.add_child(game)
	game.start_match(false)
	game.pause_match()
	game.hud.visible = false
	var camera := Camera3D.new()
	camera.fov = 96.0
	camera.near = .04
	camera.far = 350.0
	root.add_child(camera)
	camera.current = true
	for item in [{"name":"pitch_eye","at":Vector3(23,1.6,8),"target":Vector3(0,1.2,-52.5)},
		{"name":"roof_sky","at":Vector3(0,1.6,0),"target":Vector3(0,25,-76)},
		{"name":"ground_shadow","at":Vector3(0,1.6,4),"target":Vector3(0,0,0)}]:
		camera.position = item.at
		camera.look_at(item.target,Vector3.UP)
		game.stadium.update_detail_for_camera(camera.position)
		for _i in 8: await process_frame
		await RenderingServer.frame_post_draw
		var file: String = ("baseline_" if condition=="off" else "low_")+item.name+".png"
		root.get_texture().get_image().save_png(evidence.path_join(file))
		captures_list.append({"file":file,"camera":camera.position,"target":item.target,"quality":game.get_node("MatchEnvironment").get_meta("daylight_profile","baseline_balanced")})
	game.shutdown_audio()
	game.queue_free()
	camera.queue_free()
	game = null
	for _i in 4: await process_frame

func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func fixture() -> void:
	# Reproducible starting positions; normal 22-player AI and swept World stay on.
	keys([])
	game.ball.clear_control()
	game.ball.set_held(false)
	game.player.position = Vector3(0,.002,8)
	game.player.velocity = Vector3.ZERO
	game.player.reset_view(0)
	game.player.action_cooldown = 0
	game.player.tackle_cooldown = 0
	game.player.stop_requested = 0
	game.player.sole_stopped = false
	game.ball.position = Vector3(0,.113,7.42)
	game.ball.previous_position = game.ball.position
	game.ball.velocity = Vector3.ZERO
	game.ball.spin_rads = Vector3.ZERO
	game.ball.pickup_block = 0
	game.ball.touch_timer = 0
	game.ball.control_mode = "LOOSE"
	for i in game.agents.size():
		var agent: Node3D = game.agents[i]
		agent.position = Vector3(-28.0 if i%2 else 28.0,.002,-43.0+4.2*i)
		agent.velocity = Vector3.ZERO
		agent.target = agent.position
	game.sync_input_context()
