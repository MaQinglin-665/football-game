extends SceneTree
var game:Node
var output:=""
var evidence:=""
var tag:=""
var cleanup_only:=false
var match_msaa:=-1
var setup_start:int=0
var warm_start:int=0
var measure_start:int=0
var previous:int=0
var ending:=false
var rows:Array=[]
var contacts:Array=[]
var begin_positions:Array=[]
var prior_positions:Array=[]
var paths:Array=[]
var config:Dictionary={}
var physics_start:int=0
var world_start:int=0
var time_start:=0.0
func _initialize()->void:
	for a in OS.get_cmdline_user_args():
		if a=="--cleanup-only":cleanup_only=true
		if a.begins_with("--output="):output=a.trim_prefix("--output=")
		if a.begins_with("--evidence="):evidence=a.trim_prefix("--evidence=")
		if a.begins_with("--stage="):tag=a.trim_prefix("--stage=")
		if a.begins_with("--match-msaa="):match_msaa=int(a.trim_prefix("--match-msaa="))
	Engine.max_fps=120;Engine.time_scale=1.0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	seed(47011);setup_start=Time.get_ticks_usec();call_deferred("begin")
func begin()->void:
	game=load("res://scenes/match.tscn").instantiate();game.test_mode=true;root.add_child(game);current_scene=game
	for i in 8:await process_frame
	game.hud.menu.get_node("StartMatch").pressed.emit()
	for i in 8:await physics_frame
	# Same declared LIVE/free-ball fixture for both versions; normal22-player
	# motor, AI, planner, contact and World continue without subsequent writes.
	game.services.rules.restart.clear();game.services.rules._become_live();game.set_phase(game.Phase.PLAY)
	game.ball.set_held(false);game.ball.reset(Vector3(0,.111,0))
	game.player.position=Vector3(0,.002,3);game.player.velocity=Vector3.ZERO
	var production_msaa:int=root.msaa_3d
	if match_msaa>=0:root.msaa_3d=match_msaa
	var camera:=Camera3D.new();game.add_child(camera);camera.position=Vector3(0,9,18);camera.look_at(Vector3(0,0,0));camera.current=true
	game.contact_hub.contact_resolved.connect(func(e):contacts.append({"physics_frame":e.get("physics_frame",-1),"kind":e.get("kind",""),"action":e.get("action",""),"success":e.get("success",false),"actor_id":game.players.find(e.get("actor",null))}))
	config={"stage":tag,"quality":game.render_quality,"pid":OS.get_process_id(),"actors":game.players.size(),"agents":game.agents.size(),"AI_processing":game.agents.filter(func(a):return a.is_physics_processing()).size(),"planner_processing":game.tactics_bridge.is_physics_processing(),"physics_hz":Engine.physics_ticks_per_second,"time_scale":Engine.time_scale,"frame_cap":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode(),"window_size":str(root.size),"render_scale":root.scaling_3d_scale,"msaa3d":root.msaa_3d,"production_msaa3d":production_msaa,"max_physics_steps_per_frame":Engine.max_physics_steps_per_frame,"camera_transform":str(camera.global_transform),"gpu":RenderingServer.get_video_adapter_name(),"renderer":ProjectSettings.get_setting("rendering/renderer/rendering_method")}
	warm_start=Time.get_ticks_usec()
func _process(_dt:float)->bool:
	if ending:return false
	var now:int=Time.get_ticks_usec()
	if warm_start==0:
		if now-setup_start>8000000:quit(2)
		return false
	if measure_start==0:
		if now-warm_start<(250000 if cleanup_only else 1500000):return false
		measure_start=now;previous=now;physics_start=Engine.get_physics_frames();world_start=game.physics_world.step_serial;time_start=game.time_left
		for p in game.players:
			p.avatar.reset_pose_refresh_counters()
			begin_positions.append(p.position);prior_positions.append(p.position);paths.append(0.0)
		return false
	var ms:float=float(now-previous)/1000.0;previous=now
	var moving:int=0
	for id in game.players.size():
		var p=game.players[id]
		paths[id]+=p.position.distance_to(prior_positions[id]);prior_positions[id]=p.position
		if not p.is_human and Vector2(p.velocity.x,p.velocity.z).length()>.10:moving+=1
	rows.append({"frame":Engine.get_process_frames(),"physics_frame":Engine.get_physics_frames(),"wall_seconds":float(now-measure_start)/1000000.0,"frame_ms":ms,"physics_cpu_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0,"process_cpu_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,"time_left":game.time_left,"world_step":game.physics_world.step_serial,"phase":game.phase,"rules_state":game.services.rules.state,"moving_ai":moving,"ball_position":str(game.ball.position),"ball_velocity":str(game.ball.velocity),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"ram_static":Performance.get_monitor(Performance.MEMORY_STATIC)})
	if now-measure_start>=(250000 if cleanup_only else 5000000):finish(now)
	return false
func finish(now:int)->void:
	ending=true
	var activity:Array=[]
	for id in game.players.size():
		var p=game.players[id]
		activity.append({"id":id,"team":p.team,"human":p.is_human,"keeper":p.is_goalkeeper,"physics_processing":p.is_physics_processing(),"begin":str(begin_positions[id]),"end":str(p.position),"net_displacement_m":p.position.distance_to(begin_positions[id]),"render_sampled_path_m":paths[id],"pose":p.avatar.get_pose_refresh_debug(),"visual_far":p._visual_far39 if not p.is_human else false})
	var wall:float=float(now-measure_start)/1000000.0
	var report={"status":"completed","config":config,"rows":rows,"activity":activity,"contacts":contacts,"wall_measurement_seconds":wall,"physics_frames_advanced":Engine.get_physics_frames()-physics_start,"physics_game_seconds":float(Engine.get_physics_frames()-physics_start)/float(Engine.physics_ticks_per_second),"world_steps_advanced":game.physics_world.step_serial-world_start,"rules_game_seconds":time_start-game.time_left,"scope":"Native actual22actors+21AI/planner/World. One matched fixed elevated camera, free-ball LIVE initial fixture only; no human input, ownership injection, AI freezes, quality changes or slow motion. 1.5wall warmup+5wall measurement. All activity and rules/physics time recorded. Not fullmatch, subjective feel or export acceptance."}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(evidence.path_join(tag+"_activity22.png"))
	game.pause_match();game.shutdown_audio();game.queue_free();game=null
	for i in 6:await process_frame
	quit(0)
