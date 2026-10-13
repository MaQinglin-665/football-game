extends RefCounted
## Motion only. The controller remains responsible for action admission.
var request:Dictionary={}
var step:Dictionary={}
var episode:=0
var landings:=0
var conflicts:=0
var pelvis_x:=0.0
var blocked_reason:="NO_INTENT"

func prepare(avatar,dt:float,state:Dictionary,body_request:Dictionary)->void:
	request=body_request.duplicate(true)
	blocked_reason=""
	var velocity:Vector3=state.get("velocity",Vector3.ZERO)
	var speed:float=Vector2(velocity.x,velocity.z).length()
	var eligible:bool=bool(state.get("grounded",true)) and speed<=2.10 and bool(request.get("active",false))
	if not eligible:
		blocked_reason="INACTIVE_OR_OUTSIDE_LOW_SPEED"
		step.clear();pelvis_x=move_toward(pelvis_x,0.0,dt*.20);return
	var dominant:int=int(request.get("dominant_side",1))
	var side:String=avatar.side_suffix(-dominant)
	# Never silently change the controller's selected touch foot.
	if not avatar._action.is_empty() and int(avatar._action.get("side",dominant))!=dominant:
		blocked_reason="CONTROLLER_TOUCH_SIDE_CONFLICT"
		if dt>0:conflicts+=1
		step.clear();pelvis_x=move_toward(pelvis_x,0.0,dt*.20);return
	var sk:Skeleton3D=avatar.skeleton
	var root:Vector3=sk.global_position
	var completed:Dictionary=avatar._last_ankles.get(side,{})
	if completed.is_empty():
		blocked_reason="WAIT_COMPLETED_POSE";return
	var idle:bool=avatar._action.is_empty()
	if idle and not "--dribble-rhythm=A" in OS.get_cmdline_user_args() and step.get("phase","")=="LANDING" and float(step.elapsed)>float(step.load_s)+float(step.duration)+.10:
		# A failed solve is not an endless landing. Release the stale reservation;
		# common locomotion recovers actual plants before a fresh episode.
		step.clear();blocked_reason="REPLAN_UNREACHABLE_LANDING";return
	var stale_landing:bool=not step.is_empty() and step.get("phase","")=="LANDED" and (completed.point as Vector3).distance_to(step.goal)>=.012
	if not step.is_empty():step["stale_landing"]=stale_landing
	if stale_landing:step.ready_for_touch=false
	var new_step:bool=step.is_empty() or (step.get("phase","")=="LANDED" and idle and (stale_landing or (int(request.get("after_touch_episode",-1))>=int(step.get("episode",0)) and root.distance_to(step.root_at_landing)>.05)))
	if new_step and dt>0 and idle:
		var other:String=avatar.side_suffix(dominant)
		if not avatar._plants.has(other) or bool(avatar._plants[other].get("releasing",false)):
			blocked_reason="WAIT_OTHER_ACTUAL_PLANT";return
		for foot_side in [side,other]:
			var last:Dictionary=avatar._last_ankles.get(foot_side,{})
			if last.is_empty():
				blocked_reason="WAIT_COMPLETED_POSE";return
			var gap:float=(last.point as Vector3).y+avatar._minimum_offset(foot_side,last.rotation)-float(avatar._ground_y)
			if gap<-.002 or gap>.012:
				blocked_reason="WAIT_BOTH_SOLES_GROUNDED";return
		var forward:Vector3=state.get("forward",Vector3.FORWARD)
		forward.y=0;forward=forward.normalized()
		var right:=Vector3(-forward.z,0,forward.x)
		var origin:Vector3=completed.point
		var intended:Vector3=request.get("move_direction",velocity.normalized())
		intended.y=0;intended=intended.normalized()
		var rhythm:bool=not "--dribble-rhythm=A" in OS.get_cmdline_user_args()
		var fore_offset:float=clampf((origin-root).dot(forward),-.04,.04) if rhythm else (origin-root).dot(forward)
		var advance:float=.10+minf(speed*.20,.34) if rhythm else .10
		# Land under the predicted moving pelvis, not behind its old world position.
		var goal:Vector3=root+right*(.115*(-1.0 if side=="L" else 1.0))+forward*fore_offset+intended*advance
		goal=origin+(goal-origin).limit_length(.36 if rhythm else .26)
		var rotation:=Quaternion(Vector3.UP,float(avatar.visual.global_rotation.y))
		goal.y=float(avatar._ground_y)+.005-avatar._minimum_offset(side,rotation)
		if Vector2(goal.x-origin.x,goal.z-origin.z).length()<.06:
			blocked_reason="WAIT_LATERAL_TRAVEL";return
		episode+=1
		step={"phase":"LOAD","side":side,"touch_side":dominant,"surface":"INSIDE","episode":episode,"origin":origin,"origin_sole":avatar._last_contacts.get(side,origin),"goal":goal,"rotation":rotation,"elapsed":0.0,"load_s":.035 if not "--dribble-rhythm=A" in OS.get_cmdline_user_args() else .055,"duration":clampf(origin.distance_to(goal)/2.4,.11,.16) if not "--dribble-rhythm=A" in OS.get_cmdline_user_args() else .24,"actual":origin,"ready_for_touch":false,"solve_ok":false,"early_touch":false,"lifted":false}
	if step.is_empty():return
	if dt>0 and step.phase!="LANDED":step.elapsed=float(step.elapsed)+dt
	if step.phase!="LANDED":
		step.phase="LOAD" if float(step.elapsed)<float(step.load_s) else "SWING" if float(step.elapsed)<float(step.load_s)+float(step.duration) else "LANDING"
		if not idle and avatar._action.get("contact_confirmed",false):step.early_touch=true
	# Transfer over the opposite planted foot before liftoff, then toward landing.
	var target:float=(.025*dominant) if step.phase in ["LOAD","SWING"] else (-.025*dominant)
	if dt>0:pelvis_x=move_toward(pelvis_x,target,dt*.25)
	# A same-world-step refresh reprojects the completed world ankle; no time advance.
	if dt<=0:
		var old:Dictionary=avatar._last_ankles.get(side,{})
		if not old.is_empty():avatar._last_local_ankles[side]={"point":sk.to_local(old.point),"rotation":sk.global_basis.get_rotation_quaternion().inverse()*(old.rotation as Quaternion)}

