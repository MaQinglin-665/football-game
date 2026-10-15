extends RefCounted
## R011: geometry/relative motion, never a second touch timer or a ball force.
const MIN_BODY_ADVANCE := .12
const MAX_BODY_ADVANCE := .26
const RELEASE_CLEARANCE := .035
var pending:Dictionary = {}
var last:Dictionary = {}

func clear()->void:
	pending.clear()

func contacted(actor:Node3D,ball:Node3D,incoming:Vector3,side:int)->void:
	if not actor.is_human:return
	var run:=Vector3(actor.velocity.x,0,actor.velocity.z)
	var outgoing:=Vector3(ball.velocity.x,0,ball.velocity.z)
	incoming.y=0
	if outgoing.length()<.5 or run.length()<1.0:return
	pending={"root":actor.position,"ball":ball.position,"axis":outgoing.normalized(),"side":side,"advance":clampf(run.length()*.06,MIN_BODY_ADVANCE,MAX_BODY_ADVANCE),"aim":actor.get_ball_direction()}

static func evaluate(offset:Vector3,relative:Vector3,body_advance:float,ball_travel:float,required:float,released:bool,aligned:bool,supported:bool)->Dictionary:
	# Rescue is geometric: do not watch a reachable ball escape or overrun it.
	var future:Vector3=offset+relative*.12
	var rescue:bool=(offset.length()>.82 and future.length()>offset.length()+.025) or offset.length()<.27
	var followed:bool=body_advance>=required and ball_travel>=.06 and released and aligned and (supported or body_advance>=required+.12)
	return {"ready":rescue or followed,"reason":"follow_rescue" if rescue else "body_followed_roll" if followed else "follow_free_roll","body_advance_m":body_advance,"required_advance_m":required,"ball_travel_m":ball_travel,"shoe_released":released,"support_grounded":supported,"body_aligned":aligned}

func consider(actor:Node3D,ball:Node3D,aim:Vector3)->Dictionary:
	if pending.is_empty():return {}
	if ball.carrier!=actor or not actor.move_requested or actor.stop_requested>0:
		clear();return {}
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
	if last.ready:clear()
	return last

func follow_motion(actor:Node3D,ball:Node3D,aim:Vector3,maximum:float)->Dictionary:
	if not actor.is_human or ball.carrier!=actor:return {}
	if pending.is_empty() and not actor.gather_after_sprint:return {}
	if actor.foot.has_buffer() or not actor.foot.idle() and not actor.foot.planned_dribble():return {}
	var offset:Vector3=ball.position-actor.position;offset.y=0
	var roll:Vector3=ball.velocity;roll.y=0
	if offset.length()>1.15 or roll.length()<.35:return {}
	var axis:Vector3=roll.normalized()
	# The ball's current path owns the approach; input prepares the next touch.
	# Small lateral weight shifts are immediate, opposition brakes immediately.
	var follow:Vector3=roll+(offset-axis*.38)*4.0
	var along:float=maxf(0.0,follow.dot(axis))
	if aim.dot(axis)<-.3 and not actor.gather_after_sprint:along=minf(along,maxf(0.0,actor.velocity.dot(axis)-1.2))
	var lateral:Vector3=(offset.slide(axis)*3.0+aim.slide(axis)*.65).limit_length(.85)
	return {"motion":(axis*along+lateral).limit_length(maximum)}
