extends SceneTree
var game:Node
var out:String=""
var samples:Array=[]
var native:bool=false
var camera:Camera3D
func _initialize()->void:
	out=ProjectSettings.globalize_path("res://../verification/coordination")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):out=a.trim_prefix("--out=")
	native=DisplayServer.get_name()!="headless"
	call_deferred("run")
func run()->void:
	game=load("res://scenes/match.tscn").instantiate();root.add_child(game)
	await process_frame
	game.settings_menu.values.volume=0;game.settings_menu.values.lighting=0;game.settings_menu.apply_values(false)
	game.process_mode=Node.PROCESS_MODE_DISABLED
	for layer in game.find_children("*","CanvasLayer",true,false):layer.hide()
	for actor in game.players:actor.visible=false
	var near=game.agents[1];var far=game.agents[2]
	for actor in [near,far]:
		actor.visible=true;actor.foot.cancel();actor.avatar.clear_foot_action()
		actor.position=Vector3(0,.002,0)
	camera=Camera3D.new();root.add_child(camera);camera.current=true;camera.fov=52
	if native:root.mode=Window.MODE_WINDOWED;root.size=Vector2i(1280,720);Engine.max_fps=60
	var previous:=Vector3.ZERO
	var point:=Vector3(0,0,14)
	var last_rate:=0.0
	var largest_rate_jump:=0.0
	var finite:=true
	for frame in 600:
		var t:float=frame/60.0
		var speed:float=lerpf(0,5.6,clampf(t/3.0,0,1)) if t<3 else 5.6 if t<4 else lerpf(5.6,0,clampf((t-4)/.7,0,1)) if t<4.7 else 0.0 if t<5.5 else 2.4 if t<8 else maxf(0,2.4-(t-8)*5)
		var yaw:float=0.0 if t<5.5 else deg_to_rad(179) if t<6.2 else deg_to_rad(-179) if t<6.7 else deg_to_rad(30) if t<7.3 else deg_to_rad(-175)
		var direction:=Vector3.FORWARD.rotated(Vector3.UP,yaw)
		var velocity:Vector3=direction*speed
		var accel:Vector3=(velocity-previous)*60;previous=velocity
		point+=velocity/60.0
		var state:Dictionary={"velocity":velocity,"acceleration":accel,"forward":direction,"grounded":true,"ground_y":.002,"locomotion":"run" if speed>2 else "walk" if speed>.08 else "idle","control_tier":"FREE","ai_guard":t>=5.5 and t<8}
		near.position=point+Vector3(-1.4,.002,0);far.position=point+Vector3(1.4,.002,0)
		near.avatar.update_pose(1.0/60,state)
		far.avatar.update_display_gait(1.0/60,state)
		camera.position=point+Vector3(6,2.1,2.5);camera.look_at(point+Vector3(0,1,0))
		var rate:float=near.avatar._cadence
		if frame>5 and t<3:largest_rate_jump=maxf(largest_rate_jump,absf(rate-last_rate))
		last_rate=rate
		var feet:Array=[]
		var trunk_angles:Array=[]
		var pelvis:Array=[]
		for actor in [near,far]:
			var skeleton:Skeleton3D=actor.avatar.skeleton
			var hip:Vector3=skeleton.to_global(skeleton.get_bone_global_pose(actor.avatar.cached_bone_id("hips")).origin)
			var neck:Vector3=skeleton.to_global(skeleton.get_bone_global_pose(actor.avatar.cached_bone_id("neck")).origin)
			var trunk:Vector3=neck-hip
			pelvis.append({"position":skeleton.get_bone_pose_position(actor.avatar.cached_bone_id("hips")),"rest":skeleton.get_bone_rest(actor.avatar.cached_bone_id("hips")).origin,"pitch":rad_to_deg(skeleton.get_bone_pose_rotation(actor.avatar.cached_bone_id("hips")).get_euler().x),"world":hip})
			trunk_angles.append(rad_to_deg(atan2(trunk.dot(-actor.avatar.visual.global_basis.z),trunk.y)))
			for side in ["L","R"]:
				var sk:Skeleton3D=actor.avatar.skeleton
				var foot:Vector3=sk.to_global(sk.get_bone_global_pose(actor.avatar.cached_bone_id("foot."+side)).origin)
				finite=finite and foot.is_finite();feet.append(foot)
		samples.append({"t":t,"speed":speed,"cadence":rate,"phase":near.avatar._phase,"feet":feet,"trunk_forward_degrees":trunk_angles,"pelvis":pelvis,"debug":near.avatar.ai_run_ankles.debug_feet.duplicate(true)})
		if native:
			await process_frame
			if frame in [85,179,330,332,336,344,372,374,404,440,490,570]:
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(out+"_%03d.png"%frame)
	var result:Dictionary={"scope":"controlled visual fixture: acceleration, braking, stopping and turning; two AI poses, full and distant; not natural match evidence", "finite":finite,"max_ramp_cadence_jump":largest_rate_jump,"samples":samples}
	FileAccess.open(out+".json",FileAccess.WRITE).store_string(JSON.stringify(result))
	print("COORDINATION_CHECK finite=",finite," ramp cadence jump=",largest_rate_jump)
	game.shutdown_audio();quit(0 if finite and largest_rate_jump<.12 else 1)
