extends RefCounted
const TurnControl := preload("res://scripts/dribble_turn_control.gd")
## Finite interception policy. Input/tactics own pace; real contact owns ball.
## Estimates are game assistance, not a future IK/physical-balance certificate.
static func enabled(actor:Node3D)->bool:
	if actor.is_human: return not "--dribble-rhythm=A" in OS.get_cmdline_user_args()
	return actor.has_method("ai_ordinary_rhythm") and actor.ai_ordinary_rhythm()

static func retreating(actor:Node3D,aim:Vector3)->bool:
	var reference:Vector3=-actor.global_basis.z if actor.is_human and actor.get("controller_v07_enabled")==true else actor.body_facing
	return aim.dot(reference)<-.35

static func pace(actor:Node3D,ball:Node3D,aim:Vector3,maximum:float)->Vector3:
	var offset:Vector3=ball.position-actor.position;offset.y=0
	var rolling:Vector3=ball.velocity;rolling.y=0
	var lateral:bool=absf(aim.dot(actor.body_facing))<.5
	# Full requested speed is independent of ball deceleration. Ease only when
	# actually about to overrun the reachable ball, using a short closing horizon.
	var rear_margin:float=.15 if lateral else .28
	var closing_limit:float=maxf(.45,rolling.dot(aim)+(offset.dot(aim)+rear_margin)/.18)
	var speed:float=minf(maximum,closing_limit)
	var correction:Vector3=offset.slide(aim)
	if lateral:correction-=actor.body_facing*.28
	# Bounded body alignment only; no spring/anchor/force is applied to the ball.
	var original:Vector3=(aim*speed+correction.limit_length(.18)*2.0).limit_length(maximum)
	if not actor.is_human:
		# Follow the real rolling pocket when its lateral gap is growing. The
		# motor remains the only root mover; a shoe still has to reach the ball.
		var future:Vector3=offset+(rolling-actor.velocity)*.18
		if future.slide(aim).length()>.38 or offset.length()>.72:
			return (rolling+(offset-aim*.38)*4.0).limit_length(maximum)
	return TurnControl.motion(actor,ball,aim,maximum,original,correction)

static func target_velocity(actor:Node3D,ball:Node3D,aim:Vector3)->Vector3:
	var run:Vector3=actor.velocity;run.y=0
	var offset:Vector3=ball.position-actor.position;offset.y=0
	var cfg=ball.tuning
	var close:bool=actor.close_control or actor.shielding
	var horizon:float=.28 if close else cfg.running_touch_horizon if actor.sprinting else .34
	var requested:float=cfg.sprint_ball_speed if actor.sprinting else cfg.shield_speed if actor.shielding else cfg.close_speed if close else cfg.normal_ball_speed
	if not actor.is_human and actor.get("ai_touch_pace")!=null:requested=minf(requested,maxf(1.0,float(actor.ai_touch_pace)))
	var along:float=maxf(0.0,run.dot(aim))
	var acceleration:float=actor.profile.sprint_acceleration_mps2 if actor.sprinting else actor.profile.start_acceleration_mps2
	var next_speed:float=minf(requested,along+acceleration*horizon)
	var travel:float=(along+next_speed)*.5*horizon
	var sideways:bool=absf(aim.dot(actor.body_facing))<.5
	var lead:float=.10 if sideways else lerpf(.48,cfg.running_touch_lead,smoothstep(1.5,4.5,run.length())) if actor.sprinting else .32
	var coast_loss:float=FootballBallForces.rolling_deceleration_mps2(run.length(),ball.profile)
	var exit_speed:float=clampf((travel+lead-offset.dot(aim))/horizon+.5*coast_loss*horizon,.65,7.1 if actor.sprinting else 3.0 if close else 4.5)
	var exit:Vector3=aim*exit_speed
	exit=TurnControl.result(actor,ball,aim,exit,horizon,lead)
	if actor.is_human and actor.foot.touch_plan.get("follow_collect",false):
		# A single sole cushion follows the braking body's reachable next pocket.
		# Never alter velocity between contacts or pull toward a world anchor.
		exit=run.limit_length(2.1)-offset.normalized()*clampf(offset.length()-.30,0,.35)
	if not actor.is_human:
		# AI must budget the next touch against its actual motor, including
		# inertia during a turn, rather than launching along a requested heading.
		var maximum:float=lerpf(actor.profile.jog_speed_mps,actor.profile.sprint_speed_mps,actor.sprint_intent)
		var desired:Vector3=actor.move_intent*maximum;desired.y=0
		var prediction:Dictionary=TurnControl.predict_motor(run,desired,actor.profile,actor.sprint_intent,horizon)
		var travel_axis:Vector3=(prediction.velocity as Vector3).normalized() if (prediction.velocity as Vector3).length()>.2 else aim
		var modest_lead:float=lerpf(.22,.40,clampf(run.length()/5.0,0,1))
		var pocket:Vector3=actor.position+prediction.displacement+travel_axis*modest_lead
		# Clip the desired next-contact pocket, never the physical ball position.
		pocket.x=clampf(pocket.x,-actor.match_controller.field_half_width+.65,actor.match_controller.field_half_width-.65)
		pocket.z=clampf(pocket.z,-actor.match_controller.field_half_length+.65,actor.match_controller.field_half_length-.65)
		exit=(pocket-ball.position)/horizon;exit.y=0
		if exit.length()>.01:exit+=exit.normalized()*.5*FootballBallForces.rolling_deceleration_mps2(exit.length(),ball.profile)*horizon
		exit=exit.limit_length(6.7 if actor.sprinting else 3.0 if close else 4.5)
	if actor.foot.touch_plan.get("turn_stage","")=="BRAKE":
		# One bounded real contact removes roll before either body/ball turns out.
		var incoming:Vector3=actor.foot.ordinary_scheduler.turn_incoming
		# Match the finite ball brake to the body's next motor braking interval.
		# A .30m/s ball beside a still-5m/s person was not a reachable next touch.
		var next_body_speed:float=maxf(.30,run.dot(incoming)-actor.profile.brake_deceleration_mps2*actor.foot.interval)
		exit=incoming*clampf(Vector3(ball.velocity.x,0,ball.velocity.z).dot(incoming),0,next_body_speed)
	# A single finite strike reaches this outgoing velocity under the existing
	# 35ms force budget. Invert the receiver relaxation so it doesn't halve kicks.
	var response:float=.035
	var gain:float=1.0-exp(-response/maxf(ball.profile.receiver_relaxation_time_s,.001))
	var before:Vector3=ball.velocity;before.y=0
	actor.foot.touch_plan["rhythm_horizon_s"]=horizon
	actor.foot.touch_plan["rhythm_exit_goal"]=exit
	return before+(exit-before)/maxf(gain,.001)

