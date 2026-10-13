extends RefCounted
## Two confirmed footfalls, cached geometry only. Artistic trajectories do not
## change motor deceleration, ball impulse, camera, or skeleton refresh budget.
var active:=false
var kind:=""
var stage:="IDLE"
var variant:=0
var step_index:=0
var confirmed:=0
var pivot:=""
var swing:=""
var age:=0.0
var elapsed:=0.0
var duration:=.20
var lifted:=false
var landing_ready:=false
var sink:=0.0
var arm:=0.0
var _dt:=0.0
var _speed:=0.0
var _initial_speed:=0.0
var _last_speed:=0.0
var _cooldown:=0.0
var _velocity:=Vector3.ZERO
var _acceleration:=Vector3.ZERO
var _incoming:=Vector3.FORWARD
var _desired:=Vector3.FORWARD
var _previous_travel:=Vector3.FORWARD
var _previous_intent:=Vector3.ZERO
var _origin:=Vector3.ZERO
var _goal:=Vector3.ZERO
var _rotation:=Quaternion.IDENTITY
var _turn:=0.0
var _stop_requested:=false
var _events:Array=[]
var _reason:=""
var _contact_frozen:=false
var _contact_point:=Vector3.ZERO
var _contact_rotation:=Quaternion.IDENTITY

