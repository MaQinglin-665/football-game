extends Node
var match_controller: Node3D
var folder := ""
var captures: Array[Dictionary] = []

func _ready() -> void:
	match_controller.test_mode = true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			folder = arg.trim_prefix("--capture-dir=")
	if folder=="":
		folder = ProjectSettings.globalize_path("res://../verification/native")
	DirAccess.make_dir_recursive_absolute(folder)
	call_deferred("run")

func frames(count: int) -> void:
	for i in range(count):
		await get_tree().physics_frame

func clear_inputs() -> void:
	for action in ["move_forward","move_back","move_left","move_right","sprint","shield","close_control"]:
		Input.action_release(action)

func reset_case(live := false) -> void:
	var m := match_controller
	clear_inputs()
	m.ai_enabled = live
	if live:
		m.start_duel()
	else:
		m.start_match(false)
	m.begin_play()
	for i in range(m.agents.size()):
		m.agents[i].position = Vector3(-17 if i%2==0 else 17,0.92,16+int(i/2)*2.5)
		m.agents[i].velocity = Vector3.ZERO
	m.player.position = Vector3(0,0.92,0)
	m.player.velocity = Vector3.ZERO
	m.player.reset_view(0)
	m.player.foot.cancel()
	m.ball.reset(Vector3(0,0,-m.tuning.rest_distance))
	m.ball.take(m.player)
	if live:
		m.agents[4].position = Vector3(0,0.92,-3)
		m.agents[4].facing = Vector3.BACK
		m.assign_ai()
	await frames(8)

func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var m := match_controller
	var img := get_viewport().get_texture().get_image()
	var error := img.save_png(folder.path_join(name+".png"))
	var screen: Vector2 = m.player.camera.unproject_position(m.ball.position)
	var visible: bool = not m.player.camera.is_position_behind(m.ball.position) and Rect2(Vector2.ZERO,get_viewport().get_visible_rect().size).has_point(screen)
	captures.append({"name":name,"saved":error==OK,"player":str(m.player.position),"ball":str(m.ball.position),"ball_screen":str(screen),"ball_in_view":visible,"foot":m.player.foot.kind,"phase":m.player.foot.phase,"defender_foot":m.agents[4].foot.kind,"defender_phase":m.agents[4].foot.phase,"defender_state":m.agents[4].defense.state,"camera_pitch":rad_to_deg(m.player.head.rot.x),"camera_fov":m.player.camera.fov})
	print("CAPTURE ",name)

func run() -> void:
	var m := match_controller
	await frames(10)
	await capture("01-menu")
	m.ai_enabled = true
	m.start_match(false)
	m.begin_play()
	await frames(30)
	await capture("02-five-a-side")
	await reset_case()
	await capture("03-rest-football")
	Input.action_press("move_forward")
	Input.action_press("close_control")
	await frames(62)
	await capture("04-short-touch")
	m.player.head.mouse_axis = Vector2(-(PI/2)/m.player.head.mouse_sensitivity,0)
	m.player.head.camera_rotation()
	for i in range(6):
		await frames(6)
		await capture("05-turn90-%02d"%i)
	clear_inputs()
	await reset_case()
	Input.action_press("move_forward")
	Input.action_press("close_control")
	await frames(62)
	m.player.head.mouse_axis = Vector2(-PI/m.player.head.mouse_sensitivity,0)
	m.player.head.camera_rotation()
	for i in range(6):
		await frames(6)
		await capture("06-turn180-%02d"%i)
	await frames(40)
	await capture("06-turn180-collected")
	clear_inputs()
	await reset_case(true)
	Input.action_press("move_forward")
	Input.action_press("close_control")
	await frames(22)
	Input.action_release("move_forward")
	Input.action_press("move_left")
	for i in range(8):
		await frames(4)
		await capture("07-duel-feint-%02d"%i)
	Input.action_release("close_control")
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await frames(75)
	Input.action_release("move_left")
	await frames(30)
	await capture("08-breakthrough")
	clear_inputs()
	await reset_case()
	var opponent: FootballAgent = m.agents[4]
	opponent.position = Vector3(0,0.92,-1.35)
	opponent.facing = Vector3.BACK
	opponent.refresh_legs()
	m.ball.reset(Vector3(0,0,-0.72))
	m.ball.take(opponent)
	m.attempt_tackle(m.player)
	await frames(5)
	await capture("09-tackle-prepare")
	await frames(5)
	await capture("10-tackle-contact")
	await frames(12)
	await capture("11-tackle-recover")
	m.pause_match()
	await frames(3)
	await capture("12-pause")
	var f := FileAccess.open(folder.path_join("captures.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify(captures,"\t"))
	get_tree().quit()
