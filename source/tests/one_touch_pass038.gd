extends "res://tests/integration_checks.gd"
## Publisher-only: two bounded real Q input checks. Do not launch concurrently.
var pass_events: Array[Dictionary] = []
var receive_events: Array[Dictionary] = []
func setup_incoming(gap: float, speed: float) -> void:
	release_inputs()
	game.ball.clear_control()
	game.ball.set_held(false)
	game.player.position = Vector3(0,.002,4)
	game.player.velocity = Vector3.ZERO
	game.player.reset_view(0)
	game.player.action_cooldown = 0
	game.player.stop_requested = 0
	game.player.foot.cancel("one_touch_fixture")
	game.ball.position = game.player.position+Vector3.FORWARD*gap
	game.ball.position.y = game.ball.radius+.0005
	game.ball.previous_position = game.ball.position
	game.ball.velocity = Vector3.BACK*speed
	game.ball.spin_rads = Vector3.UP.cross(game.ball.velocity)/game.ball.radius
	game.ball.pickup_block = 0
	game.ball.touch_timer = 0
	for a in game.agents:
		a.active = false
		a.position = Vector3(-9 if a.team==0 else 9,.002,-10+a.jersey*.3)
		a.velocity = Vector3.ZERO
		a.target = a.position
		a.pending_kick.clear()
		a.foot.cancel("one_touch_fixture")
	game.sync_input_context()
func run() -> void:
	DirAccess.make_dir_recursive_absolute(evidence)
	AudioServer.set_bus_mute(0,true)
	game = load("res://scenes/training_3v3.tscn").instantiate()
	game.test_mode = true
	game.ai_enabled = false
	root.add_child(game)
	await ticks(6)
	for a in game.players: a.refresh_pose(1.0/120.0)
	game.hud.menu.get_node("StartMatch").pressed.emit()
	await ticks(8)
	game.contact_hub.contact_resolved.connect(func(event: Dictionary):
		if event.get("actor")==game.player and event.get("success",false):
			if event.get("action","")=="PASS": pass_events.append(event.duplicate())
			if event.get("action","")=="RECEIVE": receive_events.append(event.duplicate())
	)
	setup_incoming(1.35,3.0)
	key(KEY_Q,true)
	await ticks(2)
	key(KEY_Q,false)
	await ticks(1)
	check("Q release before contact reserves one free-ball pass",game.ball.carrier==null and game.player.foot.has_receive_pass() and pass_events.is_empty())
	await ticks(75)
	check("first actual shoe action is exactly one PASS, not RECEIVE then PASS",pass_events.size()==1 and receive_events.is_empty(),{"passes":pass_events,"receives":receive_events,"result":game.player.foot.last_result,"failure":game.player.foot.contact_failure})
	setup_incoming(1.35,3.0)
	pass_events.clear()
	receive_events.clear()
	# Use the published optional validity field only to make expiry deterministic;
	# Q input and ordinary physics still run unchanged. No timer/ball writes afterward.
	var expiry_filter: Callable = func(intent: Dictionary):
		if intent.get("phase","")=="commit" and String(intent.get("action","")).begins_with("pass_"):
			for pending in game.input_bridge.pending_intents:
				if pending.get("gesture_id")==intent.get("gesture_id") and pending.get("phase","")=="commit": pending["one_touch_valid_seconds"] = .05
	game.input_bridge.adapter.intent_emitted.connect(expiry_filter)
	key(KEY_Q,true)
	await ticks(2)
	key(KEY_Q,false)
	await ticks(1)
	game.input_bridge.adapter.intent_emitted.disconnect(expiry_filter)
	check("second Q accepts a bounded early reservation",bool(game.player.foot.buffer.get("one_touch_pass",false)))
	await ticks(90)
	check("expired reservation never produces a delayed PASS",pass_events.is_empty() and not game.player.foot.has_receive_pass(),{"passes":pass_events,"ordinary_receives":receive_events,"result":game.player.foot.last_result})
	var passed := checks.all(func(row):return row.passed)
	var report:String=evidence.path_join("one_touch_pass038.json")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):report=arg.trim_prefix("--output=")
	FileAccess.open(report,FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"checks":checks,"scope":"Publisher-only short synthetic Q input through live bridge, actual boot/World; declared initial fixtures; expiry uses optional per-intent 50ms validity. No native visuals/performance claim."},"\t"))
	game.pause_match()
	game.shutdown_audio()
	game.queue_free()
	game = null
	for i in 4: await process_frame
	quit(0 if passed else 1)