static func needs_touch(actor:Node3D,ball:Node3D,aim:Vector3)->bool:
	var offset:Vector3=ball.position-actor.position;offset.y=0
	var relative:Vector3=ball.velocity-actor.velocity;relative.y=0
	var prediction:Vector3=offset+relative*.09
	if actor.is_human and actor.sprint_release_carry_remaining>0 and prediction.dot(aim)>.45 and relative.dot(aim)>.1:return true
	var sideways:bool=absf(aim.dot(actor.body_facing))<.5
	var intercept:float=.08 if sideways else .36 if actor.sprinting else .25
	return prediction.dot(aim)<intercept or prediction.slide(aim).length()>.52 or offset.length()>.95 or TurnControl.needs_low_repair(actor,ball,aim)

static func steering_enabled(actor:Node3D)->bool:
	return enabled(actor) and not "--dribble-steer=A" in OS.get_cmdline_user_args()

static func can_steer(actor:Node3D,requested:Vector3)->bool:
	if not steering_enabled(actor) or not actor.move_requested or actor.stop_requested>0:return false
	var foot=actor.foot
	if not foot.planned_dribble() or foot.hit or foot.has_buffer():return false
	if foot.phase not in [foot.Phase.PREPARE,foot.Phase.CONTACT]:return false
	if actor.match_controller.ball.carrier!=actor:return false
	var aim:Vector3=Vector3(requested.x,0,requested.z)
	if aim.length_squared()<.0001:return false
	# The cone remains centered on this action's ORIGINAL direction. Repeated
	# input changes cannot ratchet it around; the selected shoe/surface stays fixed.
	return foot.direction.dot(aim.normalized())>=.5 # At most 60 degrees.

static func may_chase(actor:Node3D,ball:Node3D,intended:Vector3)->bool:
	if not steering_enabled(actor) or ball.carrier!=actor or actor.stop_requested>0:return false
	var foot=actor.foot
	if foot.has_buffer() or (not foot.idle() and not foot.planned_dribble()):return false
	var aim:Vector3=Vector3(intended.x,0,intended.z)
	if aim.length_squared()<.0025:return false
	aim=aim.normalized()
	if aim.dot(actor.body_facing)<-.2:return false
	var offset:Vector3=ball.position-actor.position;offset.y=0
	# Chase only a reachable-possession ball ahead in the requested corridor.
	# Behind/sideways balls retain the released limit; all action caps still apply.
	return offset.length()>.80 and offset.length()<=control_reach(actor,ball) and offset.dot(aim)>.25 and offset.normalized().dot(aim)>.6 and offset.slide(aim).length()<.65
static func turn_enabled(actor:Node3D)->bool:
	return TurnControl.enabled(actor)

static func braking_turn(actor:Node3D,aim:Vector3)->bool:
	return TurnControl.braking(actor,aim)

static func turn_chase_brake(actor:Node3D,ball:Node3D,aim:Vector3,old_chase:bool)->float:
	return TurnControl.chase_brake(actor,ball,aim,old_chase)

static func control_reach(actor:Node3D,ball:Node3D)->float:
	var offset:Vector3=ball.position-actor.position;offset.y=0
	var run:Vector3=actor.velocity;run.y=0
	var aim:Vector3=actor.get_ball_direction()
	var recent:bool=ball.last_contact_actor==actor and ball.touch_age<.75
	if recent and run.length()>2.2 and actor.move_requested and offset.dot(aim)>.15 and offset.slide(aim).length()<.65:
		return ball.tuning.running_control_reach
	return 1.45
