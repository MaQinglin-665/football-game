extends SceneTree
const Current=preload("res://scripts/tactics/receive_motion.gd")
const Previous=preload("res://tests/receive_motion_reference.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var game=load("res://scenes/training_3v3.tscn").instantiate();root.add_child(game)
	var snapshot:Dictionary={"motor_profile":game.physics_profile,"movement_cfg":game.tuning,"capabilities":{"receive_speed":5.6,"brake_deceleration":game.physics_profile.brake_deceleration_mps2}}
	var maximum:=0.0
	var before_us:=0
	var after_us:=0
	seed(391008)
	for i in 80:
		var row:Dictionary={"position":Vector3(randf_range(-10,10),0,randf_range(-10,10)),"velocity":Vector3(randf_range(-6,6),0,randf_range(-6,6)),"facing":Vector3.FORWARD.rotated(Vector3.UP,randf_range(-PI,PI)),"stamina":[0.0,1.5,25.0,80.0][i%4],"sprint_locked":i%3==0,"foot_cap":[1.6,4.8,100.0][i%3]}
		var target:=Vector3(randf_range(-12,12),0,randf_range(-12,12));var horizon:float=randf_range(.1,3)
		var start:int=Time.get_ticks_usec();var a:Dictionary=Previous.predict(row,target,Vector3.FORWARD,horizon,snapshot);before_us+=Time.get_ticks_usec()-start
		start=Time.get_ticks_usec();var b:Dictionary=Current.predict(row,target,Vector3.FORWARD,horizon,snapshot);after_us+=Time.get_ticks_usec()-start
		maximum=maxf(maximum,(a.position as Vector3).distance_to(b.position));maximum=maxf(maximum,(a.velocity as Vector3).distance_to(b.velocity))
	var report:Dictionary={"cases":80,"max_position_velocity_difference":maximum,"passed":maximum<.0001,"reference_cpu_us":before_us,"candidate_cpu_us":after_us,"scope":"same motor forecast, varied directions/speeds/stamina/foot caps; CPU function timing only, not match FPS"}
	FileAccess.open("res://../verification/receive_budget_checks.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(report);game.quit_game()
