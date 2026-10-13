extends "res://addons/publisher_checks/role_test_base.gd"
var mobility: Node
var header_events: Array[Dictionary] = []
var desired: Dictionary = {}
var focus_repairs := 0
func _ready() -> void:
	if not "--interaction-min-check" in OS.get_cmdline_user_args():
		queue_free()
		return
	game = get_parent()
	game.test_mode = true
	game.ai_enabled = false
	native = DisplayServer.get_name() != "headless"
	process_physics_priority = -100
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="): evidence = arg.trim_prefix("--evidence=")
	call_deferred("run")
func _physics_process(_dt: float) -> void:
	if not is_instance_valid(game) or not is_instance_valid(game.input_bridge): return
	if not game.input_bridge.focused:
		focus_repairs += 1
		game.input_bridge.focused = true
		game.input_bridge.sync_context()
		for code in desired: super.key(int(code),true)
func key(code: int, down: bool) -> void:
	if is_instance_valid(game.input_bridge):
		game.input_bridge.focused = true
		game.input_bridge.sync_context()
	if down: desired[code]=true
	else: desired.erase(code)
	super.key(code,down)
func fixture() -> void:
	super.fixture()
	for i in game.agents.size():
		game.agents[i].position = Vector3(-10 if i%2 else 10,.002,-14+5*i)
		game.agents[i].target = game.agents[i].position
		game.agents[i].foot.cancel("interaction_min_fixture")
func pulse(code: int) -> void:
	key(code,true)
	await ticks(1)
	key(code,false)
func run() -> void:
	DirAccess.make_dir_recursive_absolute(evidence)
	await ticks(6)
	mobility = game.player.interaction
	mobility.action_event.connect(func(event: Dictionary):
		if event.get("action","")=="HEADER": header_events.append(event.duplicate(true)))
	check("default six actors real120Hz with additive interaction",game.players.size()==6 and Engine.physics_ticks_per_second==120 and mobility.input_conflicts.is_empty())
	game.hud.menu.get_node("StartMatch").pressed.emit()
	fixture()
	game.ball.reset(Vector3(10,.113,8))
	game.sync_input_context()
	await ticks(8)
	var observer := Camera3D.new()
	game.add_child(observer)
	observer.global_position=game.player.global_position+Vector3(3,1.7,1)
	observer.look_at(game.player.global_position+Vector3(0,1.1,0))
	observer.current=true
	for mesh in game.player.avatar.mesh_nodes: mesh.visible=true
	var original_bounds: Vector2 = mobility.vertical_bounds()
	key(KEY_B,true)
	await ticks(25)
	check("held B lowers actual body head and camera",mobility.crouch>.95 and mobility.head_center().y<1.25 and game.player.head.position.y<1.05,{"head":mobility.head_center(),"camera_y":game.player.head.position.y,"bounds":mobility.vertical_bounds()})
	await capture("crouch_actual_volume")
	key(KEY_B,false)
	await ticks(32)
	check("B release restores standing volume",mobility.crouch<.001 and mobility.permits_foot_action() and mobility.vertical_bounds().distance_to(original_bounds)<.01)
	await pulse(KEY_J)
	await ticks(20)
	check("J creates actual airborne root movement",mobility.phase=="AIRBORNE" and game.player.position.y>.4,{"root":game.player.position,"head":mobility.head_center()})
	var before_headers: int = mobility.headers
	var before_shots: int = game.stats.shots
	var head: Vector3 = mobility.head_center()
	# One declared moving-ball setup; no ball/actor writes after left-click.
	game.ball.position=head+game.player.facing*.88
	game.ball.previous_position=game.ball.position
	game.ball.velocity=-game.player.facing*6+Vector3.UP*game.player.velocity.y
	mouse(MOUSE_BUTTON_LEFT,true)
	await ticks(1)
	mouse(MOUSE_BUTTON_LEFT,false)
	await ticks(8)
	await capture("actual_aerial_header")
	await ticks(35)
	check("air leftclick produces one true head sweep contact",mobility.headers==before_headers+1 and not header_events.is_empty(),header_events)
	if not header_events.is_empty():
		var hit: Dictionary=header_events.back()
		check("actual high head sphere window finite bounded impulse",hit.source=="engine_sweep" and float(hit.separation)<=mobility.HEAD_RADIUS+game.ball.radius+.009 and (hit.head_center as Vector3).y>2 and (hit.impulse as Vector3).length()>.5 and (hit.impulse as Vector3).length()<=6.001,hit)
		var velocity_before: Vector3=game.ball.velocity
		for i in 4:game.player.resolve_interaction_ball_contact(game.ball,hit.point)
		check("same header cannot apply a second impulse",game.ball.velocity==velocity_before and mobility.headers==before_headers+1)
	check("header creates one real rule shot",game.stats.shots==before_shots+1 and game.services.rules.last_touch.get("surface")=="HEAD",game.services.rules.last_touch)
	await ticks(120)
	check("landing restores ordinary foot permission",mobility.phase=="GROUNDED" and mobility.permits_foot_action())
	await pulse(KEY_J)
	await ticks(20)
	mouse(MOUSE_BUTTON_LEFT,true)
	await ticks(1)
	mouse(MOUSE_BUTTON_LEFT,false)
	mouse(MOUSE_BUTTON_MIDDLE,true)
	await ticks(1)
	mouse(MOUSE_BUTTON_MIDDLE,false)
	await ticks(8)
	check("middle cancels aerial attempt",mobility.header_phase=="IDLE")
	await ticks(130)
	var roll: String=game.get_node("TurfRollAB").mode
	await pulse(KEY_F7)
	check("F7 rolling still toggles",game.get_node("TurfRollAB").mode!=roll)
	await pulse(KEY_F7)
	var audio: bool=game.services.audio.recorded_impacts_enabled
	await pulse(KEY_F8)
	check("F8 audio still toggles",game.services.audio.recorded_impacts_enabled!=audio)
	await pulse(KEY_F8)
	var reps: int=game.training_mode.repetitions
	await pulse(KEY_R)
	await ticks(3)
	check("R still resets training",game.training_mode.repetitions==reps+1)
	var passed: bool=checks.all(func(row):return row.passed)
	FileAccess.open(evidence.path_join("INTERACTION_MINIMAL_025.json"),FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"checks":checks,"header_events":header_events,"native":native,"frames":frames,"captures":captures,"focus_repairs":focus_repairs,"scope":"Actual exported default3v3; AIoff; one actor starting fixture, one declared movingball header fixture; true World head contact, crouch, jump, cancellation, F7F8R; no49rerun/fullmatch/manualfeel/FPS"},"\t"))
	print("INTERACTION_MINIMAL025_DONE passed=",passed," checks=",checks.size())
	reparent(get_tree().root)
	game.pause_match()
	game.shutdown_audio()
	game.queue_free()
	game=null
	for i in 4: await process_frame
	quit(0 if passed else 1)
