extends SceneTree
var game: Node
var checks: Array[Dictionary] = []
var failures: Array[String] = []
var held_keys: Dictionary = {}
var held_mouse: Dictionary = {}
var report_root := ""
var visual := false

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks.append({"passed":ok,"label":label})
	if not ok:
		failures.append(label)
	print("PASS " if ok else "FAIL ",label)

func key(code: int, down: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = down
	held_keys[code] = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func mouse(button: int, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = down
	event.position = Vector2(720,470)
	held_mouse[button] = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func release_all() -> void:
	for code in held_keys.keys():
		if held_keys[code]:
			key(code,false)
	for button in held_mouse.keys():
		if held_mouse[button]:
			mouse(button,false)

func wait_seconds(seconds: float) -> void:
	for frame in range(maxi(1,int(ceil(seconds*Engine.physics_ticks_per_second)))):
		await physics_frame
	await process_frame

func stage(owned := true) -> void:
	release_all()
	game.set_physics_process(true)
	game.input_bridge.adapter.reset("test_stage")
	game.player.foot.cancel()
	game.player.action_cooldown = 0
	game.player.tackle_cooldown = 0
	game.player.stop_requested = 0
	game.player.sole_stopped = false
	game.player.position = Vector3(0,0.901,0)
	game.player.velocity = Vector3.ZERO
	game.player.reset_view(0)
	game.player.set_semantic_movement(Vector3.ZERO,"run")
	game.player.semantic_policies.clear()
	game.player.long_touch = false
	game.hud.help.hide()
	game.set_phase(game.Phase.PLAY)
	game.ball.reset(Vector3(0,0,-0.62))
	game.ball.position.y = 0.11
	game.ball.possession_grace = 0
	game.ball.last_kick_intent.clear()
	if owned:
		game.ball.take(game.player)
	game.input_bridge.sync_context()
	game.input_bridge.adapter.set_aim(Vector3.FORWARD)
	if not owned:
		game.set_physics_process(false)
		game.ball.set_physics_process(false)
	await wait_seconds(0.025)

func capture(name: String) -> void:
	if not visual:
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(report_root.path_join(name+".png"))

func run() -> void:
	visual = "--visual-evidence" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless"
	report_root = ProjectSettings.globalize_path("res://").path_join("../verification").simplify_path()
	game = load("res://scenes/match.tscn").instantiate()
	game.test_mode = true
	game.ai_enabled = false
	root.add_child(game)
	await wait_seconds(0.05)
	game.start_match(true)
	game.begin_play()
	await stage()
	check(Engine.physics_ticks_per_second==120,"host runs semantic input at 120Hz")
	check(game.player.external_input and not game.player.get_node("Sprint").is_physics_processing(),"legacy movement and sprint consumers disabled")
	check(game.input_bridge.adapter.router.catalog.error.is_empty(),"runtime action profile is present")
	var initial_z: float = game.player.position.z
	key(KEY_W,true)
	await wait_seconds(0.35)
	check(game.player.position.z < initial_z-0.20,"real W event moves the player through host motor")
	key(KEY_CTRL,true)
	await wait_seconds(0.08)
	check(game.player.close_control and game.player.semantic_move_style=="walk","Ctrl policy reaches dribble and movement")
	key(KEY_SHIFT,true)
	key(KEY_C,true)
	await wait_seconds(0.08)
	check(game.player.shielding and not game.player.sprinting,"shield takes priority over close and long touch")
	release_all()
	await stage()
	var shots: int = game.stats.shots
	mouse(MOUSE_BUTTON_LEFT,true)
	await wait_seconds(0.30)
	check(not game.input_bridge.charge_preview.is_empty() and game.stats.shots==shots,"charge previews without striking or scoring")
	await capture("input_host_01_charge")
	mouse(MOUSE_BUTTON_LEFT,false)
	check(game.stats.shots==shots and game.ball.carrier==game.player,"release schedules windup without immediate physics")
	await wait_seconds(0.30)
	check(game.stats.shots==shots+1 and game.ball.carrier!=game.player,"actual foot contact executes exactly one shot")
	check(game.ball.last_kick_intent.get("action","")=="shoot_straight" and game.ball.last_kick_intent.get("power",0.0)>0.45,"normalized command survives until physical contact")
	check(game.input_bridge.charge_preview.is_empty(),"commit closes charge preview")
	await stage()
	var passes: int = game.stats.passes
	key(KEY_Q,true)
	mouse(MOUSE_BUTTON_RIGHT,true)
	await wait_seconds(0.12)
	key(KEY_Q,false)
	await wait_seconds(0.04)
	check(game.stats.passes==passes and not game.input_bridge.charge_preview.is_empty(),"Q release waits for held RMB alias")
	mouse(MOUSE_BUTTON_RIGHT,false)
	await wait_seconds(0.25)
	check(game.stats.passes==passes+1,"Q and RMB invoke one physical pass")
	check(game.ball.last_kick_intent.get("elevation_deg",-1)==0,"ground pass keeps independent zero loft")
	await stage()
	shots = game.stats.shots
	key(KEY_W,true)
	mouse(MOUSE_BUTTON_LEFT,true)
	await wait_seconds(0.15)
	key(KEY_ESCAPE,true)
	await wait_seconds(0.02)
	check(game.phase==game.Phase.PAUSED and game.input_bridge.charge_preview.is_empty(),"Esc cancels preview and pauses once")
	mouse(MOUSE_BUTTON_LEFT,false)
	key(KEY_ESCAPE,false)
	key(KEY_ESCAPE,true)
	key(KEY_ESCAPE,false)
	await wait_seconds(0.16)
	check(game.phase==game.Phase.PLAY and game.stats.shots==shots,"paused release cannot produce stale shot")
	check(game.player.semantic_motion.length()<0.01,"W held across pause remains blocked")
	key(KEY_W,false)
	key(KEY_W,true)
	await wait_seconds(0.08)
	check(game.player.semantic_motion.length()>0.9,"release and re-press restores movement")
	await stage()
	shots = game.stats.shots
	mouse(MOUSE_BUTTON_LEFT,true)
	await wait_seconds(0.15)
	game.ball.detach()
	check(game.input_bridge.charge_preview.is_empty(),"possession loss cancels charge synchronously")
	mouse(MOUSE_BUTTON_LEFT,false)
	await wait_seconds(0.25)
	check(game.stats.shots==shots,"loss and recollection do not replay old release")
	await stage()
	passes = game.stats.passes
	key(KEY_F,true)
	key(KEY_Q,true)
	await wait_seconds(0.10)
	key(KEY_Q,false)
	key(KEY_F,false)
	await wait_seconds(0.20)
	check(game.stats.passes==passes and game.input_bridge.charge_preview.is_empty(),"unavailable high pass never falls back to ground pass")
	await stage()
	shots = game.stats.shots
	mouse(MOUSE_BUTTON_LEFT,true)
	await wait_seconds(0.10)
	key(KEY_X,true)
	await wait_seconds(0.06)
	check(game.input_bridge.charge_preview.is_empty(),"unsupported spin cancels preview immediately")
	mouse(MOUSE_BUTTON_LEFT,false)
	key(KEY_X,false)
	await wait_seconds(0.20)
	check(game.stats.shots==shots,"unsupported spin does not produce straight shot")
	await stage()
	key(KEY_SPACE,true)
	key(KEY_SPACE,false)
	check(game.player.foot.kind=="STOP" and not game.player.foot.hit,"Space requests timed sole stop")
	await wait_seconds(0.20)
	check(game.player.sole_stopped,"sole stop completes on contact")
	await stage()
	key(KEY_CTRL,true)
	key(KEY_D,true)
	await wait_seconds(0.04)
	game.player.foot.cancel()
	key(KEY_SPACE,true)
	key(KEY_SPACE,false)
	check(game.player.foot.kind=="TURN","Ctrl directional chord requests one nudge")
	await stage(false)
	game.ball.set_physics_process(false)
	game.player.foot.cancel()
	game.input_bridge.sync_context()
	key(KEY_SPACE,true)
	key(KEY_SPACE,false)
	check(game.player.foot.kind=="RECEIVE" and not is_instance_valid(game.ball.carrier),"free-ball Space prepares foot without assigning ownership")
	game.ball.set_physics_process(true)
	game.set_physics_process(true)
	await wait_seconds(0.12)
	check(game.ball.carrier==game.player,"receive ownership follows actual contact")
	await stage()
	game.set_phase(game.Phase.RESTART)
	game.state_clock = 2
	initial_z = game.player.position.z
	key(KEY_W,true)
	await wait_seconds(0.20)
	check(game.player.position.z < initial_z-0.08,"dead-ball wait retains player movement")
	var yaw: float = game.player.rotation.y
	game.player.head.mouse_axis = Vector2(35,0)
	if game.player.head.enabled:
		game.player.head.camera_rotation()
	check(game.player.head.enabled and absf(game.player.rotation.y-yaw)>0.01,"dead-ball wait retains camera input path")
	await capture("input_host_03_dead_ball")
	await stage()
	mouse(MOUSE_BUTTON_LEFT,true)
	await wait_seconds(0.10)
	key(KEY_F1,true)
	key(KEY_F1,false)
	await wait_seconds(0.05)
	check(game.hud.help.visible and game.input_bridge.context.ui_captured and game.input_bridge.charge_preview.is_empty(),"help captures input and cancels active charge")
	check("暂未开放" in game.hud.help_body.text,"help reflects actual capabilities")
	await capture("input_host_02_help")
	key(KEY_ESCAPE,true)
	key(KEY_ESCAPE,false)
	mouse(MOUSE_BUTTON_LEFT,false)
	await wait_seconds(0.04)
	check(not game.hud.help.visible and game.phase==game.Phase.PLAY,"Esc closes help without also pausing")
	var report := {"checks":checks,"failures":failures,"physics_hz":Engine.physics_ticks_per_second,"integration":"input + baseline motor/foot; pending other modules","contacts":game.contact_hub.export_records(),"input_intents":game.input_bridge.traces.size()}
	var file := FileAccess.open(report_root.path_join("input_integration_test_results.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print("INPUT_INTEGRATION_CHECKS ",checks.size()," FAILURES ",failures.size())
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
