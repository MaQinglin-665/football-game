class_name FBMatchAudioDirector
extends Node3D

const ASSET_ROOT := "assets/"
const CUE_FILES := {
	"touch": ["touch_0", "touch_1", "touch_2"], "dribble": ["dribble_0", "dribble_1", "dribble_2"],
	"pass": ["pass_0", "pass_1", "pass_2"], "shot": ["shot_0", "shot_1", "shot_2"],
	"step": ["step_0", "step_1", "step_2", "step_3"], "run": ["step_0", "step_1", "step_2", "step_3"],
	"whistle": ["whistle_short"], "ready": ["whistle_ready"], "period": ["whistle_period"], "goal": ["goal"] }
@export_range(0.0, 1.0) var master_volume: float = 0.85
@export_range(0.0, 1.0) var sfx_volume: float = 0.85
@export_range(0.0, 1.0) var music_volume: float = 0.22
@export var music_enabled: bool = true
@export var stadium_enabled: bool = false
@export var max_contact_voices: int = 10
@export var max_feedback_voices: int = 3
@export var local_actor_id: int = -1
var recent_mix: Array[Dictionary] = []
var diagnostics := {"played": 0, "duplicates": 0, "throttled": 0, "missing": 0}
var _streams: Dictionary = {}
var _contacts: Array[AudioStreamPlayer3D] = []
var _feedback: Array[AudioStreamPlayer] = []
var _local: Array[AudioStreamPlayer] = []
var _seen: Dictionary = {}
var _seen_order: Array[String] = []
var _last: Dictionary = {}
var _variants: Dictionary = {}
var _time: float = 0.0
var _duck_left: float = 0.0
var _duck: float = 1.0
var _phase: String = "IDLE"
var _music: AudioStreamPlayer
var _stadium: AudioStreamPlayer

func _ready() -> void:
	_load_streams()
	for i in range(max_contact_voices):
		var voice := AudioStreamPlayer3D.new()
		voice.bus = "Master"
		voice.unit_size = 7.5
		voice.max_distance = 45.0
		voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(voice)
		_contacts.append(voice)
	for i in range(max_feedback_voices):
		var voice := AudioStreamPlayer.new()
		voice.bus = "Master"
		add_child(voice)
		_feedback.append(voice)
	for i in range(2):
		var voice := AudioStreamPlayer.new()
		add_child(voice)
		_local.append(voice)
	_music = _loop_player("music_loop")
	_stadium = _loop_player("stadium_loop")
	_apply_mix()

func _process(delta: float) -> void:
	advance_mix(delta)

func advance_mix(delta: float) -> void:
	_time += delta
	_duck_left = maxf(0.0, _duck_left - delta)
	var target := 0.22 if _duck_left > 0.0 else 1.0
	_duck = move_toward(_duck, target, delta * (12.0 if target < _duck else 1.5))
	_apply_mix()

func set_volumes(master: float, sfx: float, music: float) -> void:
	master_volume = clampf(master, 0, 1)
	sfx_volume = clampf(sfx, 0, 1)
	music_volume = clampf(music, 0, 1)
	_apply_mix()
	# Adjust already-playing cues too; controls are audible immediately.
	for voice in _contacts:
		voice.volume_db = _gain_db(sfx_volume * master_volume * float(voice.get_meta("cue_gain", 1.0)))
	for voice in _feedback:
		voice.volume_db = _gain_db(sfx_volume * master_volume * float(voice.get_meta("cue_gain", 0.8)))
	for voice in _local:
		voice.volume_db = _gain_db(sfx_volume * master_volume * float(voice.get_meta("cue_gain", 0.5)))

func reset_events() -> void:
	_seen.clear()
	_seen_order.clear()
	_last.clear()
	_variants.clear()

func contact(event: Dictionary) -> bool:
	var kind := str(event.get("kind", "touch")).to_lower()
	var cue := "touch"
	if kind in ["pass", "shot"]:
		cue = kind
	elif kind in ["dribble", "carry", "close", "sprint", "turn", "shield", "push"]:
		cue = "dribble"
	elif kind in ["body", "receive", "stop", "settle", "pull", "throw"]:
		cue = "touch"
	var impulse: float = float(event.get("impulse", 1.0))
	var strength: float = clampf(float(event.get("strength01", impulse / 10.0)), 0.12, 1.0)
	return play_event(cue, str(event.get("event_id", "")), event.get("position", Vector3.ZERO),
		int(event.get("actor_id", -1)), strength)

func footstep(event: Dictionary) -> bool:
	if not bool(event.get("grounded", false)) or float(event.get("speed", 0.0)) < 0.4:
		return false
	return play_event("run" if float(event["speed"]) > 5.0 else "step", str(event.get("event_id", "")),
		event.get("position", Vector3.ZERO), int(event.get("actor_id", -1)), 0.6 if float(event["speed"]) > 5.0 else 0.43)

func rule_event(event: Dictionary) -> void:
	var type: String = str(event.get("type", ""))
	if type == "state_changed":
		_phase = str(event.get("state", "IDLE"))
		_apply_mix()
	elif type == "goal":
		play_event("goal", event["event_id"])
	elif type in ["half_time", "full_time"]:
		play_event("period", event["event_id"])
	elif type == "restart_awarded":
		play_event("whistle", event["event_id"])
	elif type == "restart_ready":
		var kind: String = str(event.get("restart", {}).get("kind", ""))
		if kind in ["penalty", "kickoff", "direct_free_kick", "indirect_free_kick"]:
			play_event("ready", event["event_id"])
	elif type == "restart_taken":
		var plan: Dictionary = event["restart"]
		play_event("touch" if plan["kind"] == "throw_in" else "pass", event["event_id"],
			event.get("position", Vector3.ZERO), int(event.get("actor_id", -1)), 0.7)

