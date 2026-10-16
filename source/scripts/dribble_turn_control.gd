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
	if w<=0:return original
	return (aim*maxf(original.dot(aim),maximum*.72)+correction.limit_length(.10)*2.0).limit_length(maximum)

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

static func result(actor:Node3D,ball:Node3D,aim:Vector3,original:Vector3,horizon:float,_lead:float)->Vector3:
	if not enabled(actor):return original
	var w:float=weight(actor,aim)
	if w<=0:return original
	var initial:Vector3=actor.velocity;initial.y=0
	var profile=actor.profile
	var sprint:float=actor.sprint_intent
	var maximum:float=actor.motor_speed_limit(sprint)
	maximum=lerpf(maximum,profile.shield_move_speed_mps,actor.shield_intent)
	var desired:Vector3=actor.foot.ordinary_scheduler.stable_direction(actor)*actor.move_intent.length()*maximum;desired.y=0
	var prediction:Dictionary=predict_motor(initial,desired,profile,sprint,horizon,actor if actor.is_human and actor.get("controller_v07_enabled")==true else null)
	var offset:Vector3=ball.position-actor.position;offset.y=0
	if w>0: # One reachable motor prediction for the next directional touch.
		# The same motor command predicts both residual travel and next contact.
		# Retain a modest reachable lead through turns, never stop the ball alone.
		var pocket:Vector3=actor.body_facing*.20 if absf(aim.dot(actor.body_facing))<.5 else Vector3.ZERO
		var next_lead:float=lerpf(.16,.30,clampf(initial.length()/4.5,0,1))
		var goal:Vector3=((prediction.displacement as Vector3)+pocket+aim*next_lead-offset)/maxf(horizon,.001)
		var loss:float=FootballBallForces.rolling_deceleration_mps2(goal.length(),ball.profile)
		if goal.length()>.001:goal+=goal.normalized()*.5*loss*horizon
		return original.lerp(goal.limit_length(6.7 if actor.sprinting else 3.0 if actor.close_control else 4.5),w)
	return original

static func predict_motor(initial:Vector3,desired:Vector3,profile:Variant,sprint:float,horizon:float,controller:Node=null)->Dictionary:
	# Mirrors 036 horizontal motor integration. No collision or support promise.
	var count:int=maxi(1,int(ceil(horizon/maxf(profile.internal_step_seconds,.001))))
	var dt:float=horizon/float(count)
	var velocity:Vector3=initial
	var displacement:=Vector3.ZERO
	for i in count:
		velocity=controller.predict_controller_velocity(velocity,desired,sprint,dt) if controller!=null else preload("res://scripts/movement_inertia.gd").step(velocity,desired,profile,sprint,dt)
		displacement+=velocity*dt
	return {"velocity":velocity,"displacement":displacement}

# Shared committed inside/outside cut, evaluated only at real shoe contact.
# The player is changing weight at <=3.2m/s here; adding 2.4m/s to its old
# forward velocity releases a ball the same motor cannot reach after turning.
static func ai_cut_result(actor:Node3D,ball:Node3D,aim:Vector3)->Vector3:
	var run:=Vector3(actor.velocity.x,0,actor.velocity.z)
	var offset:Vector3=ball.position-actor.position;offset.y=0
	return ai_cut_velocity(run,offset,actor.profile,actor.sprint_intent,aim,ball.profile,actor if actor.is_human and actor.get("controller_v07_enabled")==true else null)

static func ai_cut_velocity(run:Vector3,offset:Vector3,profile:Resource,sprint:float,aim:Vector3,ball_profile:Resource,controller:Node=null)->Vector3:
	aim=Vector3(aim.x,0,aim.z).normalized()
	var horizon:float=.32
	var forecast:Dictionary=predict_motor(run,aim*3.2,profile,sprint,horizon,controller)
	var travel:Vector3=forecast.velocity
	var lead_axis:Vector3=travel.normalized().rotated(Vector3.UP,travel.normalized().signed_angle_to(aim,Vector3.UP)*.45) if travel.length()>.2 else aim
	var desired:Vector3=(forecast.displacement+lead_axis*.40-offset)/horizon
	# Leave the ball free to roll; the existing finite impulse/reach checks apply.
	var loss:float=FootballBallForces.rolling_deceleration_mps2(desired.length(),ball_profile)
	if desired.length()>.01:desired+=desired.normalized()*.5*loss*horizon
	return desired.limit_length(4.2)
