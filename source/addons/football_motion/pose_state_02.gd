extends RefCounted
## Explicit semantics from the host. No Shift recognizer, timer or ball force.
static func control_tier(policy:Dictionary,owned:bool,close:bool,shield:bool,active_kind:String,knock_chase_seconds:float=0.0)->String:
	if active_kind.to_upper()=="SPRINT" or knock_chase_seconds>0:return "KNOCK_CHASE"
	if close or shield:return "CLOSE"
	if not owned:return "FREE"
	if bool(policy.get("enabled",false)):
		return "CRUISE" if String(policy.get("tier","")).to_lower() in ["run","cruise","hold","hold_shift"] else "CLOSE"
	return "CRUISE"

static func stamp(state:Dictionary,pose_tick:int,tier:String,pose_world_step:int=-1)->Dictionary:
	var result:=state.duplicate()
	result.pose_tick=pose_tick
	result.pose_world_step=pose_world_step
	result.control_tier=tier
	return result
