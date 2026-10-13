extends RefCounted
## Three-speed directional assistance. Only real contact may change ball velocity.
## No force/position writes, camera writes, new input keys or permission changes.
static func enabled(actor:Node3D)->bool:
	if actor.is_human: return not "--three-speed-turn=A" in OS.get_cmdline_user_args() and not "--dribble-turn=A" in OS.get_cmdline_user_args() and not "--dribble-rhythm=A" in OS.get_cmdline_user_args()
	return actor.has_method("ai_ordinary_turn") and actor.ai_ordinary_turn()

static func ordinary(actor:Node3D)->bool:
	if not enabled(actor) or actor.stop_requested>0 or actor.foot.has_buffer():return false
	return actor.match_controller.ball.carrier==actor and (actor.foot.idle() or actor.foot.planned_dribble())

static func angle(actor:Node3D,aim:Vector3)->float:
	if aim.length_squared()<.0001:return 0.0
	var run:Vector3=actor.velocity;run.y=0
	var value:float=run.normalized().angle_to(aim.normalized()) if run.length()>.20 else 0.0
	# Preserve the turn context only within this already-preparing unhit shoe.
	# This adds no timer/input delay and cannot redirect an already released ball.
	if actor.foot.planned_dribble() and not actor.foot.hit:
		var entry:Vector3=actor.foot.touch_plan.get("turn_entry_velocity",Vector3.ZERO);entry.y=0
		if entry.length()>.20:value=maxf(value,entry.normalized().angle_to(aim.normalized()))
	return value

static func weight(actor:Node3D,aim:Vector3)->float:
	return smoothstep(deg_to_rad(15.0),deg_to_rad(40.0),angle(actor,aim))

static func braking(actor:Node3D,aim:Vector3)->bool:
	if not ordinary(actor) or actor.shielding:return false
	var run:Vector3=actor.velocity;run.y=0
	return actor.foot.ordinary_scheduler.high_gear(actor) and aim.length_squared()>.001 and run.normalized().dot(aim.normalized())<-.25

static func motion(actor:Node3D,_ball:Node3D,aim:Vector3,maximum:float,original:Vector3,correction:Vector3)->Vector3:
	if not ordinary(actor):return original
	var w:float=weight(actor,aim)
	if w>0: # Same reachable moving pocket for AI; human behavior is unchanged.
		return (aim*maxf(original.dot(aim),maximum*.72)+correction.limit_length(.10)*2.0).limit_length(maximum)
	if w<=0:return original # 036 straight slow carry is exact.
	var speed:float=Vector2(actor.velocity.x,actor.velocity.z).length()
	var high:float=smoothstep(2.10,3.20,speed)
	# Low turns leave lateral ball repair to the selected shoe, not a strong
	# body attraction. High turns blend away from the abrupt .45m/s target floor;
	# the unchanged motor still brakes the existing velocity before accelerating.
	var drive:float=maxf(0.0,original.dot(aim))
	var turn_scale:float=lerpf(1.0,.35,smoothstep(deg_to_rad(60.0),deg_to_rad(150.0),angle(actor,aim)))
	drive=lerpf(drive,maxf(drive,maximum*turn_scale),high)
	var proposed:Vector3=(aim*drive+correction.limit_length(.05)*2.0).limit_length(maximum)
	return original.lerp(proposed,w)

static func chase_brake(actor:Node3D,ball:Node3D,aim:Vector3,old_chase:bool)->float:
	if not ordinary(actor) or aim.length_squared()<.0025:return -1.0
	var speed:float=Vector2(actor.velocity.x,actor.velocity.z).length()
	var w:float=weight(actor,aim)*smoothstep(2.10,3.20,speed)
	if w<=0:return -1.0
	var offset:Vector3=ball.position-actor.position;offset.y=0
	var gap:float=offset.length()
	if gap<.001:return -1.0
	var direction:Vector3=aim.normalized()
	var corridor:float=smoothstep(.15,.70,offset.normalized().dot(direction))*(1.0-smoothstep(.45,.90,offset.slide(direction).length()))
	var smooth_brake:float=smoothstep(.68,1.05,gap)*(1.0-corridor)
	var original:float=1.0 if gap>.80 and not old_chase else 0.0
	return lerpf(original,smooth_brake,w)

static func needs_low_repair(actor:Node3D,ball:Node3D,aim:Vector3)->bool:
	if not ordinary(actor) or actor.foot.ordinary_scheduler.high_gear(actor):return false
	if weight(actor,aim)<=0:return false
	var offset:Vector3=ball.position-actor.position;offset.y=0
	var pocket:Vector3=actor.body_facing*.28 if absf(aim.dot(actor.body_facing))<.5 else Vector3.ZERO
	return (offset-pocket).slide(aim).length()>.22

