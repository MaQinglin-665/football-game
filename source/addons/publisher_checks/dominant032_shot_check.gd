extends "res://addons/publisher_checks/role_test_base.gd"
var shots:Array=[]
func _ready()->void:
	if not "--dominant032-shot-check" in OS.get_cmdline_user_args():
		queue_free();return
	game=get_parent();game.test_mode=true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="):evidence=arg.trim_prefix("--evidence=")
	call_deferred("run")
func run()->void:
	DirAccess.make_dir_recursive_absolute(evidence)
	game.ai_enabled=false
	game.contact_hub.contact_resolved.connect(func(e:Dictionary):
		if e.get("actor")==game.player and e.get("action")=="SHOT":shots.append({"success":e.get("success",false),"surface":e.get("surface",""),"impulse":e.get("impulse",Vector3.ZERO),"sequence":e.get("action_sequence",-1),"reason":e.get("failure_reason","")})
	)
	await ticks(6)
	game.hud.menu.get_node("StartMatch").pressed.emit()
	fixture()
	for i in game.agents.size():
		var a:Node3D=game.agents[i]
		a.position=Vector3(-10.0 if i%2 else 10.0,.002,-14.0+5.0*i);a.target=a.position;a.foot.cancel()
	game.sync_input_context()
	check("actual RECEIVE fixture",await receive())
	for i in 80:
		if game.player.foot.idle():break
		await ticks(1)
	check("standing shot permission",game.can_foot_action(game.player,"SHOT") and game.ball.carrier==game.player)
	var before:int=game.stats.shots
	mouse(MOUSE_BUTTON_LEFT,true);await ticks(18)
	mouse(MOUSE_BUTTON_LEFT,false);await ticks(120)
	check("real LMB actual SHOT contact",shots.any(func(e):return e.success))
	check("single shot statistic",game.stats.shots==before+1)
	var passed:bool=checks.all(func(c):return c.passed)
	FileAccess.open(evidence.path_join("DOMINANT032_SHOT.json"),FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"checks":checks,"events":shots,"AI_decisions":false,"native":DisplayServer.get_name()!="headless","scope":"One declared starting fixture then actual RECEIVE and LMB charge/release; no actor/ball writes after shot input."},"\t"))
	print("DOMINANT032_SHOT ",passed)
	reparent(get_tree().root);game.shutdown_audio();game.queue_free()
	for i in 4:await process_frame
	quit(0 if passed else 1)
