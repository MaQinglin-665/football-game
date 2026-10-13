class_name FBMatchImpactAudioB
extends "res://addons/football_match_services/audio/audio_director.gd"

const BASE_AUDIO = preload("res://addons/football_match_services/audio/audio_director.gd")
const BASE_ASSETS = "res://addons/football_match_services/audio/assets/"
const IMPACT_FILES = {
	"touch": ["touch_b_0", "touch_b_1", "touch_b_2"],
	"dribble": ["control_b_0", "control_b_1", "control_b_2"],
	"push": ["push_b_0", "push_b_1", "push_b_2"],
	"pass": ["pass_b_0", "pass_b_1", "pass_b_2"],
	"shot": ["shot_b_0", "shot_b_1", "shot_b_2"],
	"post": ["post_b_0", "post_b_1"], "turf": ["turf_b_0", "turf_b_1"] }
const REFERENCE_NS = {"touch": 3.0, "dribble": 1.3, "push": 2.4, "pass": 8.0, "shot": 12.0, "post": 8.0, "turf": 4.0}
const CUE_SCALE = {"touch": .75, "dribble": .84, "push": 1.0, "pass": 1.0, "shot": 1.02, "post": .74, "turf": .65}

@export var use_resolved_hub_contacts := true
@export var centre_local_ball := true
@export var impact_reference_scale := 1.0
@export var surface_burst_gap := .045
var impact_diagnostics := {"played": 0, "duplicates": 0, "failed_ignored": 0, "quiet_surface": 0, "surface_burst": 0, "unknown_surface": 0}
var _impact_seen: Dictionary = {}
var _impact_seen_order: Array[String] = []
var _surface_last: Dictionary = {}
var _impact_voices: Array[AudioStreamPlayer3D] = []
var _local_impacts: Array[AudioStreamPlayer] = []
var _impact_variants: Dictionary = {}
var _impact_bus := ""
var _match_ball: Node3D

func _ready() -> void:
	super._ready()
	_impact_bus = "FootballImpactB_%d" % get_instance_id()
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, _impact_bus)
	AudioServer.set_bus_send(index, "Master")
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = -4.0
	limiter.release = .045
	AudioServer.add_bus_effect(index, limiter)
	for i in range(4):
		var voice := AudioStreamPlayer3D.new()
		voice.bus = _impact_bus
		voice.unit_size = 3.0
		voice.max_distance = 38.0
		voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		voice.attenuation_filter_cutoff_hz = 7000.0
		voice.attenuation_filter_db = -12.0
		add_child(voice)
		_impact_voices.append(voice)
	for i in range(2):
		var voice := AudioStreamPlayer.new()
		voice.bus = _impact_bus
		add_child(voice)
		_local_impacts.append(voice)

func _load_streams() -> void:
	# The inherited loader uses get_script().resource_path. An additive subclass must
	# explicitly load the original library so whistles/steps/music keep their identity.
	for files in BASE_AUDIO.CUE_FILES.values():
		for file in files:
			_streams[file] = load(BASE_ASSETS.path_join(str(file) + ".wav"))
	for cue in ["touch", "dribble", "pass", "shot"]:
		for i in range(3):
			var file := "%s_soft_%d" % [cue, i]
			_streams[file] = load(BASE_ASSETS.path_join(file + ".wav"))
	for key in ["music_loop", "stadium_loop"]:
		var stream: AudioStreamWAV = load(BASE_ASSETS.path_join(key + ".wav"))
		if stream != null:
			stream = stream.duplicate()
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_begin = 0
			stream.loop_end = stream.data.size() / 2
		_streams[key] = stream
	var assets: String = get_script().resource_path.get_base_dir().path_join("assets")
	for files in IMPACT_FILES.values():
		for file in files:
			_streams[file] = load(assets.path_join(str(file) + ".wav"))

func bind_ball(ball: Node3D) -> void:
	_match_ball = ball
	if ball != null and ball.has_signal("physical_contact"):
		var callback := Callable(self, "_on_surface_contact")
		if not ball.is_connected("physical_contact", callback): ball.connect("physical_contact", callback)

