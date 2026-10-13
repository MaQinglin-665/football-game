extends RefCounted
## Team-local 4-3-3 staging targets. The host walks AI here and the referee
## still projects/validates every target; this helper never moves a body.
const Roles := preload("res://scripts/tactics/role_catalog.gd")

static func kickoff_target(role: String, lane: float, attack: float, width: float, length: float) -> Vector3:
	var local := Vector2(lane*width*.48,-length*.28)
	match role:
		Roles.GOALKEEPER:
			local = Vector2(0,-length*.94)
		Roles.CENTER_BACK:
			local = Vector2(lane*width*.40,-length*.72)
		Roles.FULL_BACK:
			local = Vector2(lane*width*.70,-length*.64)
		Roles.MIDFIELDER:
			local = Vector2(lane*width*.48,-length*(.46 if absf(lane)<.1 else .32))
		Roles.ATTACKING_MIDFIELDER:
			local = Vector2(lane*width*.48,-length*.24)
		Roles.WINGER,Roles.LEFT_MIDFIELDER,Roles.RIGHT_MIDFIELDER:
			var side := -1.0 if role==Roles.LEFT_MIDFIELDER else 1.0 if role==Roles.RIGHT_MIDFIELDER else lane
			local = Vector2(side*width*.70,-length*.12)
		Roles.STRIKER:
			local = Vector2(lane*width*.20,-maxf(11.5,length*.22))
	# Team right also rotates at half-time, exactly as the live planner's frame.
	return Vector3(-attack*local.x,0,attack*local.y)
