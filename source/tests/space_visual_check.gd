extends SceneTree
var output:String="res://../verification/"
func _initialize()->void:call_deferred("run")
func capture(name:String)->void:
	for i in 8:await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output+name+".png")
func run()->void:
	AudioServer.set_bus_mute(0,true)
	for small in [true,false]:
		var game:Node=load("res://scenes/training_3v3.tscn" if small else "res://scenes/match.tscn").instantiate();game.test_mode=true;root.add_child(game)
		await process_frame
		await capture("before3" if small else "before11")
		var picker:Control=game.hud.menu.get_node("FormationPicker")
		var slot:String="BACK" if small else "LW"
		var point:Vector2=picker.buttons[slot].get_global_rect().get_center()
		var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;root.push_input(motion,true)
		await process_frame
		for down in [true,false]:
			var event:=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;root.push_input(event,true)
			await process_frame
		if game.Selection.human_row(game).slot!=slot:
			print("CLICK_FAIL ",point," root ",root.get_visible_rect()," selected ",game.Selection.human_row(game).slot);quit(1);return
		print("PASS pointer selects ",slot)
		await capture("formation3" if small else "formation11")
		if not small:
			var camera:=Camera3D.new();root.add_child(camera);camera.current=true;camera.fov=65;camera.position=Vector3(0,1.65,15);camera.look_at(Vector3(0,1,0))
			for layer in game.find_children("*","CanvasLayer",true,false):layer.hide()
			for night in [0,1]:
				game.settings_menu.values.lighting=night;game.settings_menu.apply_values(false)
				await capture("pitch_day" if night==0 else "pitch_night")
			camera.queue_free()
		game.shutdown_audio();game.queue_free()
		for i in 4:await process_frame
	quit()