func contact(event: Dictionary) -> bool:
	# MatchServices still updates rules through its existing adapter. Its accepted
	# canonical audio notification is silenced here because the raw resolved hub owns
	# the single sound, including a successful restart launching foot contact.
	if use_resolved_hub_contacts: return false
	return _consume_player_contact(event, false)

func consume_resolved_contact(event: Dictionary) -> bool:
	if not bool(event.get("success", false)):
		impact_diagnostics.failed_ignored += 1
		return false
	var kind := str(event.get("kind", "")).to_upper()
	if kind == "FOOT_TOUCH": return _consume_player_contact(event, true)
	if kind in ["BODY_CONTACT", "BALL_BODY_CONTACT"] and (bool(event.get("ball_contact", false)) or (is_instance_valid(_match_ball) and event.get("other") == _match_ball)):
		return _consume_player_contact(event, true, true)
	return false

func _consume_player_contact(event: Dictionary, raw: bool, body: bool = false) -> bool:
	var action := "body" if body else str(event.get("action", event.get("kind", "receive"))).to_lower()
	var cue := "touch"
	if action in ["pass", "shot"]: cue = action
	elif action in ["sprint", "push", "long_touch"]: cue = "push"
	elif action in ["carry", "close", "shield", "turn", "dribble"]: cue = "dribble"
	var actor_id := int(event.get("actor_id", -1))
	if actor_id < 0: return false
	var id := str(event.get("event_id", event.get("contact_id", "")))
	if raw and not body and int(event.get("action_sequence", event.get("sequence", 0))) > 0:
		id = "impact-foot:%d:%d" % [actor_id, int(event.get("action_sequence", event.get("sequence", 0)))]
	elif id.is_empty() and event.has("serial"): id = "impact-hub:%s" % str(event.serial)
	var j := _impulse_magnitude(event.get("impulse", 0.0))
	if not is_finite(j): return false
	if body and j < .08: return false
	var strength := impulse_strength(cue, j)
	var played := play_event(cue, id, event.get("point", event.get("position", Vector3.ZERO)), actor_id, strength)
	if played:
		recent_mix[-1]["action"] = action
		recent_mix[-1]["impulse_ns"] = j
	return played

func impulse_strength(cue: String, impulse_ns: float) -> float:
	var reference := maxf(.05, float(REFERENCE_NS.get(cue, 4.0)) * impact_reference_scale)
	return clampf(pow(maxf(0.0, impulse_ns) / reference, .65), .10, 1.0)

func rule_event(event: Dictionary) -> void:
	if str(event.get("type", "")) == "restart_taken":
		# Ground restarts are sounded only by the successful raw foot contact. A drop
		# makes no kick sound. A confirmed throw release may use a soft hand/ball cue.
		if str(event.get("restart", {}).get("kind", "")) == "throw_in":
			play_event("touch", str(event.get("event_id", "")), event.get("position", Vector3.ZERO), int(event.get("actor_id", -1)), .30)
		return
	super.rule_event(event)

func play_event(cue: String, event_id: String, at: Vector3 = Vector3.ZERO, actor_id: int = -1, strength: float = 1.0) -> bool:
	if not IMPACT_FILES.has(cue): return super.play_event(cue, event_id, at, actor_id, strength)
	if event_id.is_empty(): return false
	if _impact_seen.has(event_id):
		impact_diagnostics.duplicates += 1
		return false
	_impact_seen[event_id] = true
	_impact_seen_order.append(event_id)
	if _impact_seen_order.size() > 2048: _impact_seen.erase(_impact_seen_order.pop_front())
	var choices: Array = IMPACT_FILES[cue]
	var variation: int = int(_impact_variants.get(cue, 0)) % choices.size()
	_impact_variants[cue] = variation + 1
	var stream: AudioStream = _streams.get(choices[variation])
	if stream == null:
		diagnostics.missing += 1
		return false
	strength = clampf(strength, .10, 1.0)
	var gain := (.30 + .50 * sqrt(strength)) * float(CUE_SCALE[cue])
	var pitch := .98 + float(variation) * .02 + (strength - .5) * .035
	var local := centre_local_ball and actor_id >= 0 and actor_id == local_actor_id
	if local:
		var voice := _local_impact_voice()
		voice.stream = stream
		voice.set_meta("cue_gain", gain)
		voice.volume_db = _gain_db(master_volume * sfx_volume * gain)
		voice.pitch_scale = pitch
		voice.play()
	else:
		var voice := _remote_impact_voice()
		voice.global_position = at
		voice.stream = stream
		voice.set_meta("cue_gain", gain)
		voice.volume_db = _gain_db(master_volume * sfx_volume * gain)
		voice.pitch_scale = pitch
		voice.play()
	_duck_left = maxf(_duck_left, .24)
	diagnostics.played += 1
	impact_diagnostics.played += 1
	recent_mix.append({"cue": cue, "actor_id": actor_id, "bank": "physical", "strength": strength,
		"gain": gain, "pitch": pitch, "spatial": not local, "stream": choices[variation], "event_id": event_id,
		"max_distance": 38.0, "origin": "resolved_contact_b"})
	if recent_mix.size() > 64: recent_mix.pop_front()
	return true

