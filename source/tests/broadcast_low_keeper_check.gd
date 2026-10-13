extends "res://tests/keeper_038_contact.gd"
var cases:Array=[]
var camera:Camera3D
func capture(label:String)->void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(evidence.path_join(label+".png"))
func low_stage(speed:float,backpass:bool=false)->void:
	stage(false,false,backpass)
	keeper.keeper_dive.cooldown=0.0
	game.ball.reset(keeper.position+Vector3(0,game.ball.radius+.012,-.42-speed*.42))
	game.ball.set_held(false)
	game.ball.apply_impulse_ns((Vector3(0,0,speed)-game.ball.velocity)*game.ball.mass_kg)
func run()->void:
	if evidence.is_empty():quit(2);return
	AudioServer.set_bus_mute(0,true)
	game=load("res://scenes/match.tscn").instantiate();game.test_mode=true;game.ai_enabled=false;root.add_child(game)
	await ticks(3);game.start_match(false)
	host=game.get_node("KeeperActions04")
	keeper=game.players.filter(func(a):return a.is_goalkeeper and a.team==0)[0]
	opponent=game.players.filter(func(a):return a.team!=keeper.team)[0]
	if DisplayServer.get_name()!="headless":
		camera=Camera3D.new();root.add_child(camera);camera.current=true;camera.fov=48
		camera.position=Vector3(3,1.3,40);camera.look_at(Vector3(0,.7,43.8))
		for layer in game.find_children("*","CanvasLayer",true,false):layer.hide()
	for speed in [3.0,10.0]:
		low_stage(speed)
		var trace:Array=[]
		for frame in 220:
			await physics_frame
			if camera!=null and frame==45:call_deferred("capture","keeper_low_"+str(speed))
			if frame%5==0:
				var state:Dictionary=host.states[keeper.get_instance_id()]
				trace.append({"frame":frame,"ball":game.ball.position,"velocity":game.ball.velocity,"phase":state.phase,"body":keeper.keeper_dive.phase,"pose":state.get("pose_debug",{}).duplicate(true),"floor":keeper.keeper_dive.body.last_floor,"correction":keeper.keeper_dive.body.floor_correction,"shoulder":keeper.avatar.skeleton.global_transform*keeper.avatar.skeleton.get_bone_global_pose(keeper.avatar.skeleton.find_bone("upper_arm.L")).origin,"visual":keeper.avatar.visual.global_position})
		check("central low prepare "+str(speed),host.records.any(func(e):return e.kind=="GK_PREPARE" and e.get("central_block",false)))
		check("real low hand contact "+str(speed),count_event("GK_HAND_CONTACT")==1)
		check("low speed catch / fast parry "+str(speed),count_event("GK_RETAIN_CONFIRMED")==1 if speed<6 else count_event("GK_PARRY_CONFIRMED")==1 and count_event("GK_RETAIN_CONFIRMED")==0)
		check("low action recovers "+str(speed),not keeper.keeper_dive.active())
		cases.append({"speed":speed,"events":host.records.duplicate(true),"trace":trace})
	low_stage(4.0)
	game.ball.position.x=-1.05
	await ticks(220)
	check("lateral ground ball reaches real glove",count_event("GK_HAND_CONTACT")==1)
	check("lateral ground action recovers",not keeper.keeper_dive.active() and keeper.down_state.state=="IDLE")
	cases.append({"speed":4.0,"offset":-1.05,"events":host.records.duplicate(true)})
	low_stage(5.0,true);await ticks(65)
	check("low backpass cannot use hands",count_event("GK_HAND_CONTACT")==0 and host.hand_owner==null)
	FileAccess.open(evidence.path_join("low_keeper.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"cases":cases},"  "))
	game.pause_match();game.shutdown_audio();game.queue_free();await process_frame
	quit(0 if checks.all(func(row):return row.passed) else 1)

