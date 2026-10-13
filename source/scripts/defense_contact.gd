extends RefCounted
# Shared human/AI standing challenge: forecast intent, then actual swept contact.
# Never assigns possession, moves a root/ball or solves an extra skeleton.
static func plan(actor:Node3D,ball:Node3D,known:Dictionary)->Dictionary:
	if not known.get("position") is Vector3:return {}
	var seen:Vector3=known.position
	var roll:Vector3=known.get("velocity",Vector3.ZERO)
	var age:float=float(known.get("age_s",0))
	if not seen.is_finite() or not roll.is_finite() or age<0 or age>.35:return {}
	var current:Vector3=seen+roll*minf(age,.20)
	var offset:Vector3=current-actor.position;offset.y=0
	var relative:Vector3=roll-actor.velocity;relative.y=0
	var eta:float=clampf(-offset.dot(relative)/maxf(relative.length_squared(),.01),.025,.22)
	var center:Vector3=current+roll*eta
	var root:Vector3=actor.position+Vector3(actor.velocity.x,0,actor.velocity.z)*eta
	if Vector2(center.x-root.x,center.z-root.z).length()>ball.tuning.foot_reach+ball.radius+.06:return {}
	if center.y>.46 or center.y<0:return {}
	var choice:Dictionary=clear_foot(actor,ball,center)
	if choice.is_empty():return {}
	choice.merge({"tackle_center":center,"contact_eta_s":eta,"intercept":not is_instance_valid(ball.carrier),"observation_age_s":age})
	return choice

static func sample(action:RefCounted,ball:Node3D)->Dictionary:
	if not action.physical_contact_sample.is_empty():return action.physical_contact_sample
	# A World collision already settled this trajectory. Do not retrospectively
	# add a second action impulse to the preceding frame's ball sweep.
	if ball.last_lower_contact_frame>=Engine.get_physics_frames()-1:return {}
	var previous:Vector3=ball.previous_position
	var start:Vector3=action.previous_toe-previous
	var finish:Vector3=action.toe_world-ball.position
	var relative:Vector3=finish-start
	var fraction:float=clampf(-start.dot(relative)/maxf(relative.length_squared(),.000001),0,1)
	var gap:float=(start+relative*fraction).length()
	if gap>ball.radius+.075:return {}
	var center:Vector3=previous.lerp(ball.position,fraction)
	var shoe:Vector3=action.previous_toe.lerp(action.toe_world,fraction)
	var root:Vector3=action.actor.position
	if Vector2(center.x-root.x,center.z-root.z).length()>ball.tuning.tackle_reach+ball.radius+.06:return {}
	var normal:Vector3=center-shoe;normal.y=0
	if normal.length_squared()<.0001:normal=-Vector3(ball.velocity.x,0,ball.velocity.z)
	if normal.length_squared()<.0001:normal=action.direction
	return {"center":center,"point":shoe,"normal":normal.normalized(),"fraction":fraction,"gap":gap}

static func clear_foot(actor:Node3D,ball:Node3D,center:Vector3)->Dictionary:
	var best:Dictionary={}
	var distance:float=INF
	var game:Node=actor.foot.match_controller
	var facing:Vector3=actor.body_facing
	var right:Vector3=Vector3(-facing.z,0,facing.x)
	var offset:Vector3=center-actor.position;offset.y=0
	var lateral:float=offset.dot(right)
	for side in [-1,1]:
		# Do not sweep the opposite leg across the standing leg for a side ball.
		if lateral*side<-.14:continue
		var surface:String="OUTSIDE" if lateral*side>.24 else "INSIDE" if not is_instance_valid(ball.carrier) else "TOE"
		var start:Vector3=actor.avatar.get_foot_contact(side,surface).point
		var toward:Vector3=center-start
		var radial:Vector3=Vector3(toward.x,0,toward.z).normalized()
		var point:Vector3=center-radial*ball.radius
		var finish:Vector3=point-radial*.025
		if toward.length()>1.12:continue
		var query:=PhysicsRayQueryParameters3D.create(start,finish,3,[actor.get_rid()])
		query.hit_from_inside=true
		if not actor.get_world_3d().direct_space_state.intersect_ray(query).is_empty():continue
		var blocked:bool=false
		for other in game.players:
			if other==actor or not other.visible or other.position.distance_to(center)>1.5:continue
			var skeleton:Skeleton3D=other.avatar.skeleton
			for suffix in ["L","R"]:
				var foot:int=other.avatar.cached_bone_id("foot."+suffix)
				var shin:int=other.avatar.cached_bone_id("shin."+suffix)
				if foot<0 or shin<0:continue
				var a:Vector3=skeleton.to_global(skeleton.get_bone_global_pose(foot).origin)
				var b:Vector3=skeleton.to_global(skeleton.get_bone_global_pose(shin).origin)
				var pair:PackedVector3Array=Geometry3D.get_closest_points_between_segments(start,finish,a,b)
				if pair[0].distance_to(pair[1])<.10:blocked=true
		if not blocked and toward.length()<distance:
			var yaw:float=clampf(facing.signed_angle_to(radial,Vector3.UP),-.55,.55)
			best={"tackle_side":side,"tackle_surface":surface,"tackle_point":point,"tackle_foot_direction":facing.rotated(Vector3.UP,yaw),"tackle_travel_s":clampf(start.distance_to(point)/7.5,.025,.12)}
			distance=toward.length()
	return best
