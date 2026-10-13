extends RefCounted
## One horizontal integrator for the motor and collision-free predictions.
## Preset 0 light, 1 medium, 2 previous motor (comparison only).
static func step(flat:Vector3,desired:Vector3,p:Resource,sprint:float,dt:float,guard:bool=false)->Vector3:
	var mode:int=int(p.get_meta("movement_inertia",0))
	var speed:float=flat.length()
	var acceleration:float=lerpf(p.start_acceleration_mps2,p.sprint_acceleration_mps2,sprint)
	if mode==2:
		if desired.length()<speed or desired.dot(flat)<0:acceleration=p.brake_deceleration_mps2
		elif speed>.5 and desired.normalized().dot(flat.normalized())<.80:acceleration=p.turn_acceleration_mps2
		else:acceleration*=maxf(0,1-speed/p.theoretical_max_speed_mps)
		acceleration*=preload("res://scripts/turn_inertia.gd").factor(flat,desired,p.turn_inertia_strength)
		return flat.move_toward(desired,acceleration*dt)
	if guard:desired=desired.limit_length(3.0)
	var brake:float=10.5 if mode==0 else 9.0
	if guard:brake=12.0
	if desired.length_squared()<.0001:return flat.move_toward(Vector3.ZERO,brake*dt)
	# Small corrections preserve the old responsive envelope. No action timer.
	if speed<2.2:
		if desired.dot(flat)<0 or desired.length()<speed:acceleration=brake
		elif speed>.5 and desired.normalized().dot(flat.normalized())<.80:acceleration=8.5 if guard else p.turn_acceleration_mps2
		else:acceleration*=maxf(0,1-speed/p.theoretical_max_speed_mps)
		return flat.move_toward(desired,acceleration*dt)
	var axis:Vector3=flat/speed
	var along:float=desired.dot(axis)
	var lateral:Vector3=desired-axis*along
	# Brake the existing momentum immediately; lateral steering has its own budget.
	var forward_accel:float=brake if along<speed else acceleration*maxf(0,1-speed/p.theoretical_max_speed_mps)
	var next_along:float=move_toward(speed,along,forward_accel*dt)
	var lateral_limit:float=lerpf(p.turn_acceleration_mps2,4.8 if mode==0 else 3.6,smoothstep(2.2,7.0,speed))
	if guard:lateral_limit=8.5
	var result:Vector3=axis*next_along+lateral.limit_length(lateral_limit*dt)
	return result.limit_length(maxf(speed,desired.length()))

static func yaw_rate(speed:float)->float:
	return lerpf(6.2,2.5,smoothstep(2.2,7.0,speed))
