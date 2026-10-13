extends "res://addons/publisher_checks/native_night.gd"
## Opt-in actual exported-executable body/eye review, normal startup untouched.
var body_views: Array[Dictionary] = []
var film: Array[Dictionary] = []
var body_mesh: MeshInstance3D

func body_view(tag: String, compare_hidden: bool = false) -> void:
	for _i in 6: await process_frame
	await capture(tag)
	var cam: Camera3D=game.player.camera
	var projected: Vector2=cam.unproject_position(game.ball.global_position)
	var expected: Vector3=(game.player.avatar.skeleton.global_transform*game.player.avatar.skeleton.get_bone_global_pose(game.player.avatar.skeleton.find_bone("head"))).origin+game.player.avatar.visual.global_basis*Vector3(0,.06,-.20)
	body_views.append({"tag":tag,"camera":cam.global_transform,"body":game.player.avatar.visual.global_transform,"body_visible":body_mesh.visible,"head_rotation":game.player.head.rotation,"ball":game.ball.position,"ball_screen":projected,"ball_in_view":not cam.is_position_behind(game.ball.position) and root.get_visible_rect().has_point(projected),"owned":game.ball.carrier==game.player,"anchor_error_m":cam.global_position.distance_to(expected),"time_scale":Engine.time_scale})
	if compare_hidden:
		# Same actual camera, same frozen ball. This pair makes torso occlusion
		# inspectable; hidden frame is explicitly diagnostic, never play mode.
		body_mesh.visible=false
		await capture(tag+"_body_hidden_diagnostic")
		body_mesh.visible=true