func play_event(cue: String, event_id: String, at: Vector3 = Vector3.ZERO, actor_id: int = -1, strength: float = 1.0) -> bool:
	if not CUE_FILES.has(cue) or event_id.is_empty():
		return false
	if _seen.has(event_id):
		diagnostics["duplicates"] += 1
		return false
	_seen[event_id] = true
	_seen_order.append(event_id)
	if _seen_order.size() > 2048:
		_seen.erase(_seen_order.pop_front())
	var category := "feet" if cue in ["step", "run"] else "ball" if cue in ["touch", "dribble", "pass", "shot"] else cue
	var key := "%s:%d" % [category, actor_id]
	var interval := 0.16 if category == "feet" else 0.075 if category == "ball" else 0.12
	if _time - float(_last.get(key, -100.0)) < interval:
		diagnostics["throttled"] += 1
		return false
	_last[key] = _time
	var choices: Array = CUE_FILES[cue]
	var bank := "soft" if category == "ball" and strength < 0.58 else "firm"
	if bank == "soft":
		choices = [cue + "_soft_0", cue + "_soft_1", cue + "_soft_2"]
	var variation: int = int(_variants.get(cue, 0)) % choices.size()
	_variants[cue] = variation + 1
	var stream: AudioStream = _streams.get(choices[variation])
	if stream == null:
		diagnostics["missing"] += 1
		return false
	var feedback := cue in ["whistle", "ready", "period", "goal"]
	var gain := strength * 0.50 if category == "feet" else (0.30 + 0.60 * sqrt(strength)) if category == "ball" else strength * .9
	var pitch := 0.96 + float(variation) * 0.04 + (strength - .5) * .08 if category == "ball" else .96 + variation * .025
	var centred := category == "feet" and actor_id == local_actor_id and local_actor_id >= 0
	if feedback:
		var voice := _feedback_voice()
		voice.stream = stream
		voice.set_meta("cue_gain", gain)
		voice.volume_db = _gain_db(master_volume * sfx_volume * gain)
		voice.pitch_scale = 1.0
		voice.play()
		_duck_left = maxf(_duck_left, 1.8)
	elif centred:
		var voice := _local_voice()
		voice.stream = stream
		voice.set_meta("cue_gain", gain)
		voice.volume_db = _gain_db(master_volume * sfx_volume * gain)
		voice.pitch_scale = pitch
		voice.play()
	else:
		var voice := _contact_voice()
		voice.unit_size = 1.2 if category == "feet" else 2.6
		voice.max_distance = 18.0 if category == "feet" else 38.0
		voice.attenuation_filter_cutoff_hz = 4500.0 if category == "feet" else 6500.0
		voice.attenuation_filter_db = -14.0
		voice.global_position = at
		voice.stream = stream
		voice.set_meta("cue_gain", gain)
		voice.volume_db = _gain_db(master_volume * sfx_volume * gain)
		voice.pitch_scale = pitch
		voice.play()
		if category == "ball":
			_duck_left = maxf(_duck_left, 0.22)
	diagnostics["played"] += 1
	recent_mix.append({"cue": cue, "actor_id": actor_id, "bank": bank, "strength": strength,
		"gain": gain, "pitch": pitch, "spatial": not feedback and not centred,
		"max_distance": 18.0 if category == "feet" else 38.0, "stream": str(choices[variation])})
	if recent_mix.size() > 64:
		recent_mix.pop_front()
	return true

func _load_streams() -> void:
	var base: String = get_script().resource_path.get_base_dir().path_join(ASSET_ROOT)
	for files in CUE_FILES.values():
		for file in files:
			if not _streams.has(file):
				_streams[file] = load(base.path_join(str(file) + ".wav"))
	for file in ["music_loop", "stadium_loop"]:
		var stream: AudioStreamWAV = load(base.path_join(file + ".wav"))
		if stream != null:
			stream = stream.duplicate()
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_begin = 0
			stream.loop_end = stream.data.size() / 2
		_streams[file] = stream
	for cue in ["touch", "dribble", "pass", "shot"]:
		for i in range(3):
			var file := "%s_soft_%d" % [cue, i]
			_streams[file] = load(base.path_join(file + ".wav"))

func _local_voice() -> AudioStreamPlayer:
	for voice in _local:
		if not voice.playing:
			return voice
	var voice := _local.pop_front()
	_local.append(voice)
	voice.stop()
	return voice

func _loop_player(key: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = _streams.get(key)
	player.bus = "Master"
	add_child(player)
	player.play()
	return player

func _apply_mix() -> void:
	if _music == null:
		return
	var match_gain := 0.19 if _phase in ["LIVE", "RESTART_IN_FLIGHT", "RESTART_READY"] else 0.5
	_music.volume_db = _gain_db(master_volume * music_volume * match_gain * _duck if music_enabled else 0.0)
	_stadium.volume_db = _gain_db(master_volume * sfx_volume * 0.17 if stadium_enabled else 0.0)

func _gain_db(linear: float) -> float:
	return linear_to_db(linear) if linear > 0.00001 else -80.0

func _contact_voice() -> AudioStreamPlayer3D:
	for voice in _contacts:
		if not voice.playing:
			return voice
	var voice := _contacts.pop_front()
	_contacts.append(voice)
	voice.stop()
	return voice

func _feedback_voice() -> AudioStreamPlayer:
	for voice in _feedback:
		if not voice.playing:
			return voice
	var voice := _feedback.pop_front()
	_feedback.append(voice)
	voice.stop()
	return voice