func owns(side:String)->bool:
	return not step.is_empty() and side==String(step.side) and not bool(step.get("stale_landing",false))

func solve(avatar,side:String,forward:Vector3)->void:
	if not owns(side):return
	if step.phase=="LOAD":return
	if step.phase!="LANDED":avatar._plants.erase(side)
	var t:float=clampf((float(step.elapsed)-float(step.load_s))/float(step.duration),0,1)
	var point:Vector3=(step.origin as Vector3).lerp(step.goal,smoothstep(0,1,t))
	point.y+=.065*4.0*t*(1.0-t)
	var sk:Skeleton3D=avatar.skeleton
	var rotation:Quaternion=sk.global_basis.get_rotation_quaternion().inverse()*(step.rotation as Quaternion)
	step.solve_ok=avatar._solve_leg(side,sk.to_local(point),rotation,sk.global_basis.inverse()*forward)

func observe(avatar)->void:
	if step.is_empty():return
	var side:String=step.side
	var sk:Skeleton3D=avatar.skeleton
	var pose:Transform3D=sk.get_bone_global_pose(sk.find_bone("foot."+side))
	var point:Vector3=sk.to_global(pose.origin)
	var rotation:Quaternion=sk.global_basis.get_rotation_quaternion()*pose.basis.get_rotation_quaternion()
	var floor_gap:float=point.y+avatar._minimum_offset(side,rotation)-float(avatar._ground_y)
	step.actual=point;step.sole_floor_gap_m=floor_gap
	step.actual_sole=avatar.get_foot_contact(-1 if side=="L" else 1,"SOLE").point
	step.actual_sole_travel_m=(step.actual_sole as Vector3).distance_to(step.origin_sole)
	step.goal_error_m=point.distance_to(step.goal)
	if floor_gap>.025:step.lifted=true
	# Completion is measured AFTER the common speed bound, floor guard and body pass.
	if step.phase=="LANDING" and bool(step.solve_ok) and bool(step.lifted) and float(step.goal_error_m)<.012 and floor_gap>=-.002 and floor_gap<=.012:
		step.phase="LANDED";step.root_at_landing=sk.global_position;landings+=1
		avatar._plants[side]={"point":step.actual_sole,"rotation":rotation,"age":0.0,"yaw":float(avatar.visual.global_rotation.y),"releasing":false}
	if step.phase=="LANDED" and bool(step.solve_ok) and float(step.goal_error_m)<.012 and floor_gap>=-.002 and floor_gap<=.012:
		avatar._plants[side]={"point":step.actual_sole,"rotation":rotation,"age":0.0,"yaw":float(avatar.visual.global_rotation.y),"releasing":false}
	step.ready_for_touch=bool(step.solve_ok) and float(step.goal_error_m)<.012 and step.phase=="LANDED" and avatar._plants.has(side) and not bool(avatar._plants[side].get("releasing",false)) and floor_gap>=-.002 and floor_gap<=.012

func snapshot()->Dictionary:
	var result:=step.duplicate(true)
	if result.is_empty():result={"phase":"NONE","ready_for_touch":false}
	result.merge({"revision":"lateral_support_09","landings":landings,"conflicting_touch_frames":conflicts,"pelvis_x_m":pelvis_x,"blocked_reason":blocked_reason},true)
	return result