func prepare(avatar,dt:float,state:Dictionary,allowed:bool)->void:
	_dt=maxf(0,dt)
	_velocity=state.get("velocity",Vector3.ZERO);_velocity.y=0
	_acceleration=state.get("acceleration",Vector3.ZERO);_acceleration.y=0
	_speed=_velocity.length()
	var interaction:Dictionary=state.get("interaction",{})
	var owns:bool=not avatar._action.is_empty() or not avatar._lateral09.step.is_empty()
	var safe:bool=(allowed or _dribble_request>=0 and active) and not owns and bool(state.get("grounded",true)) and not bool(interaction.get("mobility_busy",false)) and not bool(interaction.get("airborne",false)) and float(interaction.get("crouch",0))<=0 and float(interaction.get("header_weight",0))<=0
	# Contact refresh may revoke feet immediately; it never advances time.
	if not safe:
		if active:_event("ABORT", "real_action_or_ineligible")
		active=false;stage="IDLE";sink=0;arm=0;_dribble_request=-1
		if dt>0:_last_speed=_speed;_cooldown=.12
		return
	if dt<=0:return
	_cooldown=maxf(0,_cooldown-dt)
	var forward:Vector3=state.get("forward",Vector3.FORWARD)
	forward.y=0
	if forward.length_squared()<.001:forward=Vector3.FORWARD
	forward=forward.normalized()
	var intent:Vector3=state.get("move_direction",_velocity)
	intent.y=0
	if intent.length_squared()>.0001:intent=intent.normalized()
	var travel:Vector3=_velocity.normalized() if _speed>.12 else _previous_travel
	# A new semantic direction owns a new episode. Never keep a START waiting
	# for its old forward heading after the player has selected a side/cut.
	if active and _dribble_request<0 and state.has("move_direction"):
		var changed:bool=intent.length_squared()>.01 and _desired.dot(intent)<cos(deg_to_rad(30)) and _previous_intent.dot(intent)<.94
		var stopped:bool=intent.length_squared()<.01 and _previous_intent.length_squared()>.01 and _speed>.55 and not _stop_requested
		if changed or stopped:
			_event("ABORT","superseded_by_motion_input")
			active=false;stage="IDLE";_cooldown=0
	if not active and _cooldown<=0:
		var requested:=""
		var incoming:Vector3=_previous_travel if _last_speed>.12 else forward
		var target:Vector3=intent if intent.length_squared()>.01 else travel
		var angle:float=incoming.signed_angle_to(target,Vector3.UP)
		var intent_changed:bool=_previous_intent.length_squared()>.01 and _previous_intent.dot(target)<.94
		if _speed>.55 and absf(angle)>deg_to_rad(30) and (intent_changed or absf(_previous_travel.signed_angle_to(travel,Vector3.UP))>deg_to_rad(30)):requested="CUT"
		elif _last_speed>.55 and (_acceleration.dot(incoming)<-2.0 or intent.length_squared()<.01):requested="BRAKE"
		# Explicit input owns starting. A collision/recovery velocity at rest
		# must not launch two authored steps and replace Idle with Walk.
		# Legacy callers without input still use their velocity as intent.
		elif _last_speed<.12 and (intent.length_squared()>.01 if state.has("move_direction") else (_speed>.08 or intent.length_squared()>.01)):requested="START"
		if not requested.is_empty():
			_dribble_request=-1
			active=true;kind=requested;stage="WAIT_SUPPORT";age=0;elapsed=0;confirmed=0;step_index=0
			lifted=false;landing_ready=false;_contact_frozen=false
			_incoming=incoming;_desired=target;_turn=angle;_initial_speed=maxf(_speed,_last_speed)
			_stop_requested=state.has("move_direction") and intent.length_squared()<.01
			variant=180 if absf(angle)>deg_to_rad(135) else 90 if absf(angle)>deg_to_rad(67.5) else 45
			pivot="L" if angle<0 else "R"
			if absf(angle)<deg_to_rad(15):pivot="L" if _grounded(avatar,"L") else "R"
			swing="R" if pivot=="L" else "L"
			_event("REQUEST", "await_actual_support")
	if active:
		age+=dt;elapsed+=dt
		if elapsed>1.6:
			_event("ABORT", "contact_or_motion_timeout");active=false;stage="IDLE";_cooldown=.25;_dribble_request=-1
		elif stage=="WAIT_SUPPORT" and _grounded(avatar,pivot):
			stage="LOAD";age=0;_event("PIVOT_LOADED", "actual_cached_plant")
		elif stage=="LOAD" and age>=.045 and _grounded(avatar,pivot):_launch(avatar)
		elif stage=="SWING" and age>=duration:
			stage="LANDING";age=0;_event("PATH_COMPLETE", "not_a_touchdown")
		elif stage=="CONTACT_LOAD" and age>=minf(.065,.18/maxf(_speed,.001)):
			if step_index==0:
				step_index=1;pivot=swing;swing="R" if pivot=="L" else "L"
				if _grounded(avatar,pivot):_launch(avatar)
				else:stage="LOAD";age=0
			else:stage="SETTLE";age=0
		elif stage=="SETTLE" and age>=(.08 if _stop_requested else 0.0):
			var stable:bool=_speed<.12 or travel.dot(_desired)>.75
			if kind=="BRAKE":stable=_speed<=_initial_speed+.15 and absf(_acceleration.dot(_incoming))<1.5
			if _stop_requested:stable=_speed<.35
			# Running has one loaded support, rather than a stationary double
			# stance. Both distinct footfalls remain mandatory in either case.
			var support:bool=_grounded(avatar,"L") and _grounded(avatar,"R") if _stop_requested else _grounded(avatar,swing)
			if confirmed==2 and stable and support:
				if _dribble_request>=0 and confirmed>=2:_dribble_completed=_dribble_request
				_event("COMPLETE", "two_actual_landings_and_stable_motion");active=false;stage="IDLE";_cooldown=.20
	var comfort:float=.35 if bool(state.get("motion039_first_person",false)) else 1.0
	sink=(.035 if kind=="START" else .055 if kind=="CUT" else .045+.02*confirmed)*comfort if active else 0.0
	arm=(.8 if stage in ["LOAD","SWING"] else .35) if active else 0.0
	_last_speed=_speed
	if _speed>.12:_previous_travel=travel
	_previous_intent=intent

func _grounded(avatar,side:String)->bool:
	var plant:Dictionary=avatar._plants.get(side,{})
	var foot:Dictionary=avatar._last_ankles.get(side,{})
	if plant.is_empty() or foot.is_empty() or bool(plant.get("releasing",false)):return false
	var gap:float=(foot.point as Vector3).y+avatar._minimum_offset(side,foot.rotation)-float(avatar._ground_y)
	return gap>=-.008 and gap<=.014

