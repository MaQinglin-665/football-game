extends RefCounted
## Cached actual ankles -> bounded procedural swing. Reuses body.apply's two
## existing solves; no skeleton queries, refresh, solve or host writes here.
var directional:=false
var mode:="FORWARD"
var enabled:=false
var travel_angle:=0.0
var direction_weight:=0.0
var plans:Dictionary={}
var _state:Dictionary={}
var _action:Dictionary={}
var _dt:=0.0
var _carry:=false
var _carry_style:=false
var _last_mode:="FORWARD"
var _last_sequence:=-1

func prepare(dt:float,state:Dictionary,action:Dictionary,free:bool,carry:bool)->void:
	_state=state;_action=action;_dt=maxf(0,dt);_carry=carry
	_carry_style=String(state.get("locomotion","")).to_lower()=="dribble" or String(state.get("control_tier","")).to_upper() in ["CLOSE","CRUISE","KNOCK_CHASE"]
	var velocity:Vector3=state.get("velocity",Vector3.ZERO)
	velocity.y=0
	var speed:float=velocity.length()
	var forward:Vector3=state.get("forward",Vector3.FORWARD)
	forward.y=0
	if forward.length_squared()<.00001:forward=Vector3.FORWARD
	forward=forward.normalized()
	travel_angle=forward.signed_angle_to(velocity/maxf(speed,.001),Vector3.UP) if speed>.08 else 0.0
	var along:float=velocity.dot(forward)/maxf(speed,.001)
	var across:float=velocity.dot(Vector3(-forward.z,0,forward.x))/maxf(speed,.001)
	direction_weight=maxf(smoothstep(.55,.80,absf(across)),smoothstep(.25,.65,-along))*smoothstep(.08,.35,speed)*(1.0-smoothstep(3.10,3.80,speed)) if free else 0.0
	directional=direction_weight>.000001
	mode="BACKPEDAL" if directional and along<-.25 else "STRAFE_R" if directional and across>0 else "STRAFE_L" if directional else "FORWARD"
	enabled=directional or carry
	var seq:int=int(action.get("sequence",-1))
	if dt>0 and (not enabled or (mode!=_last_mode or seq!=_last_sequence) and not state.get("ai_carry_continuity",false)):plans.clear()
	if dt>0:_last_mode=mode;_last_sequence=seq

func goals(avatar,feet:Dictionary,phase:float,fraction:float,rate:float)->void:
	if not enabled or rate<=.001:return
	var sk:Skeleton3D=avatar.skeleton
	var root:Vector3=sk.global_position
	var velocity:Vector3=_state.get("velocity",Vector3.ZERO)
	velocity.y=0
	var speed:float=velocity.length()
	var travel:Vector3=velocity/maxf(speed,.001)
	var forward:Vector3=_state.get("forward",Vector3.FORWARD)
	forward.y=0
	if forward.length_squared()<.00001:forward=Vector3.FORWARD
	forward=forward.normalized()
	var right:=Vector3(-forward.z,0,forward.x)
	var active:String="L" if int(_action.get("side",1))<=0 else "R"
	for side in ["L","R"]:
		# Real touch/recovery target always supersedes the swing waveform.
		if not _action.is_empty() and side==active:
			if _dt>0:plans.erase(side)
			continue
		var completed:Dictionary=avatar._last_ankles.get(side,{})
		if completed.is_empty():continue
		var p:float=fposmod(phase+(.5 if side=="R" else 0),1.0)
		var holding:bool=avatar._carry039.hold_support(side,_action,avatar._plants,avatar._last_contacts,float(avatar._ground_y)) if _carry else false
		var wanted:bool=p<fraction or holding
		var continuous:bool=bool(_state.get("ai_carry_continuity",false))
		if continuous and not holding and plans.has(side) and float(plans[side].get("elapsed",0))<float(plans[side].get("duration",0)):
			wanted=false
		var plant:Dictionary=avatar._plants.get(side,{})
		var goal:Transform3D=feet[side]
		var world_point:Vector3=completed.point
		if wanted:
			if _dt>0:plans.erase(side)
			if plant.is_empty() or bool(plant.get("releasing",false)):continue
			if Vector2(world_point.x-root.x,world_point.z-root.z).length()>(.31 if _carry_style else .36):continue
		else:
			if not plans.has(side):
				if _dt<=0:continue
				plans[side]={"origin":completed.point,"floor_height":(completed.point as Vector3).y-root.y,"start_phase":p,"elapsed":0.0,"duration":maxf(.12,(1.0-p)/rate)}
			var plan:Dictionary=plans[side]
			var u:float=clampf((p-fraction)/maxf(.001,1.0-fraction),0,1)
			var remaining:float=(1.0-p)/rate
			if continuous:
				plan.elapsed+=_dt
				u=clampf(float(plan.elapsed)/float(plan.duration),0,1)
				remaining=maxf(0,float(plan.duration)-float(plan.elapsed))
			var lead:float=clampf(speed/(2.0*rate)*.12,.045,.20)
			var endpoint:Vector3=root+velocity*remaining+right*(-.145 if side=="L" else .145)+travel*lead
			endpoint.y=root.y+float(plan.floor_height)
			world_point=(plan.origin as Vector3).lerp(endpoint,smoothstep(0,1,u))
			world_point.y+=sin(PI*u)*(.045 if _carry_style else .065)
			# Reach envelope is local to the moving pelvis, independent of the
			# ball. Do not warp a live world_target or create a fake anchor.
			var horizontal:=Vector3(world_point.x-root.x,0,world_point.z-root.z)
			horizontal=horizontal.limit_length(.31 if _carry_style else .36)
			world_point.x=root.x+horizontal.x;world_point.z=root.z+horizontal.z
		var weight:float=1.0 if _carry else direction_weight
		goal.origin=goal.origin.lerp(sk.to_local(world_point),weight)
		# Keep the completed real shoe rotation; support/floor code decides the
		# final heading and touchdown, rather than rotating a sole in mid-plant.
		var rotation:Quaternion=sk.global_basis.get_rotation_quaternion().inverse()*(completed.rotation as Quaternion)
		goal.basis=Basis(goal.basis.get_rotation_quaternion().slerp(rotation,weight))
		feet[side]=goal

func debug()->Dictionary:
	return {"revision":"directional_gait_039","mode":mode,"directional":directional,"direction_weight":direction_weight,"travel_angle_rad":travel_angle,"procedural_carry":_carry,"active_swing_plans":plans.size(),"forward_fallback_above_mps":3.80}
