extends "res://tests/integration_checks.gd"
const Motion=preload("res://scripts/movement_inertia.gd")
var comparison:Array=[]
func run()->void:
	var profile=FootballPhysicsProfile.playable()
	for mode in [2,0,1]:
		profile.set_meta("movement_inertia",mode)
		for initial_speed in [1.7,5.0,7.0]:
			var v:Vector3=Vector3.FORWARD*initial_speed
			var distance:=0.0
			var seconds:=0.0
			while v.length()>.01 and seconds<3:
				v=Motion.step(v,Vector3.ZERO,profile,1,1.0/120)
				distance+=v.length()/120;seconds+=1.0/120
			var turn:Vector3=Vector3.FORWARD*initial_speed
			var reverse:Vector3=turn
			for i in 24:
				turn=Motion.step(turn,Vector3.RIGHT*initial_speed,profile,1,1.0/120)
				reverse=Motion.step(reverse,Vector3.BACK*initial_speed,profile,1,1.0/120)
			comparison.append({"mode":mode,"initial_speed":initial_speed,"stop_distance":distance,"stop_seconds":seconds,"turn_200ms":turn,"reverse_200ms":reverse})
			check("motor stop finite mode %s speed %s"%[mode,initial_speed],seconds<2 and v.length()<.02)
	profile.set_meta("movement_inertia",0)
	var first:=Motion.step(Vector3.FORWARD*7,Vector3.BACK*7,profile,1,1.0/120)
	check("reverse begins braking immediately, momentum not reversed",first.z> -7 and first.z< -6.8,first)
	game=load("res://scenes/training_3v3.tscn").instantiate();game.test_mode=true;root.add_child(game)
	game.settings_menu.values.volume=0
	for arg in OS.get_cmdline_user_args():
		if arg=="--medium":game.settings_menu.values.inertia=1
	game.settings_menu.apply_values(false)
	if native:root.mode=Window.MODE_WINDOWED;root.size=Vector2i(1280,720)
	game.training_mode.defensive_opening=true;game.start_match(false)
	await ticks(120)
	var p=game.player
	check("preset reaches human and AI motors",game.players.all(func(a):return int(a.profile.get_meta("movement_inertia",-1))==int(game.settings_menu.values.inertia)))
	# Isolate the motor commitment contract; this does not assert a successful tackle/contact.
	var saved_velocity:Vector3=p.velocity
	p.foot.cancel("motor commitment fixture")
	p.foot.kind="TACKLE";p.foot.phase=p.foot.Phase.PREPARE;p.foot.direction=Vector3.FORWARD
	p.velocity=Vector3.FORWARD*7;p.set_move_intent(Vector3.RIGHT,1)
	p.advance_motor(1.0/120)
	check("tackle motor brakes but does not home sideways",absf(p.velocity.x)<.001 and p.velocity.z> -7)
	p.foot.phase=p.foot.Phase.RECOVER;p.advance_motor(1.0/120)
	check("tackle recovery returns steering immediately",p.velocity.x>0)
	p.foot.cancel("fixture complete");p.velocity=saved_velocity;p.set_move_intent(Vector3.ZERO)
	key(KEY_W,true);key(KEY_SHIFT,true);await ticks(120)
	var before_v:Vector3=p.velocity
	var before_ball:Vector3=game.ball.position
	var before_body:Basis=p.avatar.visual.global_basis
	p.head.mouse_axis=Vector2(-PI/p.head.mouse_sensitivity,0);p.head.camera_rotation()
	check("mouse sweep does not move ball or flip velocity",p.velocity==before_v and game.ball.position==before_ball)
	check("mouse sweep preserves actual visual basis",p.avatar.visual.global_basis.is_equal_approx(before_body))
	await ticks(1)
	check("hips cannot instantly follow rear view",absf(angle_difference(p.hip_yaw,p.rotation.y))>2.0)
	await capture("rear_view")
	key(KEY_W,false);key(KEY_SHIFT,false);await ticks(120)
	check("body completes stationary turn without world direction lock",absf(angle_difference(p.hip_yaw,p.rotation.y))<.23,rad_to_deg(angle_difference(p.hip_yaw,p.rotation.y)))
	var turn_start:float=p.hip_yaw
	for i in 120:
		p.head.mouse_axis=Vector2(-TAU/120/p.head.mouse_sensitivity,0);p.head.camera_rotation()
		await ticks(2)
	check("stationary full circle has no world direction lock",absf(p.hip_yaw-turn_start)>5.7,rad_to_deg(p.hip_yaw-turn_start))
	p.foot.cancel("gesture fixture");p.call_age=2
	p.head.rot.x=deg_to_rad(-10);p.head.rotation.x=p.head.rot.x
	key(KEY_W,true);key(KEY_E,true);await ticks(1);key(KEY_E,false)
	await ticks(25)
	var age:float=p.call_age
	key(KEY_E,true);await ticks(1);key(KEY_E,false)
	check("repeat call does not restart arm clock",p.call_age>=age)
	check("call gesture runs while moving",p.call_weight>.5 and p.velocity.length()>.1,{"arm":p.call_weight,"speed":p.velocity.length()})
	await capture("call_first_person")
	var hand_id:int=p.avatar.skeleton.find_bone("hand.R")
	var hand:Vector3=p.avatar.skeleton.to_global(p.avatar.skeleton.get_bone_global_pose(hand_id).origin)
	var screen:Vector2=p.camera.unproject_position(hand)
	if native:check("raised hand in peripheral first-person view",not p.camera.is_position_behind(hand) and Rect2(Vector2.ZERO,Vector2(root.size)).has_point(screen),{"screen":screen,"hand":hand,"eye":p.camera.global_position})
	if native:
		p.avatar._visible_arms03.apply(p.avatar,false);p.avatar._visible_body01.apply(p.avatar,false)
		preload("res://scripts/broadcast_body.gd").apply(p.avatar,false)
		for mesh in p.avatar.mesh_nodes:mesh.visible=true
		var camera:=Camera3D.new();root.add_child(camera);camera.global_position=p.position+p.body_facing*3+Vector3(1,1.5,0);camera.look_at(p.position+Vector3(0,1,0));camera.current=true
		await capture("call_external");camera.queue_free();p.camera.current=true
	await ticks(150);key(KEY_W,false)
	check("call arm returns to rest",p.call_weight<.01)
	await ticks(50)
	game.settings_menu.open_menu();await capture("settings");game.settings_menu.close_menu()
	FileAccess.open(evidence.path_join("body_inertia_check.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"comparison":comparison,"scope":"deterministic motor comparison and actual 3v3 input path; no claim of match feel acceptance"}))
	var failed:=0
	for c in checks:
		if not c.passed:failed+=1
	print("BODY_INERTIA_DONE failures=",failed)
	game.quit_game()

