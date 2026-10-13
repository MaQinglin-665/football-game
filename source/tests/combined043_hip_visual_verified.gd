extends "res://tests/integration_checks.gd"
var rows:Array=[]
var stage:String=""
var started:int=0
var finished:bool=false
var observer:Camera3D
func _process(_dt:float)->bool:
	if started>0 and not finished and Time.get_ticks_msec()-started>14000:
		release_inputs();quit(2)
	return false
func observe(n:int)->void:
	for i in n:
		await physics_frame
		var p=game.player
		if is_instance_valid(observer):
			observer.global_position=p.position+Vector3(3,1.7,3)
			observer.look_at(p.position+Vector3.UP*.8)
		var sk:Skeleton3D=p.avatar.skeleton
		rows.append({"stage":stage,"physics_frame":Engine.get_physics_frames(),"process_frame":Engine.get_process_frames(),"actor":p.position,"velocity":p.velocity,"head_enabled":p.head.enabled,"mouse_mode":Input.get_mouse_mode(),"head_pitch":p.head.rot.x,"phase":game.phase,"camera_origin":p.camera.global_position,"camera_basis":p.camera.global_basis,"left_sole":p.avatar.get_foot_contact(-1,"SOLE").point,"right_sole":p.avatar.get_foot_contact(1,"SOLE").point,"hips":sk.global_transform*sk.get_bone_global_pose(sk.find_bone("hips")).origin,"motion":p.avatar.get_full_body_debug()})
func run()->void:
	started=Time.get_ticks_msec();Engine.max_fps=60;seed(4112)
	game=load("res://scenes/training_3v3.tscn").instantiate();game.test_mode=true;root.add_child(game);current_scene=game
	for i in 5:await process_frame
	game.hud.menu.get_node("StartMatch").pressed.emit();await ticks(10)
	# Only declared fixture setup. Every AI, planner and World stay active.
	release_inputs();game.player.position=Vector3(0,.002,4);game.player.velocity=Vector3.ZERO;game.player.reset_view(0);game.player.foot.cancel("fixture")
	game.ball.clear_control();game.ball.set_held(false);game.ball.reset(Vector3(-9,.12,-9))
	stage="run_firstperson";key(KEY_SHIFT,true);key(KEY_W,true);await observe(90)
	await capture("body043_hip_verified_firstperson_run")
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	var look:=InputEventMouseMotion.new()
	look.relative=Vector2(0,(game.player.head.rot.x+deg_to_rad(70.0))/game.player.head.mouse_sensitivity)
	Input.parse_input_event(look);Input.flush_buffered_events()
	stage="run_look_down70";await observe(20);await capture("body043_hip_verified_look_down70_a")
	await observe(20);await capture("body043_hip_verified_look_down70_b")
	release_inputs();key(KEY_CTRL,true);key(KEY_D,true)
	stage="strafe_firstperson";await observe(100);await capture("body043_hip_verified_strafe_firstperson")
	observer=Camera3D.new();game.add_child(observer);observer.current=true
	stage="strafe_body_observer";await observe(35);await capture("body043_hip_verified_strafe_body")
	release_inputs();stage="brake_body_observer";await observe(45);await capture("body043_hip_verified_brake_body")
	check("native production six actors and five AI enabled",native and game.players.size()==6 and game.agents.size()==5 and game.agents.all(func(a):return a.is_physics_processing()) and game.tactics_bridge.is_physics_processing())
	check("all real motor camera sole and hip samples finite",rows.all(func(r):return r.velocity.is_finite() and r.camera_origin.is_finite() and r.left_sole.is_finite() and r.right_sole.is_finite() and r.hips.is_finite()))
	check("normal motor really runs above2.1",rows.any(func(r):return r.stage=="run_firstperson" and r.velocity.length()>2.1))
	check("raw mouse input reaches70degree down view",absf(game.player.head.rot.x+deg_to_rad(70.0))<.01)
	check("actual sideways motor produces strafe gait",rows.any(func(r):return String(r.stage).begins_with("strafe_") and String(r.motion.directional_gait039.mode).begins_with("STRAFE")))
	var ok:bool=checks.all(func(c):return c.passed)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE).store_string(JSON.stringify({"passed":ok,"checks":checks,"rows":rows,"captures":captures,"scope":"Latest landing+dribble041+AI followup+broadphase. Native production3v3, all5AI/planner/World remain active. Initial free-ball/actor setup only; raw keys and mouse70deg, firstperson run/down/strafe plus extra following observer for mesh. Continuous camera/sole/hips evidence; still images cannot certify absence of jitter or sliding. No fullmatch/performance acceptance."},"\t"))
	finished=true;game.pause_match();game.shutdown_audio();game.queue_free();game=null
	for i in 4:await process_frame
	quit(0 if ok else 1)
