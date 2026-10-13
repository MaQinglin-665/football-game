extends RefCounted
# Shared physical approach target only: no victim input/speed/possession writes.
static func target(defender:Vector3,owner:Vector3,velocity:Vector3,ball:Vector3,goalward:Vector3)->Vector3:
	velocity.y=0
	goalward.y=0
	goalward=goalward.normalized()
	var ahead:Vector3=owner+velocity*clampf(defender.distance_to(owner)/12.0,.08,.28)
	var exposed:Vector3=ball-owner;exposed.y=0
	var from_owner:Vector3=defender-owner;from_owner.y=0
	var side:Vector3=Vector3(-goalward.z,0,goalward.x)
	if side.dot(from_owner)<0:side=-side
	# Stay on a reachable shoulder when screened; do not drive through the carrier.
	if exposed.length()>.30 and exposed.normalized().dot(from_owner.normalized())>.5:
		return ball+(defender-ball).normalized()*.48
	return ahead+goalward*.38+side*.48
