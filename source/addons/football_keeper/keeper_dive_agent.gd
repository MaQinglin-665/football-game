extends "res://scripts/football_shared_agent.gd"
## GK-only motor hook. No changes to the shared World or other actors.
var keeper_dive: RefCounted

func keeper_dive_allowed() -> bool:
	return keeper_dive!=null and keeper_dive.owns_low_state()

func advance_motor(dt: float) -> void:
	if keeper_dive!=null and keeper_dive.advance_motor(dt):
		_apply_origin_ground_support(dt)
		return
	if is_instance_valid(match_controller.ball.keeper_host) and match_controller.ball.keeper_host.reserve_slow_capture(self):set_move_intent(Vector3.ZERO)
	super.advance_motor(dt)
