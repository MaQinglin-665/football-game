extends RefCounted
## R011: geometry/relative motion, never a second touch timer or a ball force.
const MIN_BODY_ADVANCE := .12
const MAX_BODY_ADVANCE := .26
const RELEASE_CLEARANCE := .035
var pending:Dictionary = {}
var last:Dictionary = {}
var edge_recovery:bool=false
var inside_step:Dictionary={}

func clear()->void:
	pending.clear()
	edge_recovery=false
	inside_step.clear()

func prepare_inside(actor:Node3D,ball:Node3D,aim:Vector3,side:int)->Dictionary:
	var offset:Vector3=ball.position-actor.position;offset.y=0
	if offset.length()>.65 or ball.position.y>ball.radius+.18:
		inside_step.clear();return {}
	if inside_step.is_empty():
		# The completed rolling follow is already a real weight-transfer step.
		# Reuse its displacement for a same-direction next touch, rather than
		# asking for another six centimetres beside every ball contact.
		var origin:Vector3=actor.position
		if bool(pending.get("ready",false)) and (pending.axis as Vector3).dot(aim)>.85:
			origin=pending.root
		inside_step={"root":origin,"axis":aim,"required":.06,"side":side}
	if (inside_step.axis as Vector3).dot(aim)<.75 or int(inside_step.side)!=side:
		inside_step.clear();return {}
	var advance:float=(actor.position-(inside_step.root as Vector3)).dot(inside_step.axis)
	var support:Dictionary=actor.avatar.get_control_support_snapshot().get("support_phase",{}).get(actor.avatar.side_suffix(-side),{})
	var loaded:bool=support.get("state","")=="PLANTED" and bool(support.get("sole_near_ground",false))
	# An unavailable plant must not become an endless body-shift lock. Let the
	# ordinary reachable-foot planner recover once the finite step is spent.
	if advance>.18 and not loaded:
		inside_step.clear();return {}
	inside_step["advance"]=advance
	inside_step["loaded"]=loaded
	inside_step["ready"]=advance>=float(inside_step.required)-.002 and loaded
	return inside_step

func contacted(actor:Node3D,ball:Node3D,incoming:Vector3,side:int)->void:
	if not actor.is_human and not actor.foot.shared_ordinary_control():return
	var run:=Vector3(actor.velocity.x,0,actor.velocity.z)
	var outgoing:=Vector3(ball.velocity.x,0,ball.velocity.z)
	incoming.y=0
	clear()
	if outgoing.length()<.5 or run.length()<1.0:return
	pending={"root":actor.position,"ball":ball.position,"axis":outgoing.normalized(),"side":side,"advance":clampf(run.length()*.06,MIN_BODY_ADVANCE,MAX_BODY_ADVANCE),"aim":actor.get_ball_direction(),"speed":run.length(),"ready":false}

static func evaluate(offset:Vector3,relative:Vector3,body_advance:float,ball_travel:float,required:float,released:bool,aligned:bool,supported:bool)->Dictionary:
	# Rescue is geometric: do not watch a reachable ball escape or overrun it.
	var future:Vector3=offset+relative*.12
	var rescue:bool=(offset.length()>.82 and future.length()>offset.length()+.025) or offset.length()<.27
	var followed:bool=body_advance>=required and ball_travel>=.06 and released and aligned and (supported or body_advance>=required+.12)
	return {"ready":rescue or followed,"reason":"follow_rescue" if rescue else "body_followed_roll" if followed else "follow_free_roll","body_advance_m":body_advance,"required_advance_m":required,"ball_travel_m":ball_travel,"shoe_released":released,"support_grounded":supported,"body_aligned":aligned}

func consider(actor:Node3D,ball:Node3D,aim:Vector3)->Dictionary:
	if pending.is_empty():return {}
	if ball.carrier!=actor or actor.stop_requested>0:
		clear();return {}
	if pending.get("ready",false):return last
	var axis:Vector3=pending.axis
	var offset:Vector3=ball.position-actor.position;offset.y=0
	var relative:Vector3=ball.velocity-actor.velocity;relative.y=0
	var run:=Vector3(actor.velocity.x,0,actor.velocity.z)
	var support:Dictionary=actor.avatar.get_control_support_snapshot()
	var phases:Dictionary=support.get("support_phase",{})
	var grounded:=false
	for phase in phases.values():
		if phase.get("state","")=="PLANTED" and bool(phase.get("sole_near_ground",false)):grounded=true
	var shoe:Dictionary=actor.avatar.get_foot_contact(int(pending.side),"SOLE")
	var released:bool=(shoe.point as Vector3).distance_to(ball.position)>ball.radius+RELEASE_CLEARANCE
	last=evaluate(offset,relative,(actor.position-(pending.root as Vector3)).dot(axis),ball.position.distance_to(pending.ball),float(pending.advance),released,run.length()<.6 or run.normalized().dot(axis)>.35,grounded)
	# Readiness permits the next shoe to prepare; it does not give movement
	# back to the newly requested direction before that shoe meets the ball.
	if last.ready:pending["ready"]=true
	return last

