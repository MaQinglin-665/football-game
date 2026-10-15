extends RefCounted
const Geometry:=preload("res://addons/football_keeper/keeper_contact.gd")
static func snapshot(actors:Array,ball:Node3D,dt:float)->Array:
	var rows:Array=[]
	if ball.held:return rows
	for actor in actors:
		if not is_instance_valid(actor) or not actor.visible:continue
		# Preserve the established owned-ball action/follow contact policy.
		# This addition covers incoming/loose balls, not a second dribble kick.
		if ball.velocity.length()<6.0 and (ball.carrier==actor or ball.last_contact_actor==actor and ball.touch_age<.18):continue
		var reach:float=1.2+(ball.velocity.length()+actor.velocity.length())*dt
		if actor.position.distance_squared_to(ball.position)>reach*reach:continue
		var proxy:Node=actor.get_node_or_null("LowerBallContacts")
		if proxy==null:continue
		for side in ["L","R"]:
			var body:Node3D=proxy.parts["boot."+side]
			# A fast runner crossing a slow/stationary ball is also a moving
			# collision. Ball world speed alone cannot admit relative sweeps.
			# Keep this local to nearby active boots; stationary pairs need no CCD.
			var relative:Vector3=ball.velocity-body.ball_contact_velocity(ball.position)
			if body.collision_layer!=0 and relative.length_squared()>.0001:
				rows.append({"body":body,"before":body.global_transform})
	return rows

static func settle(ball:Node3D,rows:Array,from:Vector3,collisions:int,dt:float)->void:
	if rows.is_empty() or ball.collision_count!=collisions or ball.last_lower_contact_frame==Engine.get_physics_frames():return
	var chosen:Dictionary={}
	var earliest:float=1.0
	for row in rows:
		var body:Node3D=row.body
		if body.collision_layer==0:continue
		var hit:Dictionary=Geometry.sweep_sphere_box(from,ball.position,ball.radius,row.before,body.global_transform,Vector3(.065,.105,.285))
		if bool(hit.get("hit",false)) and float(hit.fraction)<earliest:
			earliest=float(hit.fraction);chosen={"hit":hit,"body":body}
	if chosen.is_empty():return
	var body:Node3D=chosen.body
	var hit:Dictionary=chosen.hit
	var normal:Vector3=hit.normal
	var speed:Vector3=body.ball_contact_velocity(hit.point)
	if (ball.velocity-speed).dot(normal)>=-.05:return
	# Rewind only to the proven time of impact, never to a foot/ownership socket.
	ball.global_position=from.lerp(ball.global_position,earliest)+normal*.001
	if body.resolve_foot_ball_contact(ball,hit.point,normal,dt):return
	var response:Dictionary=FootballContactMath.sphere_response(ball.velocity,ball.spin_rads,speed,normal,body.physics_mass_kg(),ball.profile.body_restitution,ball.profile.body_friction_coefficient,ball.profile,ball.position.y<=ball.radius+.03)
	ball.velocity=response.velocity
	ball.spin_rads=response.spin
	body.receive_body_impulse_ns(-response.impulse_ns)
	ball.body_collision_count+=1
	ball.collision_count+=1
	ball.physical_contact.emit(body.actor,hit.point,response.impulse_ns)
