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
		if "--cut-before" in OS.get_cmdline_user_args():
			actor.avatar.ai_run_ankles=load("res://tests/run_cut_before.gd").new()
			actor.avatar.ai_body_presentation=load("res://tests/run_cut_arm_before.gd").new()
		actor.position=Vector3(0,.002,0)
	camera=Camera3D.new();root.add_child(camera);camera.current=true;camera.fov=52
	if native:root.mode=Window.MODE_WINDOWED;root.size=Vector2i(1280,720);Engine.max_fps=60
	for bone_name in ["upper_arm.L","forearm.L","hand.L"]:
		var sk:Skeleton3D=near.avatar.skeleton
		print("ARM_REST ",bone_name," ",sk.get_bone_global_rest(sk.find_bone(bone_name)))
	var previous:=Vector3.ZERO
	var point:=Vector3(0,0,14)
	var last_rate:=0.0
	var largest_rate_jump:=0.0
	var finite:=true
	for frame in 480:
		var t:float=frame/60.0
		var speed:float=lerpf(0,4.5,clampf(t/2.0,0,1))
		var yaw:float=deg_to_rad(45)*smoothstep(3.2,3.65,t)-deg_to_rad(90)*smoothstep(6.2,6.65,t)
		var direction:=Vector3.FORWARD.rotated(Vector3.UP,yaw)
		var velocity:Vector3=direction*speed
		var accel:Vector3=(velocity-previous)*60;previous=velocity
		point+=velocity/60.0
		var state:Dictionary={"velocity":velocity,"acceleration":accel,"forward":direction,"grounded":true,"ground_y":.002,"locomotion":"run" if speed>2 else "walk" if speed>.08 else "idle","control_tier":"FREE","ai_guard":false}
		near.position=point+Vector3(-1.4,.002,0);far.position=point+Vector3(1.4,.002,0)
		near.avatar.update_pose(1.0/60,state)
		far.avatar.update_display_gait(1.0/60,state)
		camera.position=point+Vector3(5,1.7,-2);camera.look_at(point+Vector3(0,1,0))
		var rate:float=near.avatar._cadence
		if frame>5 and t<3:largest_rate_jump=maxf(largest_rate_jump,absf(rate-last_rate))
		last_rate=rate
		var feet:Array=[]
		var arms:Array=[]
		var trunk_angles:Array=[]
		var pelvis:Array=[]
		for actor in [near,far]:
			var skeleton:Skeleton3D=actor.avatar.skeleton
			var hip:Vector3=skeleton.to_global(skeleton.get_bone_global_pose(actor.avatar.cached_bone_id("hips")).origin)
			var neck:Vector3=skeleton.to_global(skeleton.get_bone_global_pose(actor.avatar.cached_bone_id("neck")).origin)
			var trunk:Vector3=neck-hip
			pelvis.append({"roll":rad_to_deg(skeleton.get_bone_pose_rotation(actor.avatar.cached_bone_id("hips")).get_euler().z),"position":skeleton.get_bone_pose_position(actor.avatar.cached_bone_id("hips")),"rest":skeleton.get_bone_rest(actor.avatar.cached_bone_id("hips")).origin,"pitch":rad_to_deg(skeleton.get_bone_pose_rotation(actor.avatar.cached_bone_id("hips")).get_euler().x),"world":hip})
			trunk_angles.append(rad_to_deg(atan2(trunk.dot(-actor.avatar.visual.global_basis.z),trunk.y)))
			for side in ["L","R"]:
				var elbow:Vector3=skeleton.get_bone_global_pose(actor.avatar.cached_bone_id("forearm."+side)).origin
				var shoulder:Vector3=skeleton.get_bone_global_pose(actor.avatar.cached_bone_id("upper_arm."+side)).origin
				var wrist:Vector3=skeleton.get_bone_global_pose(actor.avatar.cached_bone_id("hand."+side)).origin
				arms.append({"flex_deg":rad_to_deg((elbow-shoulder).angle_to(wrist-elbow)),"upper":elbow-shoulder,"lower":wrist-elbow})
				var sk:Skeleton3D=actor.avatar.skeleton
				var foot:Vector3=sk.to_global(sk.get_bone_global_pose(actor.avatar.cached_bone_id("foot."+side)).origin)
				finite=finite and foot.is_finite();feet.append(foot)
		samples.append({"t":t,"speed":speed,"cadence":rate,"phase":near.avatar._phase,"feet":feet,"arms":arms,"trunk_forward_degrees":trunk_angles,"pelvis":pelvis,"debug":near.avatar.ai_run_ankles.debug_feet.duplicate(true)})
		if native:
			await process_frame
			if frame in [120,126,132,138,144,150,186,192,198,204,210,216,222,228,366,372,378,384,390,396,402,408]:
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(out+"_%03d.png"%frame)
	var result:Dictionary={"scope":"controlled visual fixture: acceleration, braking, stopping and turning; two AI poses, full and distant; not natural match evidence", "finite":finite,"max_ramp_cadence_jump":largest_rate_jump,"samples":samples}
	FileAccess.open(out+".json",FileAccess.WRITE).store_string(JSON.stringify(result))
	print("COORDINATION_CHECK finite=",finite," ramp cadence jump=",largest_rate_jump)
	game.shutdown_audio();quit(0 if finite and largest_rate_jump<.12 else 1)
