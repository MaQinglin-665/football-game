extends RefCounted
## View chooses facing; keys choose translation. The motor limits actual yaw.
## Ball-contact and committed-follow adjustments are owned by the caller.
static func target(view_yaw:float,_intent:Vector3,_velocity:Vector3,_owned:bool,_guard:bool=false)->float:
	return view_yaw