func surface_impact(event: Dictionary) -> bool:
	if not bool(event.get("success", false)): return false
	var cue := str(event.get("surface", ""))
	if cue not in ["post", "turf"]: return false
	var j := _impulse_magnitude(event.get("impulse", 0.0))
	if not is_finite(j): return false
	if j < (.10 if cue == "turf" else .04):
		impact_diagnostics.quiet_surface += 1
		return false
	var source := "%s:%s" % [cue, event.get("collider_id", -1)]
	if _time - float(_surface_last.get(source, -100.0)) < surface_burst_gap:
		impact_diagnostics.surface_burst += 1
		return false
	var played := play_event(cue, str(event.get("event_id", "")), event.get("position", Vector3.ZERO), -1, impulse_strength(cue, j))
	if played: _surface_last[source] = _time
	return played

func _on_surface_contact(collider: Object, point: Vector3, impulse: Vector3) -> void:
	if not collider is Node3D or collider is CharacterBody3D: return
	var cue := str(collider.get_meta("football_audio_surface", ""))
	if cue.is_empty():
		if collider.name in ["LeftPostBody", "RightPostBody", "CrossbarBody"]: cue = "post"
		elif collider.name == "Ground" and collider.get_parent() != null and collider.get_parent().name == "Pitch": cue = "turf"
	if cue not in ["post", "turf"]:
		impact_diagnostics.unknown_surface += 1
		return
	var count := int(_match_ball.get("collision_count")) if is_instance_valid(_match_ball) else 0
	surface_impact({"success": true, "surface": cue, "impulse": impulse, "position": point,
		"collider_id": collider.get_instance_id(), "event_id": "impact-surface:%d:%d:%d" % [get_instance_id(), count, collider.get_instance_id()]})

func set_volumes(master: float, sfx: float, music: float) -> void:
	super.set_volumes(master, sfx, music)
	for voice in _impact_voices: voice.volume_db = _gain_db(master_volume * sfx_volume * float(voice.get_meta("cue_gain", 1.0)))
	for voice in _local_impacts: voice.volume_db = _gain_db(master_volume * sfx_volume * float(voice.get_meta("cue_gain", 1.0)))

func reset_events() -> void:
	super.reset_events()
	_impact_seen.clear()
	_impact_seen_order.clear()
	_impact_variants.clear()
	_surface_last.clear()

func _impulse_magnitude(value: Variant) -> float:
	return value.length() if value is Vector3 else absf(float(value))

func _local_impact_voice() -> AudioStreamPlayer:
	for voice in _local_impacts:
		if not voice.playing: return voice
	var voice := _local_impacts.pop_front()
	_local_impacts.append(voice)
	voice.stop()
	return voice

func _remote_impact_voice() -> AudioStreamPlayer3D:
	for voice in _impact_voices:
		if not voice.playing: return voice
	var voice := _impact_voices.pop_front()
	_impact_voices.append(voice)
	voice.stop()
	return voice

func _exit_tree() -> void:
	for voice in _impact_voices: voice.stop()
	for voice in _local_impacts: voice.stop()
	var index := AudioServer.get_bus_index(_impact_bus)
	if index > 0: AudioServer.remove_bus(index)
