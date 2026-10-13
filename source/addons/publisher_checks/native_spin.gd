extends "res://addons/publisher_checks/native_night.gd"
## Actual match ball and mesh; external close camera only for the spin cases.
var follow_camera: Camera3D
var spin_rows: Array[Dictionary] = []
var spin_cases: Array[Dictionary] = []
var spin_film: Array[Dictionary] = []
var following := false

func _process(_delta: float) -> void:
	if following and is_instance_valid(game) and is_instance_valid(follow_camera):
		follow_camera.global_position=game.ball.global_position+Vector3(0,.75,1.50)
		follow_camera.look_at(game.ball.global_position,Vector3.UP)

func q(qv: Quaternion) -> Array: return [qv.x,qv.y,qv.z,qv.w]

func roll_case(tag: String, speed: float, cap: int, seconds: float, airborne: bool=false) -> void:
	stage=tag;Engine.max_fps=cap
	game.ball.clear_control();game.ball.set_held(false)
	game.ball.position=Vector3(0,1.20 if airborne else .111,25)
	game.ball.previous_position=game.ball.position
	game.ball.velocity=Vector3(2,5,-10) if airborne else Vector3(speed,0,0)
	game.ball.spin_rads=Vector3(100,200,-50) if airborne else Vector3.UP.cross(game.ball.velocity)/game.ball.radius
	game.ball.pickup_block=20
	# Only each explicitly labeled initial fixture resets visual orientation.
	game.ball.visual.quaternion=Quaternion.IDENTITY
	var initial:={"position":game.ball.position,"velocity":game.ball.velocity,"spin":game.ball.spin_rads,"q":q(game.ball.visual.quaternion)}
	var start_frame:=Engine.get_physics_frames();var start_wall:=Time.get_ticks_usec()
	var start_contact: int=game.ball.collision_count
	var start_rows:=spin_rows.size();var start_film:=spin_film.size()
	var last_capture:=-10000
	while Engine.get_physics_frames()-start_frame<roundi(seconds*120):
		await process_frame
		spin_rows.append({"stage":tag,"physics_frame":Engine.get_physics_frames(),"world_step":game.physics_world.step_serial,"wall_usec":Time.get_ticks_usec(),"position":game.ball.position,"velocity":game.ball.velocity,"spin":game.ball.spin_rads,"q":q(game.ball.visual.quaternion),"contacts":game.ball.collision_count,"held":game.ball.held})
		if Engine.get_physics_frames()-last_capture>=8:
			last_capture=Engine.get_physics_frames()
			await RenderingServer.frame_post_draw
			var name:="spin_"+str(spin_film.size()).pad_zeros(3)+"_"+tag+".jpg"
			var code:=root.get_texture().get_image().save_jpg(evidence.path_join(name),.90)
			spin_film.append({"file":name,"result":code,"stage":tag,"physics_frame":Engine.get_physics_frames(),"wall_usec":Time.get_ticks_usec(),"ball":game.ball.position,"q":q(game.ball.visual.quaternion)})
	var final:={"position":game.ball.position,"velocity":game.ball.velocity,"spin":game.ball.spin_rads,"q":q(game.ball.visual.quaternion)}
	spin_cases.append({"stage":tag,"cap_requested":cap,"initial":initial,"final":final,"physics_ticks":Engine.get_physics_frames()-start_frame,"wall_seconds":(Time.get_ticks_usec()-start_wall)/1000000.0,"render_samples":spin_rows.size()-start_rows,"film_samples":spin_film.size()-start_film,"contacts_added":game.ball.collision_count-start_contact})
	check(tag+" actual world moves mesh without render PIcap",game.ball.position.distance_to(initial.position)>.10 and game.ball.visual.quaternion.angle_to(Quaternion.IDENTITY)>.0001 and Engine.time_scale==1,spin_cases.back())
	if airborne:check("air-spin actual floor contact occurred",game.ball.collision_count>start_contact)
	await capture(tag+"_final")

