extends SceneTree
var game: Node3D
var checks: Array[Dictionary] = []
var failures: Array[String] = []
var report_root := ""

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks.append({"label":label,"passed":ok})
	if not ok:
		failures.append(label)
	print("PASS " if ok else "FAIL ",label)

func ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from,to,1)
	return game.get_world_3d().direct_space_state.intersect_ray(query)

func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(report_root.path_join(name+".png"))

func run() -> void:
	report_root = ProjectSettings.globalize_path("res://").path_join("../verification").simplify_path()
	game = load("res://scenes/match.tscn").instantiate()
	game.test_mode = true
	game.ai_enabled = false
	root.add_child(game)
	for frame in range(5):
		await physics_frame
	check(is_equal_approx(game.field_half_width,34) and is_equal_approx(game.field_half_length,52.5),"host dimensions come from 105x68 stadium")
	check(is_equal_approx(game.goal_width,7.32) and is_equal_approx(game.goal_height,2.44),"host scoring uses 7.32x2.44 clear opening")
	check(game.find_children("Stadium","Node3D",true,false).is_empty(),"old small arena is absent")
	check(game.stadium.build_details.seat_instances==52562,"delivered multimesh instance data reloads")
	var ground := ray(Vector3(10,3,20),Vector3(10,-1,20))
	check(not ground.is_empty() and absf(ground.position.y)<0.001,"integrated physical pitch has Y0 surface")
	check(not ray(Vector3(3.71,1,-50),Vector3(3.71,1,-55)).is_empty(),"new visible post has real static collision")
	check(not ray(Vector3(0,2.49,-50),Vector3(0,2.49,-55)).is_empty(),"new visible crossbar has real collision")
	check(ray(Vector3(3.45,0.3,-50),Vector3(3.45,0.3,-55)).is_empty(),"legal wide opening and visual net are unobstructed")
	game.start_match(true)
	game.begin_play()
	game.ball.detach()
	game.ball.set_physics_process(false)
	game.ball.previous_position = Vector3(3.45,0.3,-52.35)
	game.ball.position = Vector3(3.45,0.3,-52.70)
	game._check_boundaries()
	check(game.scores[0]==1,"shot through wider valid mouth counts beyond old six-metre goal")
	game.scores = [0,0]
	game.set_phase(game.Phase.PLAY)
	game.ball.set_physics_process(false)
	game.ball.previous_position = Vector3(0,0.3,-52.35)
	game.ball.position = Vector3(0,0.3,-52.60)
	game._check_boundaries()
	check(game.scores[0]==0,"partial crossing of new outer goal line is not goal")
	if DisplayServer.get_name() != "headless":
		game.show_menu()
		game.hud.root.hide()
		var overview := Camera3D.new()
		game.add_child(overview)
		overview.global_position = Vector3(86,80,98)
		overview.look_at(Vector3(0,1,0))
		overview.fov = 68
		overview.current = true
		for frame in range(12):
			await process_frame
		await capture("stadium_host_overview")
		overview.queue_free()
		game.player.camera.current = true
		game.hud.root.show()
		game.start_match(false)
		game.begin_play()
		game.player.head.rot.x = deg_to_rad(-10)
		game.player.head.rotation.x = game.player.head.rot.x
		for frame in range(18):
			await process_frame
		await capture("stadium_host_player_view")
	var report := {"checks":checks,"failures":failures,"layout":game.field_layout,"scope":"stadium + host goal geometry; final rules and 11v11 roster pending"}
	var output := FileAccess.open(report_root.path_join("stadium_integration_test_results.json"),FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"\t"))
	print("STADIUM_INTEGRATION_CHECKS ",checks.size()," FAILURES ",failures.size())
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
