extends RefCounted
# Original adapter: read-only forecast of the same shared movement and horizontal motor.
const Shared=preload("res://scripts/football_shared_movement.gd")
const Inertia=preload("res://scripts/turn_inertia.gd")
const Forces=preload("res://addons/football_physics/ball_forces.gd")
static func flat(v:Vector3)->Vector3:return Vector3(v.x,0,v.z)
static func travel_facing(position:Vector3,target:Vector3,incoming:Vector3,remaining:float)->Vector3:
	var move:Vector3=flat(target-position)
	# Far or late receivers keep chasing. Open the foot only inside a reachable last step.
	var gap:float=move.length()
	if gap>.95:return move.normalized()
	var blend:float=smoothstep(.35,.95,gap)
	return incoming.normalized().slerp(move.normalized(),blend).normalized() if gap>.05 else incoming
static func pace(position:Vector3,target:Vector3,velocity:Vector3,cap:Dictionary)->float:
	var gap:float=flat(target-position).length()
	var brake:float=maxf(1,float(cap.get("brake_deceleration",5.5)))
	return minf(float(cap.get("receive_speed",5.6)),sqrt(2*brake*maxf(0,gap-.10)))
static func predict(row:Dictionary,target:Vector3,incoming:Vector3,horizon:float,snapshot:Dictionary)->Dictionary:
	var profile=snapshot.motor_profile
	var cfg=snapshot.movement_cfg
	var position:Vector3=flat(row.position)
	var velocity:Vector3=flat(row.get("velocity",Vector3.ZERO))
	var facing:Vector3=flat(row.get("facing",incoming)).normalized()
	var stamina:float=float(row.get("stamina",100))
	var locked:bool=bool(row.get("sprint_locked",false))
	var duration:float=maxf(0,horizon-.065) # contact preparation/reaction budget, not a runtime wait
	var count:int=maxi(1,int(ceil(duration/.06)))
	var dt:float=duration/count
	for i in count:
		var desired_face:Vector3=travel_facing(position,target,incoming,horizon-float(i)*dt)
		var yaw:float=atan2(-facing.x,-facing.z)
		yaw+=clampf(angle_difference(yaw,atan2(-desired_face.x,-desired_face.z)),-5.8*dt,5.8*dt)
		facing=Vector3(-sin(yaw),0,-cos(yaw))
		var gap:Vector3=flat(target-position)
		var requested:float=pace(position,target,velocity,snapshot.capabilities)
		var command:Dictionary={"enabled":true,"move":gap.normalized() if gap.length()>.18 else Vector3.ZERO,"tier":"run" if requested>cfg.normal_move_speed else "walk_jog","requested_pace":requested,"receiving":true}
		var state:Dictionary={"owned":false,"facing":facing,"velocity":velocity,"stamina":stamina,"sprint_locked":locked,"foot_cap":float(row.get("foot_cap",100))}
		var resolved:Dictionary=Shared.resolve(command,state,cfg,dt)
		stamina=resolved.stamina;locked=resolved.sprint_locked
		var desired:Vector3=resolved.motion
		var acceleration:float=profile.sprint_acceleration_mps2 if resolved.sprint else profile.start_acceleration_mps2
		if desired.length()<velocity.length() or desired.dot(velocity)<0:acceleration=profile.brake_deceleration_mps2
		elif velocity.length()>.5 and desired.normalized().dot(velocity.normalized())<.80:acceleration=profile.turn_acceleration_mps2
		else:acceleration*=maxf(0,1-velocity.length()/profile.theoretical_max_speed_mps)
		acceleration*=Inertia.factor(velocity,desired,profile.turn_inertia_strength)
		velocity=velocity.move_toward(desired,acceleration*dt)
		position+=velocity*dt
	return {"position":position,"velocity":velocity,"facing":facing,"gap":flat(target-position).length(),"collision_free_estimate":true}
static func ball_samples(position:Vector3,velocity:Vector3,spin:Vector3,profile:FootballPhysicsProfile)->Array:
	var samples:Array=[]
	# Resolve bounce/contact-height windows inside each 100ms forecast bucket.
	# Sampling only bucket endpoints could miss the entire descending foot window
	# and suddenly send a waiting receiver back towards the airborne ball.
	var dt:float=.0125
	var buckets:int=48 if position.y>.45 or velocity.y>.6 else 30
	for bucket in buckets:
		var low:Dictionary={}
		var descending:Dictionary={}
		for j in 8:
			var supported:bool=position.y<=profile.ball_radius_m+.012 and velocity.y<=.10
			var step:Dictionary=Forces.rolling_step(velocity,spin,Vector3.UP,dt,Vector3.ZERO,profile) if supported else Forces.airborne_step(velocity,spin,dt,Vector3.ZERO,profile)
			position+=step.motion;velocity=step.velocity;spin=step.spin
			if position.y<profile.ball_radius_m:
				position.y=profile.ball_radius_m
				var bounce:Dictionary=preload("res://addons/football_physics/contact_math.gd").sphere_response(velocity,spin,Vector3.ZERO,Vector3.UP,0.0,profile.turf_restitution if -velocity.y>profile.low_bounce_cutoff_mps else 0.0,profile.bounce_friction_coefficient,profile,false)
				velocity=bounce.velocity;spin=bounce.spin
				if velocity.y<=profile.rest_speed_mps:velocity.y=0
			var item:Dictionary={"point":position,"speed":velocity.length(),"time":(bucket*8+j+1)*dt}
			if low.is_empty() or position.y<float(low.point.y):low=item
			if descending.is_empty() and position.y<=.42 and velocity.length()<=14.0:descending=item
		samples.append(descending if not descending.is_empty() else low if low.point.y>.42 else {"point":position,"speed":velocity.length(),"time":(bucket+1)*.1})
	return samples
