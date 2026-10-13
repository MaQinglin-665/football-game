extends RefCounted
# Shared approach geometry; tactical layer retains exclusive target ownership.
# No collision, possession or player input changes here.
const STANDOFF := 1.12
const INSIDE_BIAS := .48
const SHOULDER_CLEARANCE := .76
static func target(defender:Vector3,owner:Vector3,velocity:Vector3,ball:Vector3,goalward:Vector3)->Vector3:
	velocity.y=0
	goalward.y=0
	goalward=goalward.normalized()
	var offset:Vector3=defender-owner;offset.y=0
	var distance:float=offset.length()
	var horizon:float=clampf(distance/14.0,.06,.24)
	var ahead:Vector3=owner+velocity*horizon
	var inside:Vector3=Vector3(-clampf(owner.x/3.0,-1,1),0,0)
	var lane:Vector3=(goalward+inside*INSIDE_BIAS).normalized()
	var exposed:Vector3=ball-owner;exposed.y=0
	var ball_lane:Vector3=ball-defender;ball_lane.y=0
	var closest:Vector3=Geometry3D.get_closest_point_to_segment(owner,defender,ball)
	var reachable_side:bool=Vector2(closest.x-owner.x,closest.z-owner.z).length()>.40 or ball_lane.length()<distance-.16
	# An actual exposed boot-side ball is a tackle window, not a mandate to
	# press straight through the carrier's protected central channel.
	if reachable_side and exposed.length()>.32 and ball_lane.length()<1.3:
		return ball+(defender-ball).normalized()*.48
	var desired:Vector3=ahead+lane*STANDOFF
	# Already alongside and goal-side: take a reachable screening shoulder.
	if distance<1.25 and offset.dot(goalward)>.10:
		desired=ahead+lane*SHOULDER_CLEARANCE
	# If beaten, arc around the nearest shoulder; never cut through the torso.
	var crossing:Vector3=Geometry3D.get_closest_point_to_segment(owner,defender,desired)
	if distance>.45 and Vector2(crossing.x-owner.x,crossing.z-owner.z).length()<.62:
		var side:Vector3=Vector3(-goalward.z,0,goalward.x)
		if side.dot(offset)<0:side=-side
		desired=ahead+side*.86+goalward*.45
	desired.y=defender.y
	return desired
static func facing(watch:Vector3,position:Vector3,_goalward:Vector3)->Vector3:
	watch.y=0
	if watch.length_squared()<.001:return Vector3.FORWARD
	# Bias the open shoulder toward the touchline; continuous at midfield.
	var outward:Vector3=Vector3(clampf(position.x/3.0,-1,1),0,0)
	var cross:float=watch.normalized().cross(outward).y
	var angle:float=clampf(cross,-1,1)*.28
	return watch.normalized().rotated(Vector3.UP,angle)