static func result(actor:Node3D,ball:Node3D,aim:Vector3,original:Vector3,horizon:float,lead:float)->Vector3:
	if not enabled(actor):return original
	var w:float=weight(actor,aim)
	if w<=0:return original
	var initial:Vector3=actor.velocity;initial.y=0
	var profile=actor.profile
	var sprint:float=actor.sprint_intent
	var maximum:float=lerpf(profile.jog_speed_mps,profile.sprint_speed_mps,sprint)
	maximum=lerpf(maximum,profile.shield_move_speed_mps,actor.shield_intent)
	var desired:Vector3=actor.foot.ordinary_scheduler.stable_direction(actor)*actor.move_intent.length()*maximum;desired.y=0
	var prediction:Dictionary=predict_motor(initial,desired,profile,sprint,horizon)
	var offset:Vector3=ball.position-actor.position;offset.y=0
	var low:bool=not actor.foot.ordinary_scheduler.high_gear(actor) or actor.close_control or actor.shielding
	var outgoing:Vector3=original
	if w>0: # Same reachable moving pocket for AI; human behavior is unchanged.
		# The same motor command predicts both residual travel and next contact.
		# Retain a modest reachable lead through turns, never stop the ball alone.
		var pocket:Vector3=actor.body_facing*.20 if absf(aim.dot(actor.body_facing))<.5 else Vector3.ZERO
		var next_lead:float=lerpf(.16,.30,clampf(initial.length()/4.5,0,1))
		var goal:Vector3=((prediction.displacement as Vector3)+pocket+aim*next_lead-offset)/maxf(horizon,.001)
		var loss:float=FootballBallForces.rolling_deceleration_mps2(goal.length(),ball.profile)
		if goal.length()>.001:goal+=goal.normalized()*.5*loss*horizon
		return original.lerp(goal.limit_length(6.7 if actor.sprinting else 3.0 if actor.close_control else 4.5),w)
	var mode:String="LOW_SIDE_REPAIR"
	if low:
		var pocket:Vector3=actor.body_facing*.28 if absf(aim.dot(actor.body_facing))<.5 else Vector3.ZERO
		var side_velocity:Vector3=((prediction.displacement as Vector3)+pocket-offset).slide(aim)/maxf(horizon,.001)
		# Inside cushions/centres more; outside keeps a gentler curved escape.
		var side_limit:float=.25 if actor.foot.surface=="OUTSIDE" else .50
		outgoing=(original+side_velocity.limit_length(side_limit)*w).limit_length(3.0 if actor.close_control or actor.shielding else 4.5)
	else:
		var future:Vector3=prediction.velocity
		var travel_direction:Vector3=future.normalized() if future.length()>.20 else (prediction.displacement as Vector3).normalized()
		if travel_direction.length_squared()<.0001:travel_direction=initial.normalized()
		var opposed:bool=angle(actor,aim)>deg_to_rad(90.0)
		var end_lead:float=minf(lead,.12) if opposed else lead
		var exit:Vector3=((prediction.displacement as Vector3)+travel_direction*end_lead-offset)/maxf(horizon,.001)
		var loss:float=FootballBallForces.rolling_deceleration_mps2(exit.length(),ball.profile)
		if exit.length()>.001:exit+=exit.normalized()*(.5*loss*horizon)
		exit=exit.limit_length(6.7 if actor.sprinting else 4.5)
		outgoing=original.lerp(exit,w*smoothstep(2.10,2.80,initial.length()))
		if opposed and future.dot(initial.normalized())>.20:
			var reverse:float=outgoing.dot(initial.normalized())
			if reverse<0:outgoing-=initial.normalized()*reverse
		mode="MOMENTUM_BRAKE" if opposed else "MOMENTUM_CUT"
	actor.foot.touch_plan["turn_prediction"]={"revision":"three_speed_turn036_01","mode":mode,"angle_deg":rad_to_deg(angle(actor,aim)),"weight":w,"initial_velocity":initial,"motor_desired":desired,"end_velocity":prediction.velocity,"displacement":prediction.displacement,"old_exit":original,"new_exit":outgoing,"collision_free_estimate":true}
	return outgoing

static func predict_motor(initial:Vector3,desired:Vector3,profile:Variant,sprint:float,horizon:float)->Dictionary:
	# Mirrors 036 horizontal motor integration. No collision or support promise.
	var count:int=maxi(1,int(ceil(horizon/maxf(profile.internal_step_seconds,.001))))
	var dt:float=horizon/float(count)
	var velocity:Vector3=initial
	var displacement:=Vector3.ZERO
	for i in count:
		velocity=preload("res://scripts/movement_inertia.gd").step(velocity,desired,profile,sprint,dt)
		displacement+=velocity*dt
	return {"velocity":velocity,"displacement":displacement}
