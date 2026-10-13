extends "res://tests/integration_checks.gd"
var host_contacts: Array[Dictionary] = []
var case_id := "startup"
var first_real_contact: Dictionary = {}

func _initialize() -> void:
	AudioServer.set_bus_mute(0,true) # This test process only, no audible desktop output.
	super._initialize()

func fixture() -> void:
	super.fixture()
	game.player.set_semantic_movement(Vector3.ZERO,"run")

func on_contact(event: Dictionary) -> void:
	if event.actor!=game.player: return
	var event_id := "impact-foot:%d:%d" % [game.player.get_instance_id(),int(event.get("action_sequence",0))]
	var matches: Array = game.services.audio.recent_mix.filter(func(m): return m.get("event_id","")==event_id)
	if event.success and first_real_contact.is_empty(): first_real_contact = event.duplicate(true)
	host_contacts.append({"case":case_id,"frame":frames,"kind":event.kind,"action":event.action,"success":event.success,"action_sequence":event.get("action_sequence",0),"event_id":event_id,"audio_records":matches.duplicate(true),"impact_count":game.services.audio.impact_diagnostics.played})

func run() -> void:
	game = load("res://scenes/match.tscn").instantiate()
	game.test_mode = true
	root.add_child(game)
	check("impact addon installed in actual MatchServices",game.services.audio.get_script().resource_path=="res://addons/football_impact_audio_b/impact_audio.gd")
	check("local actor and original samples preserved",game.services.audio.local_actor_id==game.player.get_instance_id() and game.services.audio._streams.has("step_0") and game.services.audio._streams.has("whistle_ready"))
	check("19 impact wave resources present",game.services.audio.IMPACT_FILES.values().reduce(func(n,files): return n+files.size(),0)==19 and game.services.audio._streams.has("push_b_2") and game.services.audio._streams.has("turf_b_1"))
	game.contact_hub.contact_resolved.connect(on_contact)
	case_id = "kickoff"
	game.start_match(false)
	for i in 2400:
		await ticks(1)
		if game.is_restart_taker(game.player): break
	key(KEY_Q,true)
	await ticks(50)
	key(KEY_Q,false)
	await ticks(650)
	check("actual kickoff pass uses one pass sample",host_contacts.any(func(e): return e.case=="kickoff" and e.action=="PASS" and e.success and e.audio_records.size()==1 and e.audio_records[0].cue=="pass"))
	check("actual game is live after kickoff",game.phase==game.Phase.PLAY)
	case_id = "receive_and_control"
	var received := await receive()
	check("free ball received by actual shoe",received)
	check("actual RECEIVE gets one soft touch sample",host_contacts.any(func(e): return e.case=="receive_and_control" and e.action=="RECEIVE" and e.success and e.audio_records.size()==1 and e.audio_records[0].cue=="touch"))
	key(KEY_CTRL,true)
	key(KEY_W,true)
	await ticks(120)
	key(KEY_W,false)
	key(KEY_CTRL,false)
	check("actual close touches use control samples",host_contacts.any(func(e): return e.case=="receive_and_control" and e.action=="CLOSE" and e.success and e.audio_records.size()==1 and e.audio_records[0].cue=="dribble"))
	case_id = "pass"
	await receive()
	key(KEY_Q,true)
	await ticks(45)
	key(KEY_Q,false)
	await ticks(120)
	check("actual Q pass uses one dedicated pass sample",host_contacts.any(func(e): return e.case=="pass" and e.action=="PASS" and e.success and e.audio_records.size()==1 and str(e.audio_records[0].stream).begins_with("pass_b")))
	check("successful local foot touches sound once",host_contacts.filter(func(e): return e.success).all(func(e): return e.audio_records.size()==1))
	check("failed physical touches have no audio",host_contacts.filter(func(e): return not e.success).all(func(e): return e.audio_records.is_empty()))
	var played_before: int = game.services.audio.impact_diagnostics.played
	if not first_real_contact.is_empty(): game.services.audio.consume_resolved_contact(first_real_contact)
	check("duplicate of real contact adds no sound",not first_real_contact.is_empty() and game.services.audio.impact_diagnostics.played==played_before)
	check("all referenced audio samples load",game.services.audio.diagnostics.missing==0,game.services.audio.diagnostics)
	var passed: int = checks.filter(func(c): return c.passed).size()
	var result := {"version":"B v0.6.2 impact audio","passed":passed,"failed":checks.size()-passed,"checks":checks,"host_contacts":host_contacts,"audio_diagnostics":game.services.audio.impact_diagnostics.duplicate(),"recent_mix":game.services.audio.recent_mix.duplicate(true),"audio_driver":AudioServer.get_driver_name(),"master_muted":true,"graphics":DisplayServer.get_name(),"actors":game.players.size(),"scope":"Actual integrated game, real kickoff/receive/close/Q foot contacts and audio resource selection; WASAPI test process muted. Starting fixtures reset free-ball/player positions without fabricating ownership. Dedicated shot/push/post/turf mappings use provider's28-event checks, not real-game coverage here. No audible listening, rendered sync, performance or full-match QA."}
	FileAccess.open(evidence.path_join("impact_audio_host_check.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("IMPACT_HOST_CHECK ",passed,"/",checks.size()," driver=",AudioServer.get_driver_name())
	game.pause_match()
	game.shutdown_audio()
	game.queue_free()
	game = null
	first_real_contact.clear()
	for i in 4: await process_frame
	await create_timer(.15).timeout
	quit(0 if passed==checks.size() else 1)
