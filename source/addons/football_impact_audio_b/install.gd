class_name FBImpactAudioInstallerB
extends RefCounted
const ImpactScript = preload("impact_audio.gd")

static func install(services: Node3D, hub: Node, ball: Node3D) -> FBMatchAudioDirector:
	var old: FBMatchAudioDirector = services.get("audio")
	if old == null:
		push_error("Install audio B after MatchServices has completed _ready")
		return null
	if old.get_script() == ImpactScript: return old
	var replacement := ImpactScript.new()
	replacement.name = old.name
	for property in ["master_volume", "sfx_volume", "music_volume", "music_enabled", "stadium_enabled", "local_actor_id", "max_contact_voices", "max_feedback_voices"]:
		replacement.set(property, old.get(property))
	replacement.set("_phase", old.get("_phase"))
	_stop_players(old)
	var parent := old.get_parent()
	parent.remove_child(old)
	services.set("audio", replacement)
	parent.add_child(replacement)
	replacement.bind_ball(ball)
	for signal_name in ["contact_resolved", "body_contact"]:
		if hub != null and hub.has_signal(signal_name):
			hub.connect(signal_name, Callable(replacement, "consume_resolved_contact"))
	old.queue_free()
	return replacement

static func _stop_players(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer3D: node.stop()
	for child in node.get_children(): _stop_players(child)
