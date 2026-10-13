extends RefCounted
# Route risk only. The existing director remains the sole intent owner.
static func inspect(p:Dictionary,point:Vector3,opponents:Array[Dictionary],speed:float=5.0)->Dictionary:
	var start:Vector3=Vector3(p.position.x,0,p.position.z)
	var direction:Vector3=(point-start).normalized()
	var clearance:float=20.0
	var immediate:float=20.0
	var closing:float=0.0
	var escape:float=0.0
	var contact_time:float=10.0
	var frontal:bool=false
	var trailing:bool=false
	for other in opponents:
		var relative:Vector3=Vector3(other.position.x,0,other.position.z)-start
		var velocity:Vector3=Vector3(other.velocity.x,0,other.velocity.z)
		var gap:float=relative.length()
		var own_velocity:Vector3=p.get("velocity",Vector3.ZERO)
		var approach:float=(Vector3(own_velocity.x,0,own_velocity.z)-velocity).dot(relative.normalized())
		var predicted_contact:float=maxf(0,gap-.85)/maxf(.05,approach)
		if predicted_contact<contact_time:
			contact_time=predicted_contact
			frontal=relative.normalized().dot(direction)>.15
			trailing=relative.normalized().dot(direction)<-.35
		if gap<4.0:closing=maxf(closing,approach)
		# Sample concurrent travel, not distance to a segment that includes the
		# trailing defender forever. Near-horizon collision still cancels a run.
		for t in [.16,.32,.55,.85]:
			var travelled:float=minf(start.distance_to(point),speed*t)
			var separation:float=(relative+velocity*t-direction*travelled).length()
			clearance=minf(clearance,separation)
			if t<=.32:immediate=minf(immediate,separation)
		if gap<3.2:
			escape=maxf(escape,(relative+velocity*.6-direction*speed*.6).length()-gap)
	return {"clearance":clearance,"immediate":immediate,"closing":closing,"escape":escape,"contact_time":contact_time,"frontal":frontal,"trailing":trailing}
