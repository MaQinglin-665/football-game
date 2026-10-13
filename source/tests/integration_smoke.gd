extends SceneTree
var game: Node
var frames := 0
var records: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("run")

func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func wait_ticks(count: int) -> void:
	for _i in count:
		await physics_frame
		frames += 1
		if frames%10==0:
			var actor: Node3D = game.player
			var foot: FootballFootAction = actor.foot
			records.append({"frame":frames,"state":game.services.rules.state_name(),"ball":game.ball.position,"velocity":game.ball.velocity,"player":actor.position,"foot_kind":foot.kind,"foot_phase":foot.phase,"hit":foot.hit,"actual_contact":foot.actual_contact,"foot_result":foot.last_result,"rule_violations":game.services.rules.restart_violations().size()})

func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../verification/"+label+".png"))

func run() -> void:
	game = load("res://scenes/match.tscn").instantiate()
	game.test_mode = true
	root.add_child(game)
	await wait_ticks(6)
	await capture("v5_menu")
	game.start_match(false)
	for _i in 1200:
		await wait_ticks(1)
		if game.services.can_take_restart(game.player.get_instance_id()): break
	await capture("v5_kickoff_ready")
	key(KEY_Q,true)
	await wait_ticks(60)
	await capture("v5_pass_charge")
	key(KEY_Q,false)
	await wait_ticks(45)
	await capture("v5_pass_contact")
	key(KEY_W,true)
	await wait_ticks(240)
	key(KEY_W,false)
	await wait_ticks(240)
	await capture("v5_first_play")
	var result := {"scope":"first integrated runtime smoke; not final QA","actors":game.players.size(),"native":DisplayServer.get_name()!="headless","stats":game.stats,"rules":game.services.rules.snapshot(),"records":records,"hub":game.contact_hub.export_records()}
	var file := FileAccess.open("res://../verification/integration_smoke_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	print("SMOKE_END actors=",game.players.size()," state=",game.services.rules.state_name()," stats=",game.stats)
	game.queue_free()
	await process_frame
	quit(0)
