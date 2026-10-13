extends SceneTree
## Read-only rendered pose observer. Starting physical fixtures only; all 22
## actors, normal foot actions, tactics, referee and swept World remain active.
var game: Node
var frames := 0
var samples: Array[Dictionary] = []
var evidence := ""
var native := false
var captures := 0
var front_camera: Camera3D
var side_camera: Camera3D
var stage := ""

func _initialize() -> void:
	evidence = ProjectSettings.globalize_path("res://../verification/pose_baseline")
	native = DisplayServer.get_name()!="headless"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="): evidence = arg.trim_prefix("--evidence=")
	DirAccess.make_dir_recursive_absolute(evidence)
	call_deferred("run")

func key(code: int, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = down
	Input.parse_input_event(e)
	Input.flush_buffered_events()

func release() -> void:
	for code in [KEY_W,KEY_S,KEY_A,KEY_D,KEY_SHIFT,KEY_CTRL,KEY_SPACE,KEY_Q]: key(code,false)

func fixture(ball_present := true) -> void:
	release()
	game.ball.clear_control()
	game.ball.set_held(false)
	game.player.position = Vector3(0,.002,8)
	game.player.velocity = Vector3.ZERO
	game.player.reset_view(0)
	game.player.action_cooldown = 0
	game.player.stop_requested = 0
	game.player.sole_stopped = false
	game.ball.position = Vector3(0,.113,7.5) if ball_present else Vector3(22,.113,-20)
	game.ball.previous_position = game.ball.position
	game.ball.velocity = Vector3.ZERO
	game.ball.spin_rads = Vector3.ZERO
	game.ball.pickup_block = 0
	game.ball.touch_timer = 0
	for i in game.agents.size():
		game.agents[i].position = Vector3(-28.0 if i%2 else 28.0,.002,-43.0+4.2*i)
		game.agents[i].velocity = Vector3.ZERO
	game.sync_input_context()

func observer(name: String, offset: Vector2) -> Camera3D:
	var vp := SubViewport.new()
	vp.size = Vector2i(400,300)
	vp.world_3d = root.world_3d
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var camera := Camera3D.new()
	camera.fov = 50
	camera.current = true
	vp.add_child(camera)
	var view := TextureRect.new()
	view.texture = vp.get_texture()
	view.position = offset
	view.size = Vector2(400,300)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.hud.add_child(view)
	var label := Label.new()
	label.text = name
	label.position = offset+Vector2(8,8)
	game.hud.add_child(label)
	return camera

func sample() -> void:
	var sk: Skeleton3D = game.player.avatar.skeleton
	var row := {"frame":frames,"stage":stage,"foot_action":game.player.foot.kind,"phase":game.player.foot.phase,"clip":game.player.avatar._clip,"locomotion":game.player.locomotion,"ball_gap":game.flat_distance(game.player.position,game.ball.position),"ball_height":game.ball.position.y,"weight_shift":game.player.avatar.weight_shift,"owned":game.ball.carrier==game.player}
	for side in ["L","R"]:
		var hip := sk.to_global(sk.get_bone_global_pose(sk.find_bone("thigh."+side)).origin)
		var knee := sk.to_global(sk.get_bone_global_pose(sk.find_bone("shin."+side)).origin)
		var ankle := sk.to_global(sk.get_bone_global_pose(sk.find_bone("foot."+side)).origin)
		var sole := sk.to_global(sk.get_bone_global_pose(sk.find_bone("contact_sole."+side)).origin)
		var thigh := knee-hip
		var shin := ankle-knee
		row[side] = {"hip":hip-game.player.position,"knee":knee-game.player.position,"ankle":ankle-game.player.position,"sole_height":sole.y,"thigh_forward_deg":rad_to_deg(atan2(thigh.dot(game.player.facing),-thigh.y)),"knee_flex_deg":rad_to_deg(thigh.angle_to(shin)),"upper_length":thigh.length(),"lower_length":shin.length()}
	samples.append(row)

func ticks(count: int, record := false) -> void:
	for _i in count:
		await physics_frame
		frames += 1
		if record:
			if frames%4==0: sample()
			if native and frames%4==0:
				front_camera.position = game.player.position+Vector3(0,1.05,-3.1)
				front_camera.look_at(game.player.position+Vector3(0,.86,0))
				side_camera.position = game.player.position+Vector3(3.1,1.0,0)
				side_camera.look_at(game.player.position+Vector3(0,.86,0))
				await process_frame
				await RenderingServer.frame_post_draw
				captures += 1
				root.get_texture().get_image().save_png(evidence.path_join("frame_%05d.png" % captures))

func run() -> void:
	game = load("res://scenes/match.tscn").instantiate()
	game.test_mode = true
	root.add_child(game)
	game.start_match(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	for _i in 2400:
		await ticks(1)
		if game.is_restart_taker(game.player): break
	key(KEY_Q,true)
	await ticks(40)
	key(KEY_Q,false)
	await ticks(60)
	if native:
		# Spectator views see the same complete skinned rig. The FP camera keeps
		# head/core hidden using a camera layer, without creating a second body.
		for mesh in game.player.avatar.mesh_nodes:
			if String(mesh.name) in ["Head","BodyCore"]:
				mesh.visible = true
				mesh.layers = 2
		game.player.head.cam.cull_mask &= ~2
		front_camera = observer("FRONT | normal-speed",Vector2(24,70))
		side_camera = observer("SIDE | normal-speed",Vector2(440,70))
	stage = "walk_no_ball"
	fixture(false)
	key(KEY_CTRL,true)
	key(KEY_W,true)
	await ticks(240,true)
	stage = "jog_no_ball"
	fixture(false)
	key(KEY_W,true)
	await ticks(240,true)
	stage = "close_dribble"
	fixture()
	key(KEY_SPACE,true)
	await ticks(1)
	key(KEY_SPACE,false)
	await ticks(28)
	key(KEY_CTRL,true)
	key(KEY_W,true)
	await ticks(480,true)
	stage = "normal_dribble"
	fixture()
	key(KEY_SPACE,true)
	await ticks(1)
	key(KEY_SPACE,false)
	await ticks(28)
	key(KEY_W,true)
	await ticks(480,true)
	release()
	FileAccess.open(evidence.path_join("pose.json"),FileAccess.WRITE).store_string(JSON.stringify({"native":native,"physics_hz":120,"capture_fps_simulation":30,"captures":captures,"samples":samples,"scope":"Normal simulated engine inputs with all 22 actors and rule/physics/tactics active; only initial fixture transforms and spectator cameras added."},"\t"))
	print("POSE_DIAGNOSTIC samples=",samples.size()," captures=",captures)
	game.queue_free()
	game = null
	for _i in 4: await process_frame
	quit()
