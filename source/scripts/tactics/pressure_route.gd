extends RefCounted
# Route risk only. The existing director remains the sole intent owner.
const Motor=preload("res://scripts/movement_inertia.gd")
static var default_profile:Resource=preload("res://addons/football_physics/physics_profile.gd").new()

static func wants_cut(p:Dictionary,point:Vector3,opponents:Array[Dictionary])->bool:
	if not p.get("cut_ready",false):return false
	var direction:Vector3=(point-p.position).normalized()
	var facing:Vector3=p.facing.normalized()
	var turn:float=facing.dot(direction)
	if turn>=.94 or turn<=-.35:return false
	for enemy in opponents:
		var relative:Vector3=enemy.position-p.position;relative.y=0
		var projected:Vector3=relative+(enemy.get("velocity",Vector3.ZERO)-p.velocity)*.25;projected.y=0
		if relative.length()<3.6 and relative.normalized().dot(facing)>-.10 and (relative.length()<2.8 or projected.length()<1.6):return true
	return false

static func inspect(p:Dictionary,point:Vector3,opponents:Array[Dictionary],speed:float=5.0,cut:bool=false)->Dictionary:
	var start:Vector3=Vector3(p.position.x,0,p.position.z)
	var direction:Vector3=point-start;direction.y=0
	if direction.length_squared()<.000001:direction=p.facing
	direction=direction.normalized()
	var own_velocity:Vector3=p.get("velocity",Vector3.ZERO);own_velocity.y=0
	var profile:Resource=p.get("motor_profile",default_profile)
	var run:Vector3=own_velocity
	var displacement:=Vector3.ZERO
	var offset:Vector3=p.get("ball_offset",direction*.4);offset.y=0
	var heading:Vector3=p.get("carry_heading",p.facing)
	var free_ball:Vector3=offset
	var ball_velocity:Vector3=p.get("ball_velocity",own_velocity);ball_velocity.y=0
	var samples:Array[Dictionary]=[]
	# Ten motor steps per route, shared by all defenders. The old estimate
	# teleported velocity to 5m/s even during a committed 2.8m/s cut.
	for i in 10:
		var t:float=(i+1)*.08
		var pace:float=2.8 if cut and t<=.24 else speed
		if not cut:
			var turn_rate:float=lerpf(4.0,1.6,clampf(run.length()/5.0,0,1))
			var angle:float=heading.signed_angle_to(direction,Vector3.UP)
			heading=heading.rotated(Vector3.UP,clampf(angle,-turn_rate*.08,turn_rate*.08)).normalized()
		else:heading=direction
		run=Motor.step(run,heading*pace,profile,clampf((pace-3.2)/2.4,0,1),.08)
		displacement+=run*.08
		# Planar yaw remains defined at a 180-degree reversal; Vector3.slerp's
		# near-collinear cross-axis produced non-unit rotation axes in real play.
		var travel:Vector3=run.normalized() if run.length()>.2 else direction
		var lead:Vector3=travel.rotated(Vector3.UP,travel.signed_angle_to(direction,Vector3.UP)*.45)*.40
		var ball:Vector3=displacement+offset.lerp(lead,clampf(t/.24,0,1))
		if cut and t<=.40:
			# First actual touch is estimated at .08s. Preserve the same finite
			# 3.8m/s delta-v budget as TURN; the ball cannot instantly turn either.
			if i==1:
				var exit:Vector3=preload("res://scripts/dribble_turn_control.gd").ai_cut_velocity(run,free_ball-displacement,profile,0.0,direction,profile)
				ball_velocity+=(exit-ball_velocity).limit_length(3.8)
			var drag:float=FootballBallForces.rolling_deceleration_mps2(ball_velocity.length(),profile)
			ball_velocity=ball_velocity.move_toward(Vector3.ZERO,drag*.08)
			free_ball+=ball_velocity*.08
			ball=free_ball
		samples.append({"t":t,"body":displacement,"ball":ball})
	var clearance:float=20.0
	var immediate:float=20.0
	var closing:float=0.0
	var escape:float=0.0
	var contact_time:float=10.0
	var frontal:bool=false
	var trailing:bool=false
	for other in opponents:
		var relative:Vector3=Vector3(other.position.x,0,other.position.z)-start
		var velocity:Vector3=Vector3(other.velocity.x,0,other.velocity.z)
		var gap:float=relative.length()
		var approach:float=(Vector3(own_velocity.x,0,own_velocity.z)-velocity).dot(relative.normalized())
		var predicted_contact:float=maxf(0,gap-.85)/maxf(.05,approach)
		if predicted_contact<contact_time:
			contact_time=predicted_contact
			frontal=relative.normalized().dot(direction)>.15
			trailing=relative.normalized().dot(direction)<-.35
		if gap<4.0:closing=maxf(closing,approach)
		if gap>9.0:continue
		var enemy_pos:Vector3=relative
		var enemy_profile:Resource=other.get("motor_profile",default_profile)
		for sample in samples:
			var t:float=sample.t
			# Visible momentum persists through a reaction interval. Afterwards
			# budget a possible pursuit, including the defender's real braking.
			# No opponent input, future tactic or collision result is read here.
			if t>.24 and gap<6.0:
				var chase:Vector3=(sample.ball-enemy_pos).normalized()*minf(5.6,float(other.get("ability_speed",5.6)))
				velocity=Motor.step(velocity,chase,enemy_profile,1.0,.08)
			enemy_pos+=velocity*.08
			var body_gap:float=(enemy_pos-sample.body).length()
			var ball_gap:float=(enemy_pos-sample.ball).length()
			var separation:float=minf(body_gap,ball_gap+.15)
			clearance=minf(clearance,separation)
			if t<=.32:immediate=minf(immediate,separation)
		if gap<3.2:
			escape=maxf(escape,(relative+velocity*.6-direction*speed*.6).length()-gap)
	return {"clearance":clearance,"immediate":immediate,"closing":closing,"escape":escape,"contact_time":contact_time,"frontal":frontal,"trailing":trailing}
