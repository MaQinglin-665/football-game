extends Node

var enabled := true
var streams: Dictionary = {}

func _ready() -> void:
	streams["kick"] = make_tone(95, 0.10, 0.4, 0.5)
	streams["pass"] = make_tone(130, 0.08, 0.28, 0.5)
	streams["whistle"] = make_tone(1850, 0.23, 0.20, 0.03)
	streams["tackle"] = make_tone(75, 0.09, 0.24, 0.65)
	streams["goal"] = make_tone(550, 0.72, 0.26, 0.0, true)

func play(cue: String) -> void:
	if not enabled or DisplayServer.get_name() == "headless":
		return
	var voice := AudioStreamPlayer.new()
	voice.stream = streams.get(cue)
	voice.volume_db = -7
	add_child(voice)
	voice.finished.connect(voice.queue_free)
	voice.play()

func make_tone(hz: float, duration: float, amplitude: float, noise: float, melody := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	var samples := int(22050 * duration)
	bytes.resize(samples * 2)
	var random := RandomNumberGenerator.new()
	random.seed = 43
	for i in range(samples):
		var t := float(i) / 22050.0
		var f := hz * (pow(2.0, float(mini(int(t * 6), 3)) / 4.0) if melody else 1.0)
		var wave := sin(TAU * f * t) * (1.0 - noise) + random.randf_range(-1, 1) * noise
		var envelope := minf(t * 80, 1.0) * pow(1.0 - t / duration, 1.6)
		bytes.encode_s16(i * 2, int(clampf(wave * envelope * amplitude, -1, 1) * 32767))
	var result := AudioStreamWAV.new()
	result.format = AudioStreamWAV.FORMAT_16_BITS
	result.mix_rate = 22050
	result.data = bytes
	return result
