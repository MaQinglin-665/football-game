class_name FBMatchRecordedImpact
extends "res://addons/football_impact_audio_b/impact_audio.gd"
## Additive audio replacement. All admission/contact/surface/rule guards are inherited.
## No input, ball force, TouchPlan, skeleton, camera or physics ownership.
const Samples = preload("sample_bank.gd")
const LEGACY_IMPACT_ASSETS: String = "res://addons/football_impact_audio_b/assets/"

@export var recorded_impacts_enabled: bool = true
var recorded_diagnostics: Dictionary = {"played": 0, "silent_impulse": 0, "fallback": 0}
var _recorded_previous: Dictionary = {}

func surface_impact(event: Dictionary) -> bool:
	# Audio-only suppression of a ground solver burst, without foot/post throttling.
	var previous_gap: float = surface_burst_gap
	if recorded_impacts_enabled and str(event.get("surface", "")) == "turf":
		surface_burst_gap = maxf(previous_gap, .080)
	var accepted: bool = super.surface_impact(event)
	surface_burst_gap = previous_gap
	return accepted

func _load_streams() -> void:
	# A subclass has a different get_script().resource_path. Pin existing banks,
	# then locate this bank from its own resource, not a caller/test subclass.
	for choices in BASE_AUDIO.CUE_FILES.values():
		for file in choices:
			_streams[file] = load(BASE_ASSETS.path_join(str(file) + ".wav"))
	for cue in ["touch", "dribble", "pass", "shot"]:
		for i in range(3):
			var file: String = "%s_soft_%d" % [cue, i]
			_streams[file] = load(BASE_ASSETS.path_join(file + ".wav"))
	for key in ["music_loop", "stadium_loop"]:
		var stream: AudioStreamWAV = load(BASE_ASSETS.path_join(key + ".wav"))
		if stream != null:
			stream = stream.duplicate()
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_begin = 0
			stream.loop_end = stream.data.size() / 2
		_streams[key] = stream
	for choices in IMPACT_FILES.values():
		for file in choices:
			_streams[file] = load(LEGACY_IMPACT_ASSETS.path_join(str(file) + ".wav"))
	var own_assets: String = "res://addons/football_recorded_impact/assets"
	for choices in Samples.FILES.values():
		for file in choices:
			_streams[file] = load(own_assets.path_join(str(file) + ".wav"))

func impulse_strength(cue: String, impulse_ns: float) -> float:
	if not recorded_impacts_enabled or cue == "post": return super.impulse_strength(cue, impulse_ns)
	var reference: float = maxf(.05, float(REFERENCE_NS.get(cue, 4.0)) * impact_reference_scale)
	return clampf(pow(maxf(0.0, impulse_ns) / reference, .65), 0.0, 1.0)

func play_event(cue: String, event_id: String, at: Vector3 = Vector3.ZERO, actor_id: int = -1, strength: float = 1.0) -> bool:
	if not recorded_impacts_enabled or Samples.family(cue, strength).is_empty():
		return _legacy_play(cue, event_id, at, actor_id, strength)
	if event_id.is_empty() or not at.is_finite() or not is_finite(strength): return false
	if _impact_seen.has(event_id):
		impact_diagnostics.duplicates += 1
		return false
	strength = clampf(strength, 0.0, 1.0)
	if strength <= .025:
		_remember(event_id)
		recorded_diagnostics.silent_impulse += 1
		return false
	var family: String = Samples.family(cue, strength)
	var choices: Array = Samples.FILES[family]
	var actor_key: String = "%s:%d" % [family, actor_id]
	var variation: int = Samples.variant(event_id, int(_recorded_previous.get(actor_key, -1)), choices.size())
	var file: String = str(choices[variation])
	var stream: AudioStream = _streams.get(file)
	if stream == null:
		recorded_diagnostics.fallback += 1
		return _legacy_play(cue, event_id, at, actor_id, strength)
	_remember(event_id)
	_recorded_previous[actor_key] = variation
	var gain: float = Samples.gain(strength, float(CUE_SCALE[cue]))
	var local: bool = centre_local_ball and actor_id >= 0 and actor_id == local_actor_id
	_submit_recorded_voice(stream, at, local, gain)
	_duck_left = maxf(_duck_left, .24)
	diagnostics.played += 1
	impact_diagnostics.played += 1
	recorded_diagnostics.played += 1
	recent_mix.append({"cue": cue, "actor_id": actor_id, "bank": "recorded_" + family,
		"strength": strength, "gain": gain, "pitch": 1.0, "spatial": not local,
		"stream": file, "event_id": event_id, "max_distance": 38.0,
		"origin": "resolved_contact_recorded"})
	if recent_mix.size() > 64: recent_mix.pop_front()
	return true

func _remember(event_id: String) -> void:
	_impact_seen[event_id] = true
	_impact_seen_order.append(event_id)
	if _impact_seen_order.size() > 2048: _impact_seen.erase(_impact_seen_order.pop_front())

func _submit_recorded_voice(stream: AudioStream, at: Vector3, local: bool, gain: float) -> void:
	if local:
		var voice: AudioStreamPlayer = _local_impact_voice()
		voice.stream = stream
		voice.set_meta("cue_gain", gain)
		voice.volume_db = _gain_db(master_volume * sfx_volume * gain)
		voice.pitch_scale = 1.0
		voice.play()
	else:
		var voice: AudioStreamPlayer3D = _remote_impact_voice()
		voice.global_position = at
		voice.stream = stream
		voice.set_meta("cue_gain", gain)
		voice.volume_db = _gain_db(master_volume * sfx_volume * gain)
		voice.pitch_scale = 1.0
		voice.play()

func _legacy_play(cue: String, event_id: String, at: Vector3, actor_id: int, strength: float) -> bool:
	return super.play_event(cue, event_id, at, actor_id, strength)

func reset_events() -> void:
	super.reset_events()
	_recorded_previous.clear()
