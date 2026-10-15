extends "res://tests/three_turn043_contact_completion.gd"
var weight_rows:Array=[]
func ticks(n:int)->void:
	for i in n:
		await super.ticks(1)
		var a=game.player
		var info:Dictionary=a.avatar.get_control_support_snapshot().get("body_phase",{})
		weight_rows.append({"tick":case_tick,"stage":case_name,"info":info.duplicate(true),"camera_bob":a._eye_current.y-a._bob_baseline,"speed":a.velocity.length(),"owned":game.ball.carrier==a})
func start()->void:
	game=load("res://scenes/training_3v3.tscn").instantiate();game.test_mode=true;root.add_child(game);current_scene=game
	for i in 4:await process_frame
	await reset_case("start","B",Vector2(0,.28),true)
	game.player.position.x=0;game.ball.position.x=0
	game.player.avatar._plants.clear();game.player.avatar.invalidate_pose_snapshot()
	set_keys([KEY_W,KEY_SHIFT]);await ticks(150)
	case_name="turn";set_keys([KEY_A]);await ticks(120)
	case_name="settle";set_keys([]);await ticks(90)
	var applied:Array=weight_rows.filter(func(r):return r.info.get("running_transfer",false) and r.info.get("bone_writes",false))
	check("weight transfer changes real running pose",applied.size()>20)
	check("both final ankles preserved",applied.all(func(r):return float(r.info.get("preserved_ankle_error_m",1))<=.00001))
	check("pelvis shift stays within 4cm down and3.5cm sideways",applied.all(func(r):return absf(r.info.applied_offset_m.x)<=.03501 and r.info.applied_offset_m.y>=-.04001 and r.info.applied_offset_m.y<=.00001))
	check("eye bob remains at most1.5cm",weight_rows.all(func(r):return absf(r.camera_bob)<=.0151))
	check("start turn settle retains actual ball control",weight_rows.all(func(r):return r.owned))
	check("no ordinary double strike",unique_contacts())
	FileAccess.open(ProjectSettings.globalize_path("res://../verification/weight.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"rows":weight_rows,"contacts":contacts,"scope":"Isolated headless real pose/start/turn/settle. No visual acceptance."}))
	game.shutdown_audio();game.queue_free()
	for i in 4:await process_frame
	quit(0 if checks.all(func(c):return c.passed) else 1)
