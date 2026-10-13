extends "res://addons/football_recorded_impact/recorded_impact.gd"
## Contract fixture: no tree, voices, AudioServer, device or real audio output.
var submissions: Array[Dictionary] = []
var legacy_calls: Array[Dictionary] = []

func _ready() -> void: pass
func _process(_delta: float) -> void: pass
func _exit_tree() -> void: pass
func _load_streams() -> void: pass

func prime() -> void:
	for choices in Samples.FILES.values():
		for file in choices: _streams[file] = AudioStreamGenerator.new()

func _submit_recorded_voice(stream: AudioStream, at: Vector3, local: bool, gain: float) -> void:
	submissions.append({"stream": stream, "position": at, "local": local, "gain": gain})

func _legacy_play(cue: String, event_id: String, at: Vector3, actor_id: int, strength: float) -> bool:
	legacy_calls.append({"cue": cue, "event_id": event_id, "position": at, "actor_id": actor_id, "strength": strength})
	return false # Routing capture, not an assertion that the legacy mixer played.

func clear_capture() -> void:
	reset_events()
	submissions.clear()
	legacy_calls.clear()
	recent_mix.clear()
