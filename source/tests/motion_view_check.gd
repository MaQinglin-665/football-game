extends SceneTree
var game:Node
var output:String=""
var aa:int=1
var frames:Array=[]
var started:bool=false
class Observer extends Node:
	var probe
	func _process(delta:float)->void:probe.observe(delta)
func _initialize()->void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):output=a.trim_prefix("--out=")
		if a=="--aa4":aa=2
	call_deferred("run")
func key(code:int,pressed:bool)->void:
	var e:=InputEventKey.new();e.physical_keycode=code;e.keycode=code;e.pressed=pressed;Input.parse_input_event(e)
func run()->void:
	seed(391008)
	game=load("res://scenes/training_3v3.tscn").instantiate();root.add_child(game);current_scene=game;game.test_mode=true
	game.settings_menu.values.aa=aa;game.settings_menu.values.quality=1;game.settings_menu.values.lighting=0;game.settings_menu.values.volume=0;game.settings_menu.apply_values(false)
	root.mode=Window.MODE_WINDOWED;root.size=Vector2i(1280,720);Engine.max_fps=144
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	game.training_mode.defensive_opening=true;game.start_match(false)
	var observer:=Observer.new();observer.probe=self;observer.process_priority=9500;root.add_child(observer)
	for i in 240:await physics_frame
	game.player.head.rotation.x=deg_to_rad(-22)
	started=true;key(KEY_W,true)
	for i in 120:await physics_frame
	await capture("day")
	key(KEY_SHIFT,true)
	for i in 120:await physics_frame
	key(KEY_W,false);key(KEY_SHIFT,false);key(KEY_D,true)
	for i in 120:await physics_frame
	key(KEY_D,false)
	game.settings_menu.values.lighting=1;game.settings_menu.apply_values(false)
	for i in 60:await physics_frame
	await capture("night")
	# A real reset must not produce a rendered sweep across the pitch.
	game.ball.reset(Vector3(3,.11,3));game.player.position+=Vector3(2,0,0)
	for i in 4:await physics_frame
	game.settings_menu.open_menu();await capture("settings");game.settings_menu.close_menu()
	started=false
	FileAccess.open(output+".json",FileAccess.WRITE).store_string(JSON.stringify({"frames":frames,"aa":aa,"scope":"3v3 actual input path W/run/D; display sampling and day/night screenshots; capture timings excluded from performance conclusions; not human feel acceptance"}))
	game.quit_game()
func observe(dt:float)->void:
	if not started:return
	frames.append({"dt":dt,"tick":Engine.get_physics_frames(),"root":game.player.position,"eye":game.player.camera.global_position,"speed":game.player.velocity.length(),"camera_head_angle":game.player.camera.global_basis.get_rotation_quaternion().angle_to(game.player.head.global_basis.get_rotation_quaternion()),"ball":game.ball.position})
func capture(label:String)->void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output+"_"+label+".png")
