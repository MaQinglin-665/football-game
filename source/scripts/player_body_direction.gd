extends RefCounted
## Camera-relative input is authoritative. Hips are an output, never an input axis.
static func target(view_yaw:float,intent:Vector3,velocity:Vector3,owned:bool,guard:bool=false)->float:
	var view:=Vector3(-sin(view_yaw),0,-cos(view_yaw))
	intent.y=0;velocity.y=0
	if intent.length()<.05:return view_yaw
	var move:=intent.normalized()
	# Backpedal/sole pull faces the view, even while the old hips face elsewhere.
	if move.dot(view)<-.2:return view_yaw
	var requested:=angle_difference(view_yaw,atan2(-move.x,-move.z))
	var momentum:=angle_difference(view_yaw,atan2(-velocity.x,-velocity.z)) if velocity.length()>.05 else requested
	# Smooth speed weighting replaces the old hard switch at 2 m/s.
	# Clamp offsets before blending so looking behind cannot wrap the hips.
	var limit:=deg_to_rad(18.0 if guard else 35.0 if owned else 60.0)
	var bias:=lerpf(clampf(requested,-limit,limit),clampf(momentum,-limit,limit),.25*smoothstep(.5,4.5,velocity.length()))
	return view_yaw+bias*smoothstep(.1,1.4,velocity.length())