func retreat_approach(actor:Node3D,ball:Node3D,aim:Vector3)->Dictionary:
	# Reverse input selects the next sole touch, not an immediate retreat away
	# from an outgoing ball. This budget moves only the body through its motor.
	if not actor.is_human or ball.carrier!=actor or actor.stop_requested>0:return {}
	if actor.foot.has_buffer() and not queued_follow(actor):return {}
	if not actor.foot.idle() and actor.foot.kind not in ["CLOSE","TURN","SHIELD","PULL"]:return {}
	var roll:=Vector3(ball.velocity.x,0,ball.velocity.z)
	var offset:Vector3=ball.position-actor.position;offset.y=0
	if roll.length()<1.0 or aim.length()<.05:return {}
	var axis:=roll.normalized()
	if aim.normalized().dot(axis)>-.5 or aim.normalized().dot(actor.body_facing)>-.2:return {}
	if offset.length()>1.10 or offset.dot(axis)<.24 or ball.position.y>ball.radius+.18:return {}
	var eta:float=.12
	if actor.foot.kind=="PULL" and not actor.foot.hit:
		eta=clampf(actor.foot.windup-actor.foot.elapsed+.035,.05,.16)
	# Spend available reach on braking, rather than imposing the backwards
	# speed cap before the sole has actually slowed the ball.
	var along:float=maxf(0.0,roll.length()-(.68-offset.dot(axis))/eta)
	var lateral:Vector3=(offset.slide(axis)*3.0).limit_length(.8)
	return {"motion":axis*along+lateral}

func follow_motion(actor:Node3D,ball:Node3D,aim:Vector3,maximum:float)->Dictionary:
	if ball.carrier!=actor or actor.stop_requested>0:
		clear();return {}
	var gathering:bool=actor.is_human and actor.gather_after_sprint
	if actor.foot.has_buffer() and not queued_follow(actor):
		edge_recovery=false;inside_step.clear();return {}
	if not actor.foot.idle() and not actor.foot.planned_dribble() and actor.foot.kind!="PULL" and not (actor.foot.hit and actor.foot.touch_plan.has("cut_style")):
		edge_recovery=false;inside_step.clear();return {}
	var offset:Vector3=ball.position-actor.position;offset.y=0
	var roll:Vector3=ball.velocity;roll.y=0
	if not inside_step.is_empty() and not bool(inside_step.get("ready",false)):
		if offset.length()>.65 or ball.position.y>ball.radius+.18:
			inside_step.clear()
		else:
			var advance:float=(actor.position-(inside_step.root as Vector3)).dot(inside_step.axis)
			var remaining:float=maxf(0.0,float(inside_step.required)-advance)
			var step_speed:float=maxf(remaining*8.0,.45 if remaining>.001 else .25)
			return {"motion":(roll+(inside_step.axis as Vector3)*step_speed).limit_length(maximum)}
	# A slow ball at the side is not a completed directional touch. Reposition
	# the body before asking the leg to pull across; never move the ball here.
	var right:=Vector3(-actor.body_facing.z,0,actor.body_facing.x)
	if actor.is_human and pending.is_empty() and offset.length()<=1.10 and offset.length()>.55 and absf(offset.dot(right))>.45 and roll.length()<.8 and aim.dot(offset)<-.08 and ball.position.y<=ball.radius+.18:
		edge_recovery=true
	if edge_recovery:
		if offset.length()>1.15 or ball.position.y>ball.radius+.18:
			clear();return {}
		# Reposition around a view-facing stance pocket, rather than rotating
		# the entire body toward a lateral ball. Only the motor moves the root.
		var pocket:Vector3=actor.body_facing*.32+right*clampf(offset.dot(right),-.22,.22)
		var correction:Vector3=(offset-pocket)*4.0
		return {"motion":(roll+correction).limit_length(minf(maximum,1.8))}
	if pending.is_empty() and not gathering:return {}
	if offset.length()>1.15 or roll.length()<.35 or ball.position.y>ball.radius+.18:
		clear();return {}
	var axis:Vector3=roll.normalized()
	# The ball's current path owns the approach; input prepares the next touch.
	# Input/view select the NEXT touch. Neither steers this committed approach.
	var pocket:Vector3=actor.body_facing*.20 if gathering else axis*.38
	if actor.is_human and not gathering and axis.dot(actor.body_facing)<.5:
		# Sideways control keeps the ball ahead of the stance, with a short
		# lateral lead. The actual roll, not next-input aim, owns this step.
		pocket=actor.body_facing*.40+axis.slide(actor.body_facing)*.12
	var follow:Vector3=roll+(offset-pocket)*4.0
	var along:float=maxf(0.0,follow.dot(axis))
	var lateral:Vector3=((offset-pocket).slide(axis)*3.0).limit_length(.85)
	return {"motion":(axis*along+lateral).limit_length(maximum)}

# A queued next touch does not own movement yet. Keep the current real follow
# until it is geometrically complete; receiver reservations remain separate.
func queued_follow(actor:Node3D)->bool:
	return not pending.is_empty() and actor.foot.buffer.get("kind","") in ["CUT","NUDGE","KICK","STOP"] and not bool(actor.foot.buffer.get("one_touch_pass",false))
