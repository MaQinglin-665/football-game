extends "res://tests/eye045_visibility_native.gd"
func _process(_dt:float)->bool:
	if started>0 and not finished and Time.get_ticks_msec()-started>19000:
		release_inputs();quit(2)
	return false
func run()->void:
	started=Time.get_ticks_msec();Engine.max_fps=60;seed(4112)
	game=load("res://scenes/training_3v3.tscn").instantiate();game.test_mode=true;root.add_child(game);current_scene=game
	for i in 5:await process_frame
	game.hud.menu.get_node("StartMatch").pressed.emit();await ticks(10)
	release_inputs();game.player.position=Vector3(0,.002,4);game.player.velocity=Vector3.ZERO;game.player.reset_view(0);game.player.foot.cancel("fixture")
	game.ball.clear_control();game.ball.set_held(false);game.ball.reset(Vector3(-9,.12,-9))
	stage="initial_standing";await observe(120)
	var standing_eye:float=game.player.camera.global_position.y-game.player.position.y
	var sk:Skeleton3D=game.player.avatar.skeleton
	var hip_id:int=sk.find_bone("hips")
	var standing_hip:float=(sk.global_transform*sk.get_bone_global_pose(hip_id)).origin.y-game.player.position.y
	observer=Camera3D.new();game.add_child(observer);observer.current=true
	for cycle in 10:
		stage="cycle"+str(cycle+1)+"_forward";key(KEY_SHIFT,true);key(KEY_W,true);await observe(45)
		release_inputs();stage="cycle"+str(cycle+1)+"_side";key(KEY_CTRL,true);key(KEY_D,true);await observe(45)
		if cycle==0 or cycle==9:await capture("eye045_cycle"+str(cycle+1)+"_side")
		release_inputs();stage="cycle"+str(cycle+1)+"_stop";await observe(30)
	stage="final_standing";await observe(120);await capture("eye045_cycle10_final_standing")
	var final_eye:float=game.player.camera.global_position.y-game.player.position.y
	var final_hip:float=(sk.global_transform*sk.get_bone_global_pose(hip_id)).origin.y-game.player.position.y
	check("native all5AI and planner continue normally",native and game.agents.all(func(a):return a.is_physics_processing()) and game.tactics_bridge.is_physics_processing())
	check("ten input cycles recorded",rows.filter(func(r):return r.stage=="cycle10_stop").size()==30)
	check("actual finite body camera and sole samples",rows.all(func(r):return r.camera_origin.is_finite() and r.hips.is_finite() and r.left_sole.is_finite() and r.right_sole.is_finite()))
	check("no cumulative deep crouch during cycles",rows.all(func(r):return r.hips.y-r.actor.y>.65))
	check("standing eye returns within2cm of actual starting baseline",absf(final_eye-standing_eye)<.02)
	check("standing hip returns within2cm of actual starting baseline",absf(final_hip-standing_hip)<.02)
	check("final actual motor stops",Vector2(game.player.velocity.x,game.player.velocity.z).length()<.05)
	var ok:bool=checks.all(func(c):return c.passed)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE).store_string(JSON.stringify({"passed":ok,"checks":checks,"initial_eye_relative_y":standing_eye,"final_eye_relative_y":final_eye,"initial_hip_relative_y":standing_hip,"final_hip_relative_y":final_hip,"rows":rows,"captures":captures,"scope":"Native production3v3 all5AI+planner+World, ten real45tick ShiftW→45tick CtrlD→30tick stop cycles with120tick initial/final standing, raw input only after declared initial free-ball setup. Root-relative actual camera/hips/soles; actual model screenshots first/last cycle. Cumulative-height regression, not fullmatch,physics contact authorization or FPS acceptance."},"\t"))
	finished=true;game.pause_match();game.shutdown_audio();game.queue_free();game=null
	for i in 4:await process_frame
	quit(0 if ok else 1)
