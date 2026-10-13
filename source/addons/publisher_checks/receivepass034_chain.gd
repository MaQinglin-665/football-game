extends "res://addons/publisher_checks/role_test_base.gd"
var pass_events:Array=[]
var receiver_events:Array=[]
var receiver:Node3D
func _ready()->void:
	if not "--receivepass034-check" in OS.get_cmdline_user_args():
		queue_free();return
	game=get_parent();game.test_mode=true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="):evidence=arg.trim_prefix("--evidence=")
	call_deferred("run")
func run()->void:
	DirAccess.make_dir_recursive_absolute(evidence)
	game.ai_enabled=false
	game.contact_hub.contact_resolved.connect(func(e:Dictionary):
		if e.get("actor")==game.player and e.get("action")=="PASS" and e.get("success",false):pass_events.append({"sequence":e.get("action_sequence",-1),"point":e.get("point",Vector3.ZERO),"intent":game.ball.last_kick_intent.duplicate(true)})
		if is_instance_valid(receiver) and e.get("actor")==receiver and e.get("action")=="RECEIVE" and e.get("success",false):receiver_events.append({"sequence":e.get("action_sequence",-1),"point":e.get("point",Vector3.ZERO),"after":e.get("after_velocity",Vector3.ZERO)})
	)
	await ticks(6)
	game.hud.menu.get_node("StartMatch").pressed.emit()
	check("sender actual initial RECEIVE",await receive())
	for i in 80:
		if game.player.foot.idle():break
		await ticks(1)
	for i in game.agents.size():
		var a:Node3D=game.agents[i]
		a.position=Vector3(-10.0 if i%2 else 10.0,.002,-14.0+5.0*i);a.target=a.position;a.foot.cancel();a.active=false
		if receiver==null and a.team==game.player.team:receiver=a
	# One declared stationarystart fixture; existing motor/World owns all motion after Q.
	receiver.position=game.ball.position+Vector3(0,-game.ball.position.y+.002,-4.0)
	receiver.velocity=Vector3.ZERO;receiver.target=receiver.position
	receiver.facing=Vector3.BACK;receiver.body_facing=Vector3.BACK;receiver.face_target=Vector3.BACK
	receiver.tactical_pace=0.0;receiver.tactical_intent={"receive":true};receiver.active=true;receiver.refresh_pose(0.0)
	game.assist=true;game.sync_input_context()
	var before:Vector3=game.ball.velocity
	key(KEY_Q,true);await ticks(12)
	check("no pass impulse before Q release",pass_events.is_empty() and game.ball.velocity.distance_to(before)<.10)
	key(KEY_Q,false)
	var claimed_after:bool=false
	for i in 300:
		await ticks(1)
		if not pass_events.is_empty() and game.ball.carrier==receiver:claimed_after=true
	check("one actual Q PASS",pass_events.size()==1)
	check("real receiver shoe RECEIVE",not receiver_events.is_empty())
	check("ownership only after physical receiver touch",claimed_after and not receiver_events.is_empty())
	var sequences:Dictionary={};var duplicate:bool=false
	for e in receiver_events:
		if sequences.has(e.sequence):duplicate=true
		sequences[e.sequence]=true
	check("one RECEIVE per action",not duplicate)
	var passed:bool=checks.all(func(c):return c.passed)
	FileAccess.open(evidence.path_join("RECEIVEPASS034_CHAIN.json"),FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"checks":checks,"passes":pass_events,"receiver_contacts":receiver_events,"claimed_after_pass":claimed_after,"AI_decisions":false,"native":DisplayServer.get_name()!="headless","scope":"One declared4m stationary facingreceiver fixture, normal Q press/release and physicalWorld. No transform writes after Q. Existing receive intent explicitly supplied; not natural AI successrate."},"\t"))
	print("RECEIVEPASS034_CHAIN ",passed)
	reparent(get_tree().root);game.shutdown_audio();game.queue_free()
	for i in 4:await process_frame
	quit(0 if passed else 1)