func run() -> void:
	Engine.max_fps=60
	game=load("res://scenes/match.tscn").instantiate();game.test_mode=true;root.add_child(game)
	for _i in 3:await tick()
	game.ai_enabled=false;game.services.rules.state=game.Rules.State.LIVE;game.services.rules.restart.clear();game.set_phase(game.Phase.PLAY)
	game.services.configuration.half_seconds=600
	for agent in game.agents:agent.refresh_pose(0);agent.pose_updates_enabled=false
	game.contact_hub.contact_resolved.connect(func(e:Dictionary):
		if e.actor==game.player:touch_events.append({"stage":stage,"action":e.action,"success":e.success,"point":e.point}))
	fixture();stage="actual_receive"
	key(KEY_SPACE,true);await tick();key(KEY_SPACE,false)
	for _i in 45:await tick()
	check("current14 host acquires by actual RECEIVE",game.ball.carrier==game.player and touch_events.any(func(e):return e.action=="RECEIVE" and e.success))
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED);set_view(0,deg_to_rad(-60.0))
	var initial_q: Quaternion=game.ball.visual.quaternion
	var first_frame:=Engine.get_physics_frames()
	while Engine.get_physics_frames()-first_frame<270:
		var elapsed:=(Engine.get_physics_frames()-first_frame)/120.0
		stage="noShift" if elapsed<.75 else "holdShift" if elapsed<1.5 else "holdShift_cut"
		inputs([KEY_W] if elapsed<.75 else [KEY_W,KEY_SHIFT] if elapsed<1.5 else [KEY_W,KEY_D,KEY_SHIFT])
		await tick()
	inputs([]);await capture("actual_FP_dribble_spin")
	check("short real control contacts and visual rotation exercised",game.ball.carrier==game.player and game.ball.visual.quaternion.angle_to(initial_q)>.001 and touch_events.any(func(e):return e.action!="RECEIVE" and e.success))
	check("marker original position and visibility retained",is_equal_approx(game.ball.marker.global_position.y,.045) and game.ball.marker.visible)
	game.pause_match()
	game.ball.spin_rads=Vector3(200,300,-50) # Explicit pause probe, no World step.
	var paused:={"p":game.ball.position,"v":game.ball.velocity,"w":game.ball.spin_rads,"q":game.ball.visual.quaternion,"world_step":game.physics_world.step_serial}
	for _i in 12:await process_frame
	var after:={"p":game.ball.position,"v":game.ball.velocity,"w":game.ball.spin_rads,"q":game.ball.visual.quaternion,"world_step":game.physics_world.step_serial}
	check("actual PAUSED world and renderloop preserve mesh spin",paused==after)
	await capture("paused_ball_mesh_still")
	game.resume_match();game.set_process(false);game.set_physics_process(false)
	for actor in game.players:
		actor.set_physics_process(false);actor.velocity=Vector3.ZERO;actor.set_move_intent(Vector3.ZERO)
	game.hud.visible=false
	follow_camera=Camera3D.new();follow_camera.name="QAOnlySpinCloseCamera";follow_camera.fov=60;follow_camera.near=.05;root.add_child(follow_camera);follow_camera.current=true;following=true
	await roll_case("rolling_2_8_cap60",2.8,60,1.2)
	await roll_case("rolling_17_cap30",17.0,30,1.2)
	await roll_case("air_spin_landing_cap60",0.0,60,3.0,true)
	following=false
	check("actualEXE22actors120hz inheritednight retained",game.players.size()==22 and Engine.physics_ticks_per_second==120 and night_state().mode=="night" and root.msaa_3d==0)
	check("spin demo images written",not spin_film.is_empty() and spin_film.all(func(f):return f.result==OK) and capture_records.all(func(c):return c.result==OK))
	var report:={"passed":checks.all(func(c):return c.passed),"checks":checks,"cases":spin_cases,"rows":spin_rows,"film":spin_film,"captures":capture_records,"contacts":touch_events,"control_path":path,"gpu":RenderingServer.get_video_adapter_name(),"ticket":ticket,"physics_hz":Engine.physics_ticks_per_second,"time_scale":Engine.time_scale,"scope":"Actual exportedEXE actual productionMatchFootball/World/mesh. One initial actual RECEIVE then2.25simsec real W/noShift/heldShift/cut with actualFP camera. Real pause, highspin assignment while World paused; then3 explicitly labeled independent ball initial fixtures, unchanged forces and real floor collision, external close camera follows for texture review.22physical actors retained,AI/distantpose off; functional requested caps30/60 and image reads are not fullmatchFPS or achieved-display-cadence proof. No new quality settings/body/input changes; high-speed texture sampling alias may remain. Native images require personal review; headless65 separate exact-state tests."}
	FileAccess.open(evidence.path_join("native_spin_015.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("NATIVE_SPIN_DONE valid=",report.passed," checks=",checks.size())
	release_inputs();game.pause_match();game.shutdown_audio();follow_camera.queue_free();game.queue_free();game=null
	for _i in 4:await process_frame
	quit(0 if report.passed else 1)
