extends SceneTree
var game:Node
var output:String=""
func _initialize()->void:call_deferred("run")
func run()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):output=arg.trim_prefix("--out=")
	game=load("res://scenes/match.tscn").instantiate();game.test_mode=true;root.add_child(game)
	game.ai_enabled=false
	for a in game.players:
		a.position=Vector3(25+a.team*3,.002,20+a.jersey);a.set_physics_process(false)
	var actor:Node3D=game.agents[2]
	actor.avatar.setup(actor.team,14,false)
	actor.position=Vector3(0,.002,0);actor.velocity=Vector3.ZERO
	actor.facing=Vector3.FORWARD;actor.body_facing=Vector3.FORWARD;actor.face_target=Vector3.FORWARD
	actor.refresh_pose(0);actor.avatar.visual.rotation=Vector3.ZERO
	var camera:=Camera3D.new();root.add_child(camera);camera.current=true;camera.fov=48
	for layer in game.find_children("*","CanvasLayer",true,false):layer.hide()
	for night in [0,1]:
		game.settings_menu.values.lighting=night;game.settings_menu.values.quality=2;game.settings_menu.values.effects=2;game.settings_menu.apply_values(false)
		for direction in [Vector3(0,1.35,-3.7),Vector3(3.7,1.35,0),Vector3(0,1.35,3.7)]:
			camera.position=actor.position+direction;camera.look_at(actor.position+Vector3(0,.90,0))
			for frame in 8:await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output+"_%d_%d.png"%[night,int(direction.z)])
		camera.position=Vector3(0,1.65,15);camera.look_at(Vector3(0,1,0))
		for frame in 8:await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output+"_%d_pitch.png"%night)
	game.shutdown_audio();game.queue_free();camera.queue_free();await process_frame
	quit()