func _launch(avatar)->void:
	var foot:Dictionary=avatar._last_ankles.get(swing,{})
	if foot.is_empty():return
	_origin=foot.point;_rotation=foot.rotation
	duration=clampf(.24-_speed*.012,.15,.24)
	stage="SWING";age=0;lifted=false;landing_ready=false
	_contact_frozen=false
	_event("SWING_BEGIN", "loaded_opposite_foot")

func yaw_offset(forward:Vector3,fallback:float,first_person:bool)->float:
	if not active or kind!="CUT":return fallback
	var turn_fraction:float=0.0
	if stage not in ["WAIT_SUPPORT","LOAD"]:
		turn_fraction=(.5 if variant==180 else .7) if step_index==0 else 1.0
		turn_fraction*=smoothstep(0,.10,age) if stage=="SWING" else 1.0
	var direction:Vector3=_incoming.rotated(Vector3.UP,_turn*turn_fraction)
	var value:float=forward.signed_angle_to(direction,Vector3.UP)
	return clampf(value,-PI/3,PI/3) if first_person else value

func phase_hint(phase:float,fraction:float)->float:
	if not active or stage not in ["SWING","LANDING","CONTACT_LOAD"]:return phase
	# Contact load remains early stance. The handover resumes from this foot.
	var p:float=lerpf(fraction+.01,.99,clampf(age/duration,0,1)) if stage=="SWING" else .01
	return fposmod(p-(.5 if swing=="R" else 0),1.0)

func support_wanted(side:String,fallback:bool)->bool:
	if not active:return fallback
	if side==swing and stage in ["SWING","LANDING"]:return landing_ready if stage=="LANDING" else false
	return true

func goals(avatar,feet:Dictionary)->void:
	if not active:return
	var sk:Skeleton3D=avatar.skeleton
	var root:Vector3=sk.global_position
	# Feed the actual loaded ankle into the EXISTING body reach/sink pass.
	# Otherwise that pass checks an authored swing while support later tries
	# to solve a different world anchor, and releases it for lack of reach.
	for side in ["L","R"]:
		if side==swing and stage in ["SWING","LANDING"]:continue
		var plant:Dictionary=avatar._plants.get(side,{})
		var foot:Dictionary=avatar._last_ankles.get(side,{})
		if plant.is_empty() or foot.is_empty() or bool(plant.get("releasing",false)):continue
		var held:Transform3D=feet[side]
		held.origin=sk.to_local(foot.point)
		held.basis=Basis(sk.global_basis.get_rotation_quaternion().inverse()*(foot.rotation as Quaternion))
		feet[side]=held
	if stage not in ["SWING","LANDING","CONTACT_LOAD"]:return
	if _contact_frozen:
		# A floor-observed contact candidate stays world-fixed for the next
		# normal support pass. It is NOT a plant until final observe confirms it.
		_goal=_contact_point
		var contact:Transform3D=feet[swing]
		contact.origin=sk.to_local(_contact_point)
		contact.basis=Basis(sk.global_basis.get_rotation_quaternion().inverse()*_contact_rotation)
		feet[swing]=contact
		return
	var heading:Vector3=_incoming if kind=="BRAKE" else _desired
	if kind=="CUT" and variant==180 and step_index==0:heading=_incoming.rotated(Vector3.UP,_turn*.5)
	var right:=Vector3(-heading.z,0,heading.x)
	var lead:float=(.16 if step_index==0 else .045) if kind=="BRAKE" else (.13 if step_index==0 else .20)
	var u:float=clampf(age/duration,0,1) if stage=="SWING" else 1.0
	var target:Vector3=root+_velocity*(duration*(1-u))+right*(-.145 if swing=="L" else .145)+heading*lead
	var yaw:float=Vector3.FORWARD.signed_angle_to(heading,Vector3.UP)
	var flat:=Quaternion(Vector3.UP,yaw)
	# First brake step lands heel-first, then existing stance code rolls flat.
	var heel:float=.12*smoothstep(.55,1,u) if kind=="BRAKE" and step_index==0 and stage!="CONTACT_LOAD" else 0.0
	var rotation:Quaternion=_rotation.slerp(flat*Quaternion(Vector3.RIGHT,heel),smoothstep(0,1,u))
	target.y=float(avatar._ground_y)+.005-avatar._minimum_offset(swing,rotation)
	_goal=_origin.lerp(target,smoothstep(0,1,u));_goal.y+=sin(PI*u)*.06
	var offset:=Vector3(_goal.x-root.x,0,_goal.z-root.z).limit_length(.34)
	_goal.x=root.x+offset.x;_goal.z=root.z+offset.z
	var goal:Transform3D=feet[swing]
	goal.origin=sk.to_local(_goal)
	goal.basis=Basis(sk.global_basis.get_rotation_quaternion().inverse()*rotation)
	feet[swing]=goal

