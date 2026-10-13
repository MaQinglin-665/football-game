extends "res://tests/integration_checks.gd"
var rows:Array=[]
var started:int=0
var finished:=false
func _process(_dt:float)->bool:
	if started>0 and not finished and Time.get_ticks_msec()-started>12000:
		release_inputs();quit(2)
	return false
func observe_native(n:int)->void:
	for i in n:
		await physics_frame
		rows.append({"frame":Engine.get_physics_frames(),"position":game.player.position,"velocity":game.player.velocity,"body":game.player.avatar.get_full_body_debug(),"view_basis":game.player.camera.global_basis})
func run()->void:
	started=Time.get_ticks_msec();Engine.max_fps=60;seed(3902)
	game=load("res://scenes/training_3v3.tscn").instantiate();game.test_mode=true;root.add_child(game);current_scene=game
	for i in 5:await process_frame
	game.hud.menu.get_node("StartMatch").pressed.emit()
	await ticks(10);game.tactics_bridge.set_physics_process(false)
	for a in game.agents:
		a.set_physics_process(false);a.foot.cancel("fixture");a.set_move_intent(Vector3.ZERO);a.velocity=Vector3.ZERO;a.position=Vector3(9+a.team,.002,10+a.jersey*.01)
	release_inputs();game.player.position=Vector3(0,.002,4);game.player.velocity=Vector3.ZERO;game.player.reset_view(0);game.player.foot.cancel("fixture")
	game.ball.clear_control();game.ball.set_held(false);game.ball.reset(Vector3(-9,.12,-9))
	key(KEY_W,true);key(KEY_SHIFT,true)
	await observe_native(90)
	await capture("motion039_verified_firstperson_run")
	# Inspect the production mesh without changing first-person camera or avatar.
	var camera:=Camera3D.new();game.add_child(camera);camera.global_position=game.player.position+Vector3(3,1.7,3)
	camera.look_at(game.player.position+Vector3.UP*.8);camera.current=true
	await observe_native(20);await capture("motion039_verified_body_run")
	release_inputs();await observe_native(70);await capture("motion039_verified_body_brake")
	check("native actual renderer and six production actors",native and game.players.size()==6)
	check("native real motor and body motion remain finite",rows.all(func(r):return (r.velocity as Vector3).is_finite()) and rows.any(func(r):return r.velocity.length()>2.1))
	var view_reference:Vector3=(rows[0].view_basis as Basis).z
	check("native view keeps its initial pitch during firstperson run",rows.slice(0,90).all(func(r):return (r.view_basis as Basis).z.dot(view_reference)>.999))
	var ok:bool=checks.all(func(c):return c.passed)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE).store_string(JSON.stringify({"passed":ok,"checks":checks,"rows":rows,"captures":captures,"scope":"Native Compatibility1280x720 fast60cap, isolated production3v3 free Shift run/brake screenshots. Extra camera is observation only; no native slide/fullmatch/stability acceptance."},"\t"))
	finished=true;game.pause_match();game.shutdown_audio();game.queue_free();game=null
	for i in 4:await process_frame
	quit(0 if ok else 1)
