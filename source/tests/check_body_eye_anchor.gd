extends SceneTree
var checks: Array[Dictionary] = []

func _initialize() -> void: run.call_deferred()
func check(label: String, ok: bool, detail: Variant = null) -> void:
	checks.append({"check":label,"passed":ok,"detail":detail})
	print("PASS " if ok else "FAIL ",label)

func run() -> void:
	var game = load("res://scenes/match.tscn").instantiate()
	game.test_mode = true
	root.add_child(game)
	game.set_process(false); game.set_physics_process(false)
	game.physics_world.set_physics_process(false); game.ball.set_physics_process(false)
	for actor in game.players: actor.set_physics_process(false)
	var player = game.player
	var state := {"ball":game.ball.position,"velocity":game.ball.velocity,"spin":game.ball.spin_rads,"owner":game.ball.carrier,"sequence":player.foot.sequence,"phase":player.foot.phase}
	var eye_rows: Array = []
	var max_pitch_orbit := 0.0
	var max_body_anchor_error := 0.0
	for yaw in [0.0,PI/2.0,-PI/2.0,PI]:
		player.reset_view(yaw)
		# Deliberately give the visual a relative yaw: the eye must derive the
		# actual displayed body's frame, even when the host heading differs.
		for relative_yaw in [0.0,.35,-.35]:
			player.avatar.visual.rotation.y = relative_yaw
			player._refresh_view_anchor()
			var anchor: Vector3 = player.camera.global_position
			var expected: Vector3 = (player.avatar.skeleton.global_transform*player.avatar.skeleton.get_bone_global_pose(player.avatar.skeleton.find_bone("head"))).origin+player.avatar.visual.global_basis*Vector3(0,.06,-.20)
			max_body_anchor_error=maxf(max_body_anchor_error,anchor.distance_to(expected))
			for pitch in [-75.0,-60.0,-42.0,0.0,38.0]:
				player.head.rotation.x=deg_to_rad(pitch)
				max_pitch_orbit=maxf(max_pitch_orbit,player.camera.global_position.distance_to(anchor))
				eye_rows.append({"yaw":yaw,"relative_body_yaw":relative_yaw,"pitch":pitch,"camera":player.camera.global_position,"body":player.avatar.visual.global_transform})
	check("60 camera samples fixed through pitch in actual animated head frame",max_pitch_orbit<.000001 and max_body_anchor_error<.000001,{"samples":eye_rows.size(),"pitch_orbit_m":max_pitch_orbit,"body_anchor_error_m":max_body_anchor_error})
	check("camera has zero pitch-rotating local offset",player.camera.position==Vector3.ZERO)
	check("original lens and down/up limits retained",player.camera.fov==96 and is_equal_approx(player.camera.near,.05) and is_equal_approx(player.head.y_limit,deg_to_rad(75.0)),{"fov":player.camera.fov,"near":player.camera.near,"down_limit":player.head.y_limit,"upper_limit_deg":38})
	player.reset_view(0)
	check("original reset pitch42 retained",is_equal_approx(player.head.rot.x,deg_to_rad(-42.0)))
	var after := {"ball":game.ball.position,"velocity":game.ball.velocity,"spin":game.ball.spin_rads,"owner":game.ball.carrier,"sequence":player.foot.sequence,"phase":player.foot.phase}
	check("view-only changes preserve ball and foot action state",state==after)
	var body: MeshInstance3D
	for node in player.avatar.mesh_nodes:
		if String(node.name)=="BodyCore": body=node
	var mat: StandardMaterial3D=body.get_active_material(0)
	check("actual match firstperson body opaque672tri one surface",body.visible and body.mesh.get_surface_count()==1 and body.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size()/3==672 and mat.transparency==BaseMaterial3D.TRANSPARENCY_DISABLED and mat.albedo_color.a==1)
	var shadows: Array=game.find_children("*","Light3D",true,false)
	check("latest12 night farstands22actors120hz preserved",game.players.size()==22 and Engine.physics_ticks_per_second==120 and shadows.size()==1 and game.stadium.get_meta("far_clarity_enabled",false) and not game.stadium.has_meta("mid_clarity_state"),{"light_count":shadows.size(),"roster":game.players.size()})
	var report := {"passed":checks.all(func(c):return c.passed),"checks":checks,"GPU_used":false,"eye_rows":eye_rows,"scope":"Actual current match host, frozen simulation; geometric anchor/pitch/body-yaw invariance and unchanged ball/foot state. Native occlusion and mouse/live play remain separate."}
	FileAccess.open(ProjectSettings.globalize_path("res://../verification/BODY_EYE_ANCHOR_HEADLESS.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	game.shutdown_audio();game.free()
	print("BODY_EYE_ANCHOR_DONE valid=",report.passed)
	quit(0 if report.passed else 1)
