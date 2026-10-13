extends RefCounted
# One local human controller. No opponent speed writes or remote impulses.
var active := false
var direction := Vector3.ZERO
var motion := Vector3.ZERO
var pace := 0.0
var target := Vector3.ZERO
var clock := 0.0
var next_plan := 0.0
var next_poke := 0.0
var flank := 1.0

func step(game:Node,router:RefCounted,delta:float)->void:
	clock+=delta
	active=false
	motion=Vector3.ZERO
	var actor:Node3D=game.player
	var ball:Node3D=game.ball
	if not router.gameplay_allowed() or game.phase!=game.Phase.PLAY or not router.is_held("stand_intercept") or ball.held or ball.carrier==actor:
		next_plan=clock
		return
	if is_instance_valid(ball.carrier) and ball.carrier.team==actor.team:return
	if is_instance_valid(actor.interaction) and not actor.interaction.accepts_mobility_input():return
	if not router.snapshot().charge.is_empty() or actor.foot.kind in ["PASS","SHOT"] or actor.foot.has_receive_pass():return
	active=true
	var to_ball:Vector3=ball.position-actor.position;to_ball.y=0
	direction=to_ball.normalized() if to_ball.length()>.05 else actor.facing
	if clock>=next_plan:
		next_plan=clock+.075
		var relative:Vector3=ball.velocity-actor.velocity;relative.y=0
		var arrival:float=clampf(-to_ball.dot(relative)/maxf(relative.length_squared(),.1),.06,.32)
		target=ball.position+ball.velocity*arrival
		if is_instance_valid(ball.carrier):
			var owner:Node3D=ball.carrier
			var goal_side:Vector3=-game.services.rules.attack_direction(actor.team)
			target=preload("res://scripts/body_pressure.gd").target(actor.position,owner.position,owner.velocity,ball.position,goal_side)
		target.y=actor.position.y
		# Short torso-height sweep selects a local shoulder lane. World remains
		# authoritative if either corridor is blocked; no transforms are moved.
		var toward:Vector3=target-actor.position;toward.y=0
		if toward.length()>.75:
			var start:Vector3=actor.position+Vector3.UP*1.1
			var end:Vector3=start+toward.limit_length(1.5)
			var query:=PhysicsRayQueryParameters3D.create(start,end,3,[actor.get_rid()])
			var hit:Dictionary=actor.get_world_3d().direct_space_state.intersect_ray(query)
			if not hit.is_empty():
				var side:Vector3=Vector3(-toward.z,0,toward.x).normalized()
				if absf(to_ball.dot(side))>.12:flank=signf(to_ball.dot(side))
				target=actor.position+toward.normalized()*.55+side*flank*.65
	var offset:Vector3=target-actor.position;offset.y=0
	var closing:float=maxf(0.0,Vector3(ball.velocity.x,0,ball.velocity.z).dot(direction))
	pace=minf(5.6,maxf(.7,closing+offset.length()*3.0))
	motion=offset.normalized()*clampf(offset.length()/.25,0,1)
	if clock>=next_poke:
		next_poke=clock+.075
		if actor.tackle_cooldown<=0 and (actor.foot.idle() or actor.foot.kind=="RECEIVE" and not actor.foot.hit):
			var known:Dictionary={"position":ball.position,"velocity":ball.velocity,"age_s":0.0}
			game.attempt_tackle(actor,known) # One permission/pose read owns this request.
