class_name FBRecordedImpactInstaller
extends RefCounted
const Recorded = preload("recorded_impact.gd")

static func install(services: Node3D, hub: Node, ball: Node3D, enabled: bool = true) -> FBMatchAudioDirector:
	var old: FBMatchAudioDirector = services.get("audio")
	if old == null:
		push_error("Install recorded audio after MatchServices ready, before match start")
		return null
	if old.get_script() == Recorded:
		old.set("recorded_impacts_enabled", enabled)
		return old
	var replacement = Recorded.new()
	replacement.name = old.name
	var old_properties: Dictionary = {}
	for item in old.get_property_list(): old_properties[str(item["name"])] = true
	for property in ["master_volume", "sfx_volume", "music_volume", "music_enabled", "stadium_enabled", "local_actor_id", "max_contact_voices", "max_feedback_voices", "centre_local_ball", "impact_reference_scale", "surface_burst_gap"]:
		if old_properties.has(property): replacement.set(property, old.get(property))
	replacement.set("_phase", old.get("_phase"))
	replacement.recorded_impacts_enabled = enabled
	replacement.use_resolved_hub_contacts = true
	_stop_players(old)
	# Disconnect the previous owner immediately, including a prior B installation.
	for signal_name in ["contact_resolved", "body_contact"]:
		if hub != null and hub.has_signal(signal_name):
			var callback: Callable = Callable(old, "consume_resolved_contact")
			if hub.is_connected(signal_name, callback): hub.disconnect(signal_name, callback)
	if ball != null and ball.has_signal("physical_contact"):
		var callback: Callable = Callable(old, "_on_surface_contact")
		if ball.is_connected("physical_contact", callback): ball.disconnect("physical_contact", callback)
	var parent: Node = old.get_parent()
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
