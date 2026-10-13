extends RefCounted
static func factor(velocity:Vector3,desired:Vector3,strength:float)->float:
	if desired.length_squared()<.0025:return 1.0
	var speed:float=Vector2(velocity.x,velocity.z).length()
	var angle_weight:float=smoothstep(.12,1.35,1.0-velocity.normalized().dot(desired.normalized()))
	return 1.0-clampf(strength,0,.40)*smoothstep(2.2,5.5,speed)*angle_weight
