extends "res://scripts/football_player.gd"
## Inherits the current player/head/pose/foot files without overwriting them.
const SharedMovement := preload("res://scripts/football_shared_movement.gd")
var shared_last_result: Dictionary = {}
func uses_shared_movement()->bool:
	return controller_v07_enabled
func _physics_process(delta: float) -> void:
	var _w:int=Time.get_ticks_usec()
	_physics_process_body(delta)
	preload("res://scripts/frame_spike_watch.gd").human_us+=Time.get_ticks_usec()-_w # R006 CPU breakdown
func _physics_process_body(delta: float) -> void:
	var before := {"stamina":stamina,"sprint_locked":sprint_locked}
	# Released view, permission, cooldown, stop and pose bookkeeping stays live.
	super._physics_process(delta)
	if is_instance_valid(interaction) and not interaction.accepts_mobility_input():
		shared_last_result = {"protected_mobility":true}
		return # Preserve the base low-state cap and cost; do not regenerate stamina.
	var intended := semantic_motion if input_enabled else Vector3.ZERO
	var pressure:RefCounted=match_controller.input_bridge.pressure
	if pressure.active and input_enabled:
		intended=pressure.motion
		locomotion="run" if velocity.length()>3.5 else "jockey"
	if input_enabled: intended = match_controller.constrained_human_intent(intended)
	var command := {"enabled":input_enabled,"move":intended,"tier":movement_tier,"style":semantic_move_style,"close_control":semantic_policies.get("close_control",false),"shield":semantic_policies.get("shield",false)}
	if match_controller.ball.carrier==self and movement_tier!="run":command.close_control=true
	if pressure.active:
		command.tier="run"
		command.style="run"
		command.requested_pace=pressure.pace
		command.close_control=false
		command.shield=false
	shared_last_result = SharedMovement.apply(self,match_controller,command,before,delta)
