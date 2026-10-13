extends RefCounted
## One launch estimate at actual shoe contact. Never steers the free ball.
const Forces := preload("res://addons/football_physics/ball_forces.gd")

static func arrival_speed(distance:float,p:FootballPhysicsProfile=null)->float:
	if p==null:p=FootballPhysicsProfile.playable()
	return clampf(p.pass_arrival_base_mps+maxf(0,distance)*p.pass_arrival_per_m,p.pass_arrival_base_mps,p.pass_arrival_max_mps)

static func launch_speed(distance:float,p:FootballPhysicsProfile)->float:
	var reserve:float=Forces.rolling_distance_for_speed(arrival_speed(distance,p),p)
	return Forces.speed_for_rolling_distance(maxf(0,distance)+reserve,p)

static func power_for_distance(distance:float,p:FootballPhysicsProfile)->float:
	var fraction:float=(distance-p.ground_pass_min_distance_m)/maxf(.001,p.ground_pass_max_distance_m-p.ground_pass_min_distance_m)
	return pow(clampf(fraction,0,1),1.0/p.ground_pass_distance_exponent)

static func roll_time(distance: float, speed: float, p: FootballPhysicsProfile) -> float:
	var traveled := 0.0
	var time := 0.0
	var dt := 1.0 / 60.0
	var k := .5*p.air_density_kgpm3*PI*p.ball_radius_m*p.ball_radius_m/p.ball_mass_kg
	while traveled < distance and speed > p.rest_speed_mps and time < 3.0:
		var loss := Forces.rolling_deceleration_mps2(speed,p)
		if p.drag_enabled: loss += k*Forces.drag_coefficient(speed,p)*speed*speed
		var after := maxf(0.0,speed-loss*dt)
		traveled += (speed+after)*.5*dt
		speed = after
		time += dt
	return time

static func solve(origin: Vector3, target: Vector3, velocity: Vector3, intent: Dictionary, reference: Vector3, p: FootballPhysicsProfile) -> Dictionary:
	var result := intent.duplicate(true)
	var aim: Vector3 = intent.direction
	var original := Vector3(reference.x-origin.x,0,reference.z-origin.z)
	var toward := Vector3(target.x-origin.x,0,target.z-origin.z)
	# An explicitly off-target pass remains an intentional direction pass.
	if original.length()<2.0 or toward.length()<2.0 or toward.length()>35.0 or aim.angle_to(original)>deg_to_rad(20.0): return result
	var distance := toward.length()
	var receive_speed:float=arrival_speed(distance,p)
	var requested := lerpf(p.ground_pass_min_distance_m,p.ground_pass_max_distance_m,pow(clampf(float(intent.power),0,1),p.ground_pass_distance_exponent))
	# Keep a bounded part of charge error: weak/strong passes can still miss.
	var charge_bias := clampf((requested-original.length())*.35,-distance*.25,distance*.25)
	var lead := Vector3.ZERO
	var speed := 0.0
	var flight := 0.0
	var run := Vector3(velocity.x,0,velocity.z).limit_length(7.0)
	for _i in 3:
		var range_m := clampf((toward+lead).length()+charge_bias,p.ground_pass_min_distance_m,p.ground_pass_max_distance_m)
		var pace_power:float=lerpf(power_for_distance(range_m,p),clampf(float(intent.power),0,1),.55)
		var paced_range:float=lerpf(p.ground_pass_min_distance_m,p.ground_pass_max_distance_m,pow(pace_power,p.ground_pass_distance_exponent))
		speed = launch_speed(paced_range,p)
		flight = roll_time((toward+lead).length(),speed,p)
		lead = (run*minf(flight,1.25)).limit_length(minf(6.0,distance*.45))
	var landing := toward+lead
	var roll_range := clampf(landing.length()+charge_bias,p.ground_pass_min_distance_m,p.ground_pass_max_distance_m)
	var fraction := (roll_range-p.ground_pass_min_distance_m)/maxf(.001,p.ground_pass_max_distance_m-p.ground_pass_min_distance_m)
	result.power = lerpf(pow(clampf(fraction,0,1),1.0/p.ground_pass_distance_exponent),clampf(float(intent.power),0,1),.55)
	# Retain the user's/planner's small directional offset, rather than erase it.
	var offset:float=float(intent.get("ground_pass_aim_offset",0.0))
	result.direction = landing.normalized().rotated(Vector3.UP,offset)
	result["ground_pass_solution"] = {"target":origin+result.direction*landing.length(),"lead_m":lead.length(),"travel_s":flight,"roll_range_m":roll_range,"charge_bias_m":charge_bias,"arrival_target_mps":receive_speed}
	return result