func observe(avatar)->void:
	if not active or _dt<=0 or stage not in ["SWING","LANDING"]:return
	var foot:Dictionary=avatar._last_ankles.get(swing,{})
	if foot.is_empty():return
	var gap:float=(foot.point as Vector3).y+avatar._minimum_offset(swing,foot.rotation)-float(avatar._ground_y)
	if gap>.018:lifted=true
	landing_ready=stage=="LANDING" and lifted and gap>=-.008 and gap<=.014 and (foot.point as Vector3).distance_to(_goal)<.04
	if landing_ready and not _contact_frozen:
		_contact_frozen=true;_contact_point=foot.point;_contact_rotation=foot.rotation
		_goal=_contact_point
	_accept_landing(swing,landing_ready and _grounded(avatar,swing),_speed)

func _accept_landing(side:String,valid:bool,current_speed:float)->void:
	if not active or stage!="LANDING" or not valid or side!=swing:return
	confirmed+=1;stage="CONTACT_LOAD";age=0;landing_ready=false
	_event("REAL_LANDING", "actual_plant_floor_and_target",_initial_speed-current_speed)

func _event(name:String,reason:String,speed_drop:float=0.0)->void:
	_reason=reason
	if _events.size()>=32:_events.pop_front()
	_events.append({"event":name,"kind":kind,"variant_degrees":variant,"step":step_index+1,"side":swing,"pivot":pivot,"stage":stage,"confirmed":confirmed,"reason":reason,"speed_drop_mps":speed_drop})

func take_events()->Array:
	var result:Array=_events;_events=[];return result

func debug()->Dictionary:
	return {"revision":"two_actual_steps_039_contact_fix","active":active,"kind":kind,"stage":stage,"variant_degrees":variant,"step":step_index+1,"confirmed_landings":confirmed,"pivot":pivot,"swing":swing,"lift_observed":lifted,"landing_ready":landing_ready,"contact_candidate_frozen":_contact_frozen,"reason":_reason,"elapsed_s":elapsed}

# Explicit ordinary-carry transaction, completed only by two observed landings.
var _dribble_serial:=0
var _dribble_request:=-1
var _dribble_completed:=-1

func request_dribble_turn(incoming:Vector3,desired:Vector3)->int:
	if active and _dribble_request>=0:return -1
	if active:_event("ABORT","superseded_by_braked_dribble")
	_dribble_serial+=1;_dribble_request=_dribble_serial
	active=true;kind="CUT";stage="WAIT_SUPPORT";age=0;elapsed=0;confirmed=0;step_index=0
	lifted=false;landing_ready=false;_contact_frozen=false
	_incoming=incoming;_desired=desired;_turn=incoming.signed_angle_to(desired,Vector3.UP)
	_initial_speed=_speed;_stop_requested=false
	variant=180 if absf(_turn)>deg_to_rad(135) else 90
	pivot="L" if _turn<0 else "R";swing="R" if pivot=="L" else "L"
	_event("REQUEST","dribble_brake_contact_confirmed")
	return _dribble_request

func dribble_status(request:int)->String:
	if request==_dribble_completed:return "COMPLETE"
	return "ACTIVE" if active and request==_dribble_request else "ABORT"

func cancel_dribble(request:int)->void:
	if request!=_dribble_request:return
	if active:_event("ABORT","dribble_authority_cancelled")
	active=false;stage="IDLE";sink=0;arm=0;_dribble_request=-1
