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
	var profile=row.get("motor_profile",snapshot.motor_profile)
	var cfg=row.get("movement_cfg",snapshot.movement_cfg)
	var actor_cap:Dictionary=snapshot.capabilities.duplicate()
	actor_cap.receive_speed=float(row.get("ability_speed",actor_cap.get("receive_speed",5.6)))
	actor_cap.brake_deceleration=profile.brake_deceleration_mps2
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
		yaw+=clampf(angle_difference(yaw,atan2(-desired_face.x,-desired_face.z)),-preload("res://scripts/movement_inertia.gd").yaw_rate(velocity.length())*dt,preload("res://scripts/movement_inertia.gd").yaw_rate(velocity.length())*dt)
		facing=Vector3(-sin(yaw),0,-cos(yaw))
		var gap:Vector3=flat(target-position)
		var requested:float=pace(position,target,velocity,actor_cap)
		var move:Vector3=gap.normalized() if gap.length()>.18 else Vector3.ZERO
		var resolved:Vector4=Shared.resolve_receiving_budget(move,facing,velocity,stamina,locked,float(row.get("foot_cap",100)),requested,cfg,dt)
		stamina=resolved.y;locked=resolved.z>0
		var desired:Vector3=move*resolved.x
		velocity=preload("res://scripts/movement_inertia.gd").step(velocity,desired,profile,resolved.w,dt)
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
			var item:Dictionary={"point":position,"speed":velocity.length(),"velocity":velocity,"time":(bucket*8+j+1)*dt}
			if low.is_empty() or position.y<float(low.point.y):low=item
			if descending.is_empty() and position.y<=.42 and velocity.length()<=14.0 and absf(velocity.y)<=3.0:descending=item
		samples.append(descending if not descending.is_empty() else low)
	return samples
