extends "res://scripts/football.gd"
## Existing ball physics remains authoritative before/after a hand contact.
var keeper_host: Node

func clear_control(cancel_actions := true) -> void:
	if is_instance_valid(keeper_host): keeper_host.external_clear("host_clear_control")
	super.clear_control(cancel_actions)

func _substep(delta: float) -> void:
	if not is_instance_valid(keeper_host):
		super._substep(delta)
		return
	keeper_host.begin_substep(delta)
	if held: return
	var predicted := global_position + velocity * delta + Vector3.DOWN * profile.gravity_mps2 * .5 * delta * delta
	var contact: Dictionary = keeper_host.first_contact(global_position,predicted)
	if contact.is_empty():
		super._substep(delta)
		return
	var fraction := clampf(float(contact.fraction),0.0,1.0)
	if fraction > .000001: super._substep(delta*fraction)
	# Confirm again at the physical ball position after any earlier torso/post hit.
	keeper_host.resolve_contact(contact)
	if not held and fraction < .999999: super._substep(delta*(1.0-fraction))
