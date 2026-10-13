extends "res://tests/integration_checks.gd"
## One short real019 3v3 activation check. No broad QA, render or FPS claim.
var pass_events: Array[Dictionary] = []

func fixture() -> void:
	super.fixture()
	# Keep the reused receive fixture's five agents within this smaller pitch.
	for i in game.agents.size():
		var actor: Node3D = game.agents[i]
		actor.position = Vector3(-10.0 if i%2 else 10.0,.002,-14.0+5.0*i)
		actor.target = actor.position
		actor.foot.cancel("role_batch03_fixture")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(evidence)
	AudioServer.set_bus_mute(0,true)
	game = load("res://scenes/training_3v3.tscn").instantiate()
	game.test_mode = true
	game.ai_enabled = false
	root.add_child(game)
	game.contact_hub.contact_resolved.connect(func(event: Dictionary):
		if event.get("actor") == game.player and event.get("action","") == "PASS" and event.get("success",false):
			pass_events.append({"sequence":event.get("action_sequence",-1),"point":event.point,"after_velocity":event.after_velocity})
	)
	await ticks(6)
	for actor in game.players: actor.refresh_pose(1.0/120.0) # Menu AI is disabled; exercise actual lazy pose binding.
	var bound: bool = game.players.all(func(actor):return bool(actor.avatar.role_batch_debug().rig_bind_ok))
	check("actual019 six actors/120Hz/shared rig/pass and stance adapters bind",game.players.size()==6 and Engine.physics_ticks_per_second==120 and bound and game.player.avatar.pass_bind_ok)
	game.hud.menu.get_node("StartMatch").pressed.emit()
	var received := await receive()
	await ticks(14)
	game.player.foot.cancel("role_batch03_ready")
	game.player.refresh_pose(0)
	check("live training possession acquired through actual RECEIVE",received and game.phase==game.Phase.PLAY and game.ball.carrier==game.player)
	var before: Vector3 = game.ball.velocity
	var request := {"action":"pass_ground","direction":Vector3.FORWARD,"power":.25,"elevation_deg":0.0,"spin":Vector3.ZERO}
	var accepted: bool = game.player.foot.request_semantic_kick(request)
	check("low-speed short pass accepted without an early ball impulse",accepted and game.ball.velocity==before)
	var style_seen := false
	for i in 56:
		await ticks(1)
		style_seen = style_seen or game.player.avatar.pass_pose.samples>0
	check("one actual PASS contact/released moving ball/authored body samples",style_seen and pass_events.size()==1 and game.ball.carrier!=game.player and game.ball.velocity.length()>.1,{"events":pass_events,"foot_result":game.player.foot.last_result,"pass_samples":game.player.avatar.pass_pose.samples})
	key(KEY_C,true)
	await ticks(24)
	var active_stance: Dictionary = game.player.avatar.role_batch_debug()
	check("off-ball C pressure applies modest defence stance",game.player.foot.idle() and float(active_stance.defence_weight)>.8 and bool(active_stance.pose_applied),active_stance)
	key(KEY_C,false)
	await ticks(25)
	var restored: Dictionary = game.player.avatar.role_batch_debug()
	check("pressure release restores base pose and leaves no role override",float(restored.defence_weight)==0.0 and not bool(restored.pose_applied),restored)
	var passed := checks.all(func(row):return row.passed)
	FileAccess.open(evidence.path_join("PASS_DEFENCE_MINIMAL_03.json"),FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"checks":checks,"scope":"Source-only short activation in frozen019-derived 3v3; synthetic input/one starting receive fixture; no native visual, EXE or performance validation","frames":frames},"\t")+"\n")
	print("PASS_DEFENCE_MINIMAL_03_DONE passed=",passed," checks=",checks.size())
	game.pause_match()
	game.shutdown_audio()
	game.queue_free()
	game = null
	for i in 4: await process_frame
	quit(0 if passed else 1)
