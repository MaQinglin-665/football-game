extends RefCounted
static func settle(ball:Node3D,actor:Node3D,point:Vector3,normal:Vector3,outlet:Vector3,side:int)->Dictionary:
	var before:Vector3=ball.velocity
	var run:Vector3=Vector3(actor.velocity.x,0,actor.velocity.z)
	var n:Vector3=normal.normalized()
	if ball.grounded and Vector2(n.x,n.z).length()>.01:n=Vector3(n.x,0,n.z).normalized()
	var response:Dictionary=FootballContactMath.sphere_response(before,ball.spin_rads,run*.65,n,actor.physics_mass_kg(),.06,.5,ball.profile,ball.grounded)
	var relative:Vector3=before-run
	var quality:float=clampf(-relative.normalized().dot(n),0,1)
	var after:Vector3=response.velocity
	if relative.length()<=10.5 and before.y<1.0 and (quality>.15 or relative.length()<3.0):
		var wanted:Vector3=outlet
		# Avoid routing the first touch through the body. A side lane, when needed,
		# stays short; never replace every forward request with a sideways rebound.
		var offset:Vector3=ball.position-actor.position;offset.y=0
		var nearest:Vector3=Geometry3D.get_closest_point_to_segment(Vector3.ZERO,offset,offset+wanted*.24)
		if wanted.length()>.2 and nearest.length()<.20:
			var tangent:Vector3=Vector3(-offset.z,0,offset.x).normalized()
			if tangent.dot(wanted)<0:tangent=-tangent
			wanted=(tangent*.8+offset.normalized()*.2).normalized()*minf(wanted.length(),2.3)
		var budget:float=minf(11.0,(relative.length()*.90+2.0)*preload("res://scripts/player_abilities.gd").value(actor,"touch"))
		after=before+(wanted-before).limit_length(budget)
		if ball.grounded:after.y=0
	var impulse:Vector3=(after-before)*ball.mass_kg
	if not impulse.is_finite():return {"accepted":false}
	ball.velocity=after
	ball.spin_rads=response.spin
	if ball.grounded:ball.spin_rads=Vector3.UP*ball.spin_rads.y*.3+Vector3.UP.cross(Vector3(after.x,0,after.z))/ball.radius
	actor.receive_body_impulse_ns(-impulse)
	return {"accepted":true,"impulse_ns":impulse}

# Finite first-touch result, calculated only at the actual shoe contact.
static func lead_velocity(ball:Node3D,actor:Node3D,aim:Vector3)->Vector3:
	var run:=Vector3(actor.velocity.x,0,actor.velocity.z)
	var incoming:=Vector3(ball.velocity.x,0,ball.velocity.z)-run
	aim=Vector3(aim.x,0,aim.z).normalized()
	var turn:float=acos(clampf(run.normalized().dot(aim),-1,1)) if run.length()>.8 else 0.0
	var horizon:float=lerpf(.24,.32,clampf(turn/PI,0,1))
	var wanted_speed:float=minf(4.8,maxf(1.8,run.dot(aim)+.65))
	var predicted:Dictionary=preload("res://scripts/dribble_turn_control.gd").predict_motor(run,aim*wanted_speed,actor.profile,actor.sprint_intent,horizon)
	var lead:float=lerpf(.38,.56,smoothstep(1.0,4.5,run.length()))
	# Harder incoming balls and large cuts remain close enough for the next reachable step.
	lead*=1.0-.22*smoothstep(5.0,10.5,incoming.length())-.18*smoothstep(.8,2.5,turn)
	var pocket:Vector3=actor.position+predicted.displacement+aim*lead-ball.position;pocket.y=0
	var desired:Vector3=(pocket/horizon).limit_length(4.8)
	if desired.dot(aim)<.65:desired+=aim*(.65-desired.dot(aim))
	return run+(desired-run).limit_length(3.2)
