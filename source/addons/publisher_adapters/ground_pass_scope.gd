extends "res://addons/football_ground_pass/ground_pass_controller.gd"
## Preserve the settings API, retire the historical right-only pass slot.
func request_semantic_kick(intent: Dictionary, speed := 0.0, lift := 0.0, target_actor: Node3D = null) -> bool:
	ground_pass_enabled = false
	return super.request_semantic_kick(intent,speed,lift,target_actor)
