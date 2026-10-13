extends SceneTree
## QUEUED, NOT RUN by the audio worker. Source routing/contracts only.
## No fixture claims recorded sound, real TouchPlan timing, import quality or FPS.
const Capture = preload("capture_only.gd")
const Hub = preload("res://scripts/integration_contact_hub.gd")
const Installer = preload("res://addons/football_recorded_impact/install.gd")
const Samples = preload("res://addons/football_recorded_impact/sample_bank.gd")
const ServicesStub = preload("services_stub.gd")
const BallStub = preload("ball_stub.gd")
var checks: Array[Dictionary] = []

func _init() -> void: call_deferred("_run")

func _check(label: String, passed: bool) -> void:
	checks.append({"label": label, "passed": passed})

func _foot(actor: Node3D, action: String, sequence: int, impulse: float, frame: int) -> Dictionary:
	return {"kind": "FOOT_TOUCH", "actor": actor, "action": action,
		"sequence": sequence, "action_sequence": sequence, "physics_frame": frame,
		"success": true, "point": Vector3(2, .15, -3), "normal": Vector3.UP,
		"before_velocity": Vector3.ZERO, "after_velocity": Vector3(impulse / .43, 0, 0),
		"impulse": Vector3(impulse, 0, 0)}

func _run() -> void:
	var audio = Capture.new()
	audio.prime()
	var actor := Node3D.new()
	var other_actor := Node3D.new()
	var hub = Hub.new()
	var ball = BallStub.new()
	audio.local_actor_id = actor.get_instance_id()
	audio.bind_ball(ball)
	hub.contact_resolved.connect(audio.consume_resolved_contact)
	hub.body_contact.connect(audio.consume_resolved_contact)

	var failed: Dictionary = _foot(actor, "pass", 1, 0, 1)
	failed["kind"] = "FOOT_ACTION_FAILED"
	failed["success"] = false
	_check("hub admits resolved failure record", hub.publish(failed))
	_check("failed action has no submitted voice", audio.submissions.is_empty())

	var touch: Dictionary = _foot(actor, "close", 2, .18, 2)
	_check("actual successful contact admitted", hub.publish(touch))
	_check("one success submits exactly one voice", audio.submissions.size() == 1)
	_check("local contact is centred tap with fixed pitch", bool(audio.submissions[0].local) and audio.recent_mix[-1].bank == "recorded_tap" and audio.recent_mix[-1].pitch == 1.0)
	_check("same-frame hub duplicate rejected", not hub.publish(touch))
	touch["physics_frame"] = 3
	_check("next-frame raw report may be admitted by hub", hub.publish(touch))
	_check("actor/action_sequence still sounds once across frames", audio.submissions.size() == 1)
	_check("canonical rules adapter contact is silent", not audio.contact({"kind": "dribble", "event_id": "canonical", "actor_id": actor.get_instance_id(), "impulse": .18}))
	_check("canonical notification creates no second voice", audio.submissions.size() == 1)

	_check("ground pass admitted", hub.publish(_foot(other_actor, "pass", 3, 3.0, 4)))
	_check("ground pass selects recorded pass at actual remote point", audio.recent_mix[-1].bank == "recorded_pass" and not bool(audio.submissions[-1].local) and audio.submissions[-1].position == Vector3(2, .15, -3))
	_check("heavy shot admitted", hub.publish(_foot(actor, "shot", 4, 12.0, 5)))
	_check("heavy shot selects shot family and louder gain", audio.recent_mix[-1].bank == "recorded_shot" and audio.submissions[-1].gain > audio.submissions[0].gain)
	var count: int = audio.submissions.size()
	_check("zero impulse can be logged", hub.publish(_foot(actor, "receive", 5, 0, 6)))
	_check("zero impulse adds no voice", audio.submissions.size() == count and audio.recorded_diagnostics.silent_impulse == 1)

	var shoulder := {"kind": "BODY_CONTACT", "actor": actor, "other": other_actor,
		"sequence": 7, "success": true, "physics_frame": 7,
		"point": Vector3.ZERO, "impulse": Vector3(3, 0, 0)}
	_check("shoulder contact accepted by hub", hub.publish(shoulder))
	_check("player/player contact adds no ball cue", audio.submissions.size() == count)
	shoulder["other"] = ball
	shoulder["sequence"] = 8
	shoulder["physics_frame"] = 8
	shoulder["ball_contact"] = true
	_check("qualified ball/body contact accepted", hub.publish(shoulder))
	_check("qualified ball/body contact adds one cue", audio.submissions.size() == count + 1)
	var invalid: Dictionary = _foot(actor, "shot", 9, 12, 9)
	invalid["point"] = Vector3(NAN, 0, 0)
	_check("non-finite contact rejected before sound", not hub.publish(invalid))
	_check("non-finite direct sound rejected", not audio.play_event("touch", "nan", Vector3.ZERO, 1, NAN))

	audio.clear_capture()
	audio._time = 1.0
	var landing := {"success": true, "surface": "turf", "impulse": Vector3(0, 2, 0),
		"position": Vector3(1, 0, 2), "collider_id": 7, "event_id": "turf-1"}
	_check("qualified landing submits one turf voice", audio.surface_impact(landing) and audio.recent_mix[-1].bank == "recorded_turf")
	audio._time = 1.05
	landing["event_id"] = "turf-2"
	_check("50ms repeated turf solver burst suppressed", not audio.surface_impact(landing) and audio.submissions.size() == 1)
	audio._time = 1.09
	landing["event_id"] = "turf-3"
	_check("later independent turf impact admitted", audio.surface_impact(landing) and audio.submissions.size() == 2)
	landing["impulse"] = Vector3(0, .09, 0)
	landing["event_id"] = "turf-small"
	audio._time = 1.3
	_check("resting turf impulse below inherited cutoff silent", not audio.surface_impact(landing))
	_check("base burst setting restored after turf call", is_equal_approx(audio.surface_burst_gap, .045))
	audio._surface_last["post:7"] = 2.0
	audio._time = 2.05
	var post := {"success": true, "surface": "post", "impulse": Vector3(0, 2, 0), "position": Vector3.ZERO, "collider_id": 7, "event_id": "post-1"}
	audio.surface_impact(post)
	_check("post retains 45ms gate and legacy bank", audio.legacy_calls.size() == 1 and audio.legacy_calls[-1].cue == "post")

	audio.clear_capture()
	for i in range(32): audio.play_event("dribble", "variation-%d" % i, Vector3.ZERO, 99, .4)
	var no_adjacent_repeat: bool = true
	for i in range(1, audio.recent_mix.size()):
		if audio.recent_mix[i].stream == audio.recent_mix[i-1].stream: no_adjacent_repeat = false
	_check("small take bank has no adjacent repeated sample", no_adjacent_repeat and audio.submissions.size() == 32)
	_check("monotone gain from weak to strong", Samples.gain(.1, 1.0) < Samples.gain(.4, 1.0) and Samples.gain(.4, 1.0) < Samples.gain(1.0, 1.0))
	_check("same action changes timbre with actual impulse", Samples.family("pass", .1) == "tap" and Samples.family("pass", .5) == "pass" and Samples.family("pass", 1.0) == "shot")
	_check("tiny actual impulse has no artificial strength floor", is_zero_approx(audio.impulse_strength("touch", 0.0)))
	audio.set_volumes(.31, .57, .11)
	_check("independent mix controls remain active", is_equal_approx(audio.master_volume, .31) and is_equal_approx(audio.sfx_volume, .57) and is_equal_approx(audio.music_volume, .11))
	_check("contact still requests short music duck", is_equal_approx(audio._duck_left, .24))

	audio.clear_capture()
	for file in Samples.FILES.tap: audio._streams.erase(file)
	_check("missing sample routes to old bank", not audio.play_event("touch", "missing", Vector3.ZERO, 1, .3) and audio.legacy_calls.size() == 1)
	_check("failed fallback does not consume actual event id", not audio._impact_seen.has("missing"))
	audio.prime()
	_check("same event may play once after sample becomes available", audio.play_event("touch", "missing", Vector3.ZERO, 1, .3))
	audio.recorded_impacts_enabled = false
	_check("runtime rollback restores original strength floor", is_equal_approx(audio.impulse_strength("touch", 0), .10))
	audio.play_event("shot", "rollback", Vector3.ZERO, 1, .8)
	_check("runtime rollback routes shot to old bank", audio.legacy_calls[-1].cue == "shot")
	audio._surface_last["turf:7"] = 3.0
	audio._time = 3.05
	landing["impulse"] = Vector3(0, 2, 0)
	landing["event_id"] = "rollback-turf"
	var legacy_before: int = audio.legacy_calls.size()
	audio.surface_impact(landing)
	_check("rollback turf restores original 45ms gate", audio.legacy_calls.size() == legacy_before + 1)
	audio.recorded_impacts_enabled = true

	audio.clear_capture()
	for i in range(2100): audio.play_event("touch", "bounded-%d" % i, Vector3.ZERO, 1, .4)
	_check("contact dedupe remains bounded to 2048", audio._impact_seen_order.size() == 2048 and audio._impact_seen.size() == 2048)
	_check("recent mix remains bounded to 64", audio.recent_mix.size() == 64)
	audio.reset_events()
	_check("new match clears old contact ids and variation history", audio._impact_seen.is_empty() and audio._recorded_previous.is_empty() and audio._surface_last.is_empty())

	# Off-tree installation checks subscriptions/config, never creating mixer voices.
	var services = ServicesStub.new()
	var previous = Capture.new()
	previous.name = "MatchAudio"
	previous.master_volume = .23
	previous.sfx_volume = .41
	previous.music_volume = .11
	previous.music_enabled = false
	previous.stadium_enabled = true
	previous.local_actor_id = 42
	previous.centre_local_ball = false
	previous.impact_reference_scale = 1.7
	previous.surface_burst_gap = .061
	previous._phase = "LIVE"
	services.audio = previous
	services.add_child(previous)
	var hot_hub = Hub.new()
	var hot_ball = BallStub.new()
	hot_hub.contact_resolved.connect(previous.consume_resolved_contact)
	hot_hub.body_contact.connect(previous.consume_resolved_contact)
	hot_ball.physical_contact.connect(previous._on_surface_contact)
	var installed: FBMatchAudioDirector = Installer.install(services, hot_hub, hot_ball)
	_check("installer replaces only audio reference", installed == services.audio and installed != previous)
	_check("previous raw owner disconnected immediately", not hot_hub.contact_resolved.is_connected(previous.consume_resolved_contact) and not hot_hub.body_contact.is_connected(previous.consume_resolved_contact))
	_check("one new contact owner connected", hot_hub.contact_resolved.get_connections().size() == 1 and hot_hub.body_contact.get_connections().size() == 1)
	_check("one new surface owner connected", hot_ball.physical_contact.get_connections().size() == 1)
	_check("installer preserves mix/local/phase settings", is_equal_approx(installed.master_volume, .23) and is_equal_approx(installed.sfx_volume, .41) and not installed.music_enabled and installed.local_actor_id == 42 and installed.get("_phase") == "LIVE")
	_check("installer preserves impact reference and custom base gate", is_equal_approx(float(installed.get("impact_reference_scale")), 1.7) and is_equal_approx(float(installed.get("surface_burst_gap")), .061))
	_check("second install is idempotent", Installer.install(services, hot_hub, hot_ball) == installed and hot_hub.contact_resolved.get_connections().size() == 1)
	services.free()
	hot_hub.free()
	hot_ball.free()
	hub.free()
	actor.free()
	other_actor.free()
	audio.free()
	ball.free()
	await process_frame
	var passed: int = 0
	for row in checks: passed += 1 if row.passed else 0
	print(JSON.stringify({"scope": "capture-only source routing contracts; no real audio/physics/FPS claim",
		"passed": passed, "total": checks.size(), "checks": checks}))
	quit(0 if passed == checks.size() else 1)