func live_film(tag: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var name:="live_"+str(film.size()).pad_zeros(3)+"_"+tag+".jpg"
	var code:=root.get_texture().get_image().save_jpg(evidence.path_join(name),.87)
	var cam: Camera3D=game.player.camera
	var screen: Vector2=cam.unproject_position(game.ball.global_position)
	film.append({"file":name,"result":code,"stage":tag,"wall_usec":Time.get_ticks_usec(),"physics_frame":Engine.get_physics_frames(),"camera":cam.global_transform,"body":game.player.avatar.visual.global_transform,"ball":game.ball.position,"speed":Vector2(game.player.velocity.x,game.player.velocity.z).length(),"owned":game.ball.carrier==game.player,"ball_in_view":not cam.is_position_behind(game.ball.position) and root.get_visible_rect().has_point(screen)})

func run() -> void:
	Engine.max_fps=60 # Imagery only; separate unchanged uncapped full-scene probe.
	game=load("res://scenes/match.tscn").instantiate()
	game.test_mode=true
	root.add_child(game)
	for _i in 3: await tick()
	game.ai_enabled=false
	game.services.rules.state=game.Rules.State.LIVE
	game.services.rules.restart.clear()
	game.set_phase(game.Phase.PLAY)
	game.services.configuration.half_seconds=600
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	for agent in game.agents:
		agent.refresh_pose(0);agent.pose_updates_enabled=false
	for node in game.player.avatar.mesh_nodes:
		if String(node.name)=="BodyCore":body_mesh=node
	game.contact_hub.contact_resolved.connect(func(e:Dictionary):
		if e.actor==game.player:touch_events.append({"stage":stage,"action":e.action,"success":e.success,"point":e.point,"sequence":e.get("action_sequence",-1)}))
	fixture()
	stage="initial_receive"
	key(KEY_SPACE,true);await tick();key(KEY_SPACE,false)
	for _i in 45: await tick()
	check("acquires through actual RECEIVE",game.ball.carrier==game.player and touch_events.any(func(e):return e.action=="RECEIVE" and e.success))
	check("production firstperson body visible opaque one surface",body_mesh.visible and body_mesh.mesh.get_surface_count()==1 and (body_mesh.get_active_material(0) as StandardMaterial3D).transparency==BaseMaterial3D.TRANSPARENCY_DISABLED)
	check("original22 roster120hz time1 lens unchanged",game.players.size()==22 and Engine.physics_ticks_per_second==120 and Engine.time_scale==1 and game.player.camera.fov==96 and is_equal_approx(game.player.camera.near,.05))
	game.set_process(false);game.set_physics_process(false)
	game.physics_world.set_physics_process(false);game.ball.set_physics_process(false)
	for actor in game.players:actor.set_physics_process(false)
	game.hud.visible=false
	var before := {"ball":game.ball.position,"velocity":game.ball.velocity,"carrier":game.ball.carrier,"sequence":game.player.foot.sequence}
	for view in [{"name":"default_down42","pitch":-42.0,"yaw":0.0,"pair":true},{"name":"working_down60","pitch":-60.0,"yaw":0.0,"pair":true},{"name":"hips_down75","pitch":-75.0,"yaw":0.0,"pair":true},{"name":"level","pitch":0.0,"yaw":0.0,"pair":false},{"name":"up38","pitch":38.0,"yaw":0.0,"pair":false},{"name":"turn_right90_down60","pitch":-60.0,"yaw":90.0,"pair":false},{"name":"turn_left90_down60","pitch":-60.0,"yaw":-90.0,"pair":false}]:
		stage=view.name
		set_view(deg_to_rad(view.yaw),deg_to_rad(view.pitch))
		await body_view(view.name,view.pair)
		if "--body-first-view" in OS.get_cmdline_user_args():break
	var after := {"ball":game.ball.position,"velocity":game.ball.velocity,"carrier":game.ball.carrier,"sequence":game.player.foot.sequence}
	check("all still views preserve ball contact state",before==after)
	check("actual displayed-body anchor stays fixed through look",body_views.all(func(v):return v.anchor_error_m<.00001),body_views.map(func(v):return v.anchor_error_m))
	if not "--body-first-view" in OS.get_cmdline_user_args():
		set_view(0,deg_to_rad(-60.0))
		toggle_f4();await body_view("day_working_down60")
		toggle_f4()
		check("F4 night fallback preserves body and existing low budget",night_state().mode=="night" and body_mesh.visible and night_state().all_lights==1)
		game.set_process(true);game.set_physics_process(true)
		game.physics_world.set_physics_process(true);game.ball.set_physics_process(true)
		for actor in game.players:actor.set_physics_process(true)
		var start_physics:=Engine.get_physics_frames()
		var start_wall:=Time.get_ticks_usec()
		var last_film:=-100000
		var previous_elapsed:=0.0
		while Engine.get_physics_frames()-start_physics<840:
			var elapsed:=(Engine.get_physics_frames()-start_physics)/120.0
			if elapsed<1.2:stage="noShift_walk";inputs([KEY_W])
			elif elapsed<2.4:stage="holdShift_run";inputs([KEY_W,KEY_SHIFT])
			elif elapsed<3.4:stage="holdShift_cut";inputs([KEY_W,KEY_D,KEY_SHIFT])
			elif elapsed<4.4:
				stage="mouse_right90";inputs([KEY_W,KEY_SHIFT])
				mouse_yaw(deg_to_rad(90.0)*maxf(0,elapsed-maxf(3.4,previous_elapsed)))
			elif elapsed<5.4:
				stage="mouse_return90";inputs([KEY_W,KEY_SHIFT])
				mouse_yaw(-deg_to_rad(90.0)*maxf(0,elapsed-maxf(4.4,previous_elapsed)))
			elif elapsed<6.3:stage="noShift_return";inputs([KEY_W])
			else:stage="stop";inputs([])
			previous_elapsed=elapsed
			await tick()
			if Engine.get_physics_frames()-last_film>=10:
				last_film=Engine.get_physics_frames();await live_film(stage)
		inputs([])
		check("original-speed live capture spans7simulationseconds",Engine.get_physics_frames()-start_physics>=840 and Engine.time_scale==1,{"physics_ticks":Engine.get_physics_frames()-start_physics,"wall_seconds":(Time.get_ticks_usec()-start_wall)/1000000.0,"film_frames":film.size()})
		check("live movement and retained skeletal contact code exercised",film.any(func(f):return f.speed>3) and touch_events.any(func(e):return e.success and e.action!="RECEIVE"),{"max_speed":film.map(func(f):return f.speed).max(),"successful_contacts":touch_events.filter(func(e):return e.success).size(),"ownership_fraction":float(film.filter(func(f):return f.owned).size())/maxi(1,film.size())})
		check("live film images written",not film.is_empty() and film.all(func(f):return f.result==OK))
	check("native body screenshots written",not capture_records.is_empty() and capture_records.all(func(c):return c.result==OK))
	var report:={"passed":checks.all(func(c):return c.passed),"checks":checks,"views":body_views,"captures":capture_records,"film":film,"contacts":touch_events,"live_rows":path,"focus_recoveries":focus_recoveries,"gpu":RenderingServer.get_video_adapter_name(),"ticket":ticket,"physics_hz":Engine.physics_ticks_per_second,"time_scale":Engine.time_scale,"first_view_only":"--body-first-view" in OS.get_cmdline_user_args(),"scope":"Actual exported EXE actual FP Camera and real injected MouseMotion/RECEIVE/noShift/heldShift/WD, plus F4. Only static view pairs freeze physics; diagnostic body-hidden frames labeled. Seven simulation seconds live at time1,22 physical bodies with AI decisions/distant poses off. No actor/ball resets after RECEIVE. Ball projection alone is not occlusion/comfort proof; personally inspect actual frames. Full head/body yaw redesign absent; current physical yaw behavior retained. Functional cap60 is not performance evidence."}
	FileAccess.open(evidence.path_join("native_body_eye_014.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("NATIVE_BODY_EYE_DONE valid=",report.passed," checks=",checks.size())
	release_inputs();game.pause_match();game.shutdown_audio();game.queue_free();game=null
	for _i in 4:await process_frame
	quit(0 if report.passed else 1)
