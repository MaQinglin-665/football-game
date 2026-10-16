extends RefCounted
## CC0 phase-synchronous body loops plus authored acceleration/bank response.
## Runs before foot03 anchors/real target IK. No inputs, ball forces or camera.
const LOOPS:="res://addons/football_motion/donor_body_loops.json"
const BODY_BONES:=["hips","spine","chest","neck","head","clavicle.L","upper_arm.L","forearm.L","hand.L","clavicle.R","upper_arm.R","forearm.R","hand.R"]
var loops:Dictionary={}
var ids:Dictionary={}
var last_velocity:=Vector3.ZERO
var initialized:=false
var elapsed:=0.0
var speed:=0.0
var body_mix:=0.0
var lean:=0.0
var bank:=0.0
var drive:=0.0
var braking:=0.0
var contact_balance:=0.0
var tier:="FREE"
var body_source:="Walk_Loop"
var safety_drop:=0.0
var safety_reductions:=0
var wanted_steps:Dictionary={}
var pending_steps:Dictionary={}
var step_sequence:=0
var _control_origin_sequence:=-1
var _control_origin_low:=false
var _control_rolling:Dictionary={}
var _control_touch:Dictionary={}
var _control_offset:=Vector3.ZERO
var _control_info:Dictionary={}
var _control_restore:Dictionary={}
var _running_support:String=""
var _held_control_support:=""
# These scalar states belong to shared, grounded, FREE locomotion only.
# The released action branch, target IK and leg safety code remain in use.
var _free_eligible:=false
var _jog_blend:=0.0
var _sprint_blend:=0.0
var _free_lean:=0.0
var _last_free_phase:=0.0
var _support_supplied:=false
var _support_left:="UNSPECIFIED"
var _support_right:="UNSPECIFIED"
var _support_source:="UNSPECIFIED"
var _last_free_applied:=false
# FREE safety is an absolute offset from this sample's authored pelvis,
# never a new accumulated pelvis baseline. Original total safety cap: 5cm.
var _safety_sink044:=0.0
var _safety_strength044:=1.0
var _safety_frame044:=-1.0
var _sink_budget044:=0.0
var _strength_budget044:=1.0
var _safety_accepted044:=false
var _safety_attempts044:=0
var _sampled_hip_y044:=0.0

func bind(sk:Skeleton3D)->void:
	if not loops.is_empty():return
	loops=JSON.parse_string(FileAccess.get_file_as_string(LOOPS)).clips
	for name in BODY_BONES:ids[name]=sk.find_bone(name)
	for clip in loops:
		for row in loops[clip].frames:
			for name in row:
				var q:Array=row[name];row[name]=Quaternion(q[0],q[1],q[2],q[3]).normalized()

func update(delta:float,state:Dictionary,action:Dictionary)->void:
	var dt:=maxf(0,delta)
	if dt<=0:return
	elapsed+=dt
	var velocity:Vector3=state.get("velocity",Vector3.ZERO)
	velocity.y=0
	var forward:Vector3=state.get("forward",Vector3.FORWARD)
	forward.y=0
	if forward.length_squared()<.0001:forward=Vector3.FORWARD
	forward=forward.normalized()
	var right:=Vector3(-forward.z,0,forward.x)
	var acceleration:Vector3=state.get("acceleration",(velocity-last_velocity)/dt if initialized else Vector3.ZERO)
	acceleration=acceleration.limit_length(18.0)
	last_velocity=velocity;initialized=true;speed=velocity.length()
	tier=String(state.get("control_tier","CLOSE" if action.get("kind","") in ["CLOSE","SHIELD"] else "KNOCK_CHASE" if action.get("kind","")=="SPRINT" else "CRUISE" if String(state.get("locomotion",""))=="dribble" else "FREE")).to_upper()
	if tier in ["RUN","HOLD","HOLD_SHIFT"]:tier="CRUISE"
	elif tier in ["HEAVY_TOUCH","DOUBLE_SHIFT","KNOCK"]:tier="KNOCK_CHASE"
	if not tier in ["FREE","CLOSE","CRUISE","KNOCK_CHASE"]:tier="FREE"
	var mode:=String(state.get("locomotion","idle")).to_lower()
	var running:=mode in ["run","sprint"] or speed>3.0
	body_source="Sprint_Loop" if tier=="KNOCK_CHASE" and speed>5.5 else "Jog_Fwd_Loop" if running or tier in ["CRUISE","KNOCK_CHASE"] and speed>1.85 else "Walk_Loop"
	var response:=1.0-exp(-10.0*dt)
	var longitudinal:=clampf(acceleration.dot(forward)/9.0,-1,1)
	var lateral:=clampf(acceleration.dot(right)/9.0,-1,1)
	drive=lerpf(drive,longitudinal,response)
	braking=lerpf(braking,maxf(0,-longitudinal),response)
	# Whole pelvis/trunk lean: quiet walk, visible run, stronger actual start.
	var normal_lean:float=.030*clampf(speed/1.4,0,1)+.185*smoothstep(1.4,4.4,speed)
	if tier=="CLOSE":normal_lean=minf(normal_lean,.080)
	var lean_target:=-normal_lean-.115*maxf(0,longitudinal)+.065*maxf(0,-longitudinal)
	lean=lerpf(lean,clampf(lean_target,-.34,.06),response)
	bank=lerpf(bank,-lateral*(.040+.160*clampf(speed/4.4,0,1)),response)
	body_mix=lerpf(body_mix,smoothstep(.04,.35,speed),1.0-exp(-14.0*dt))
	_free_eligible=action.is_empty() and tier=="FREE" and bool(state.get("grounded",true)) and mode in ["idle","walk","jog","run","sprint","jockey","press","start","stop"]
	# Actual speed selects the same donor mixture for every actor.
	var blend_response:float=1.0-exp(-12.0*dt)
	var jog_target:float=smoothstep(1.4,2.6,speed)
	var sprint_target:float=smoothstep(4.4,6.4,speed)
	_jog_blend=lerpf(_jog_blend,jog_target,blend_response)
	_sprint_blend=lerpf(_sprint_blend,sprint_target,blend_response)
	if absf(_jog_blend-jog_target)<.000001:_jog_blend=jog_target
	if absf(_sprint_blend-sprint_target)<.000001:_sprint_blend=sprint_target
	var free_normal_lean:float=.030*clampf(speed/1.4,0,1)+.185*smoothstep(1.4,4.4,speed)
	var free_lean_target:float=-free_normal_lean-.115*maxf(0,longitudinal)+.065*maxf(0,-longitudinal)
	_free_lean=lerpf(_free_lean,clampf(free_lean_target,-.34,.06),response)
	# Optional current host snapshot; otherwise apply() reads prior actual plants.
	var support:Variant=state.get("support_phase",null)
	_support_supplied=support is Dictionary
	if _support_supplied:
		_support_source="supplied_support_phase"
		var left:Variant=(support as Dictionary).get("L",null)
		var right_support:Variant=(support as Dictionary).get("R",null)
		_support_left=String((left as Dictionary).get("state","UNSPECIFIED")) if left is Dictionary else "UNSPECIFIED"
		_support_right=String((right_support as Dictionary).get("state","UNSPECIFIED")) if right_support is Dictionary else "UNSPECIFIED"
	var nt:=float(action.get("normalized_time",0))
	var pulse:=sin(PI*clampf(nt,0,1))
	var strength:=.085 if tier=="KNOCK_CHASE" else .018 if tier=="CLOSE" else .030
	if String(action.get("surface",""))=="SOLE":strength=.075
	# Contact envelope and side remain owned by the real action. Low control
	# stays byte-for-byte numerically identical below the released 2.10 limit.
	if String(action.get("kind","")).to_upper() in ["CARRY","CLOSE","TURN","SPRINT"] and String(action.get("surface","")).to_upper() in ["INSIDE","OUTSIDE","INSTEP"]:
		var contact_mix039:float=smoothstep(2.10,3.10,speed)*(.30 if bool(state.get("motion039_first_person",false)) else 1.0)
		strength=lerpf(strength,maxf(strength,.090),contact_mix039)
	contact_balance=pulse*float(action.get("side",1))*strength if not action.is_empty() else 0.0

func _sample_clip(source:String,phase:float)->Dictionary:
	var frames:Array=loops[source].frames
	var value:=fposmod(phase,1.0)*frames.size()
	var index:=int(floor(value));var weight:=value-index
	var a:Dictionary=frames[index%frames.size()];var b:Dictionary=frames[(index+1)%frames.size()]
	var result:Dictionary={}
	for name in a:result[name]=(a[name] as Quaternion).slerp(b[name],weight)
	return result

func sample(phase:float,free_transition:bool=false)->Dictionary:
	if not free_transition:return _sample_clip(body_source,phase)
	# Steady endpoints still use one source and one output dictionary.
	if _sprint_blend==1.0:return _sample_clip("Sprint_Loop",phase)
	if _jog_blend==0.0 and _sprint_blend==0.0:return _sample_clip("Walk_Loop",phase)
	if _jog_blend==1.0 and _sprint_blend==0.0:return _sample_clip("Jog_Fwd_Loop",phase)
	var walk_frames:Array=loops.Walk_Loop.frames
	var jog_frames:Array=loops.Jog_Fwd_Loop.frames
	var sprint_frames:Array=loops.Sprint_Loop.frames
	var p:float=fposmod(phase,1.0)
	var w:float=p*walk_frames.size();var j:float=p*jog_frames.size();var s:float=p*sprint_frames.size()
	var wi:int=int(floor(w));var ji:int=int(floor(j));var si:int=int(floor(s))
	var wa:Dictionary=walk_frames[wi%walk_frames.size()];var wb:Dictionary=walk_frames[(wi+1)%walk_frames.size()]
	var ja:Dictionary=jog_frames[ji%jog_frames.size()];var jb:Dictionary=jog_frames[(ji+1)%jog_frames.size()]
	var sa:Dictionary=sprint_frames[si%sprint_frames.size()];var sb:Dictionary=sprint_frames[(si+1)%sprint_frames.size()]
	var result:Dictionary={}
	for name in BODY_BONES:
		var q:Quaternion=(wa[name] as Quaternion).slerp(wb[name],w-wi)
		if _jog_blend>0:
			var jog_q:Quaternion=(ja[name] as Quaternion).slerp(jb[name],j-ji)
			q=q.slerp(jog_q,_jog_blend)
		if _sprint_blend>0:
			var sprint_q:Quaternion=(sa[name] as Quaternion).slerp(sb[name],s-si)
			q=q.slerp(sprint_q,_sprint_blend)
		result[name]=q
	return result

func apply(avatar,clip:String,phase:float)->void:
	var sk:Skeleton3D=avatar.skeleton
	bind(sk)
	if not clip in ["Idle","Walk","Run","Dribble","DribbleJog","SolePull_L","SolePull_R","SoleStop_L","SoleStop_R"]:return
	var feet:Dictionary={}
	for side in ["L","R"]:feet[side]=sk.get_bone_global_pose(avatar.cached_bone_id("foot."+side))
	# Rewrite only goals already consumed by the existing two leg solves.
	# Touch target IK remains later and authoritative. No new solve/refresh.
	var trajectory039=avatar._directional039
	if trajectory039.enabled:
		var fraction039:float=float(avatar._stance_fraction039)
		if fraction039<=0:fraction039=float(avatar._profiles.get(clip,{}).get("stance_fraction",.58))
		trajectory039.goals(avatar,feet,phase,fraction039,float(avatar._cadence))
	avatar._steps039.goals(avatar,feet)
	var initial:Dictionary={}
	for name in BODY_BONES:
		if int(ids[name])>=0:initial[name]=sk.get_bone_pose_rotation(ids[name])
	var moving:=clip!="Idle" and not clip.begins_with("Sole")
	# Recheck current action/tier here: a zero-delta contact refresh must
	# immediately use the released branch, despite update(0) not advancing state.
	var current_tier:String=String(avatar._motion_state.get("control_tier","")).to_upper()
	var free_transition:bool=_free_eligible and bool(avatar._free_gait_active) and current_tier=="FREE" and avatar._action.is_empty() and clip in ["Idle","Walk","Run"]
	_last_free_applied=free_transition
	if not _support_supplied:
		var plants:Dictionary=avatar._plants
		_support_source="prior_model_plants_before_foot_ik"
		_support_left="RELEASING" if plants.has("L") and bool(plants.L.get("releasing",false)) else "PLANTED" if plants.has("L") else "SWING"
		_support_right="RELEASING" if plants.has("R") and bool(plants.R.get("releasing",false)) else "PLANTED" if plants.has("R") else "SWING"
	var sample_phase:float=phase
	if free_transition:
		if clip=="Idle":sample_phase=_last_free_phase
		elif float(avatar._pose_delta)>0:_last_free_phase=phase
	var carry_transition:bool=current_tier in ["CLOSE","CRUISE","KNOCK_CHASE"] and String(avatar._action.get("kind","")) in ["","CARRY","CLOSE","TURN","SHIELD","SPRINT"]
	var qs:Dictionary=sample(sample_phase,free_transition or carry_transition)
	# Idle keeps a frozen last gait phase while residual body_mix decays.
	var mix:float=body_mix if moving or free_transition else 0.0
	var arm_weight:float=lerpf(.86,1.0,_jog_blend) if free_transition or carry_transition else .64 if tier=="CLOSE" else .86 if body_source=="Walk_Loop" else 1.0
	var applied_lean:float=_free_lean if free_transition else lean
	var intent039=avatar._motion039
	var motion039:bool=free_transition and bool(intent039.eligible)
	var applied_bank:float=bank
	var counter_yaw039:float=0.0
	var arm_load039:float=0.0
	var cut_balance039:=false
	if motion039:
		var normal039:float=.030*clampf(speed/1.4,0,1)+.185*smoothstep(1.4,4.4,speed)
		applied_lean=clampf(-normal039+float(intent039.lean),-.34,.18)
		applied_bank=float(intent039.bank)
		if trajectory039.directional:
			var turn039:float=float(trajectory039.travel_angle)-float(avatar._motion_state.get("motion039_yaw_offset",0))
			var pitch039:float=applied_lean
			applied_lean=clampf(pitch039*cos(turn039)+applied_bank*sin(turn039),-.34,.18)
			applied_bank=clampf(applied_bank*cos(turn039)-pitch039*sin(turn039),-.25,.25)
		counter_yaw039=float(avatar._motion_state.get("motion039_counter_yaw",0))
		arm_load039=float(intent039.arm)
		cut_balance039=String(intent039.state_name)=="CUT"
	var hip_id:int=ids.hips
	var initial_hip:=sk.get_bone_pose_position(hip_id)
	var translation:=Vector3(-.045*bank,-.014*maxf(0,drive)-.035*braking,-.030*clampf(speed/4.4,0,1)-.050*maxf(0,drive)+.030*braking)
	if not moving:translation=Vector3(0,-.015*braking,0)
	if motion039:
		translation=Vector3(-.045*applied_bank,-float(intent039.sink),-.030*clampf(speed/4.4,0,1))
		if trajectory039.directional:
			var travel_shift039:Vector3=Vector3(0,0,translation.z).rotated(Vector3.UP,float(trajectory039.travel_angle)-float(avatar._motion_state.get("motion039_yaw_offset",0)))
			translation.x+=travel_shift039.x;translation.z=travel_shift039.z
	var safety_strength:=1.0
	if avatar._steps039.active:
		translation.y=minf(translation.y,-float(avatar._steps039.sink))
		arm_load039=maxf(arm_load039,float(avatar._steps039.arm))
	_prepare_safety044(free_transition,float(avatar._pose_delta))
	if free_transition:safety_strength=_strength_budget044
	_safety_accepted044=false;_safety_attempts044=0;safety_drop=0.0
	_sampled_hip_y044=initial_hip.y
	var last_strength044:float=safety_strength
	for attempt in 6:
		_safety_attempts044=attempt+1;last_strength044=safety_strength
		for name in BODY_BONES:
			var id:int=ids[name]
			if id<0:continue
			var weight:=mix*(arm_weight if name.begins_with("upper_arm") or name.begins_with("forearm") or name.begins_with("hand") else 1.0)
			var q:Quaternion=(initial[name] as Quaternion).slerp(qs.get(name,Quaternion.IDENTITY),weight)
			if name=="hips":q=Quaternion.from_euler(Vector3(applied_lean,contact_balance*.25,applied_bank)*safety_strength)*q
			elif name=="neck":q=Quaternion.from_euler(Vector3(-applied_lean*.78,counter_yaw039*.40,-applied_bank*.70)*safety_strength)*q
			elif name=="chest":q=Quaternion(Vector3.UP,-contact_balance+counter_yaw039*.60*safety_strength)*q
			elif name.begins_with("upper_arm"):
				var side_sign:=1.0 if name.ends_with("L") else -1.0
				var outside039:float=1.0 if not cut_balance039 or applied_bank*side_sign<0 else .35
				q=Quaternion(Vector3.FORWARD,side_sign*(absf(applied_bank)*.20+absf(contact_balance)*.20+.10*arm_load039*outside039*safety_strength))*q
			sk.set_bone_pose_rotation(id,q)
		var trial_hip044:Vector3=initial_hip+translation*safety_strength
		if free_transition:
			# Ordinary sink keeps its meaning when rotational safety halves.
			# Scaling it back toward zero used to raise the whole trunk abruptly.
			trial_hip044.y=initial_hip.y+translation.y-_sink_budget044
		sk.set_bone_pose_position(hip_id,trial_hip044)
		var drop:=0.0
		for side in ["L","R"]:
			var hip:=sk.get_bone_global_pose(avatar.cached_bone_id("thigh."+side)).origin
			var ankle:Vector3=(feet[side] as Transform3D).origin
			var maximum:=sk.get_bone_rest(avatar.cached_bone_id("shin."+side)).origin.length()+sk.get_bone_rest(avatar.cached_bone_id("foot."+side)).origin.length()-.004
			var horizontal:=Vector2(hip.x-ankle.x,hip.z-ankle.z).length()
			var allowed:=sqrt(maxf(0,maximum*maximum-horizontal*horizontal))
			drop=minf(drop,ankle.y+allowed-hip.y)
		var required_sink044:float=_sink_budget044+maxf(0,-drop)
		if drop>=-.050 and (not free_transition or required_sink044<=.050):
			_safety_accepted044=true
			safety_drop=maxf(0,-drop)
			sk.set_bone_pose_position(hip_id,sk.get_bone_pose_position(hip_id)+Vector3(0,minf(0,drop),0))
			if free_transition:_commit_safety044(required_sink044,safety_strength)
			break
		safety_strength*=.5;safety_reductions+=1
	if free_transition and not _safety_accepted044:
		# Keep the actual bounded trial, not an accumulated low hip. Failure
		# stays visible, and existing leg/support checks reject invalid anchors.
		_commit_safety044(_sink_budget044,last_strength044)
	for side in ["L","R"]:
		var goal:Transform3D=feet[side]
		avatar._solve_leg(side,goal.origin,goal.basis.get_rotation_quaternion(),Vector3.FORWARD)

func _prepare_safety044(free:bool,dt:float)->void:
	if not free:
		_safety_sink044=0;_sink_budget044=0
		_safety_strength044=1;_strength_budget044=1;_safety_frame044=elapsed
	elif _safety_frame044!=elapsed:
		var step044:float=clampf(dt,0,.05)
		_sink_budget044=maxf(0,_safety_sink044-.45*step044)
		_strength_budget044=minf(1,_safety_strength044+2.0*step044)
		_safety_frame044=elapsed

func _commit_safety044(absolute_sink:float,strength:float)->void:
	_safety_sink044=clampf(absolute_sink,0,.050)
	_safety_strength044=clampf(strength,0,1)
	# Further samples in this update cannot spend another recovery budget.
	_sink_budget044=maxf(_sink_budget044,_safety_sink044)
	_strength_budget044=minf(_strength_budget044,_safety_strength044)

func ground_events(avatar,delta:float,state:Dictionary)->Array:
	var events:Array=[]
	if delta<=0:return events
	if not bool(state.get("grounded",true)):
		wanted_steps.clear();pending_steps.clear();return events
	var debug:Dictionary=avatar.get_motion_debug()
	for side in [-1,1]:
		var suffix:String=avatar.side_suffix(side)
		var planted:bool=debug.plants.has(suffix) and not bool(debug.plants[suffix].get("releasing",false))
		if planted and not bool(wanted_steps.get(suffix,false)) and speed>.20:pending_steps[suffix]=true
		if not planted:pending_steps.erase(suffix)
		wanted_steps[suffix]=planted
		if not pending_steps.has(suffix):continue
		var pose:Transform3D=avatar.skeleton.get_bone_global_pose(avatar.skeleton.find_bone("foot."+suffix))
		var world_rotation:Quaternion=avatar.skeleton.global_basis.get_rotation_quaternion()*pose.basis.get_rotation_quaternion()
		var floor_y:float=avatar.skeleton.to_global(pose.origin).y+avatar._minimum_offset(suffix,world_rotation)
		if floor_y-avatar._ground_y>.012:continue
		pending_steps.erase(suffix);step_sequence+=1
		var contact:Dictionary=avatar.get_foot_contact(side,"SOLE")
		events.append({"kind":"ground_step","sequence":step_sequence,"side":side,"point":contact.point,"normal":Vector3.UP,"speed":speed,"tier":tier})
	return events

func debug()->Dictionary:
	var result:Dictionary={"tier":tier,"body_source":body_source,"body_mix":body_mix,"lean_radians":lean,"bank_radians":bank,"acceleration_drive":drive,"braking":braking,"safety_drop":safety_drop,"safety_reductions":safety_reductions,"step_sequence":step_sequence,"revision":"shared_free_motion_044_absolute_safety","free_transition_applied":_last_free_applied,"jog_blend":_jog_blend,"sprint_blend":_sprint_blend,"free_lean_radians":_free_lean,"support_left":_support_left,"support_right":_support_right,"support_source":_support_source,"control_phase":_control_info.duplicate(true)}
	result["safety044"]={"accepted":_safety_accepted044,"attempts":_safety_attempts044,"absolute_sink_m":_safety_sink044,"total_sink_cap_m":.050,"rotation_strength":_safety_strength044,"sampled_hip_y":_sampled_hip_y044,"free":_last_free_applied}
	return result

# Appended to BodyMotion by build_candidate.py. This file is a source fragment.
func restore_control_phase(avatar)->void:
	# The common gait blend must see the original completed pose, otherwise a
	# clip transition would add this model-only transfer a second time.
	if _control_restore.is_empty():return
	var sk:Skeleton3D=avatar.skeleton
	sk.set_bone_pose_position(int(_control_restore.hip_id),_control_restore.hip_position)
	for id in _control_restore.rotations:sk.set_bone_pose_rotation(int(id),_control_restore.rotations[id])
	_control_restore.clear()

func prepare_control_context(avatar,state:Dictionary,rolling:Dictionary)->void:
	_control_rolling=rolling
	var seq:int=int(avatar._action.get("sequence",-1))
	if seq==_control_origin_sequence:return
	_control_origin_sequence=seq
	var initial:Vector3=rolling.get("begin_velocity",state.get("velocity",Vector3.ZERO))
	# Existing Dribble->DribbleJog entry speed, not a prescribed human cadence.
	_control_origin_low=seq>=0 and Vector2(initial.x,initial.z).length()<=2.10

func _ordinary_low_control(avatar,clip:String)->bool:
	return _control_origin_low and bool(avatar._grounded) and clip in ["Idle","Dribble"] and String(avatar._action.get("kind","")).to_upper() in ["CLOSE","TURN"] and String(avatar._action.get("surface","")).to_upper() in ["INSIDE","OUTSIDE"] and avatar._action.get("world_target") is Vector3

func note_control_touch(event:Dictionary,rolling:Dictionary)->void:
	if not bool(event.get("success",false)) or not String(event.get("action","")).to_upper() in ["CLOSE","TURN"] or not String(event.get("surface","")).to_upper() in ["INSIDE","OUTSIDE"]:return
	if not rolling.get("position") is Vector3:return
	var point:Vector3=event.get("point",Vector3.ZERO)
	var center:Vector3=rolling.position
	_control_touch={"sequence":int(event.get("action_sequence",event.get("sequence",-1))),"physics_tick":int(event.get("physics_frame",Engine.get_physics_frames())),"point":point,"ball_center":center,"initial_radial_gap":absf(point.distance_to(center)-float(rolling.get("radius",.11))),"before_velocity":event.get("before_velocity",Vector3.ZERO),"exit_velocity":event.get("after_velocity",Vector3.ZERO),"surface":String(event.get("surface",""))}

func _control_load(avatar)->float:
	var action:Dictionary=avatar._action
	var nt:float=clampf(float(action.get("normalized_time",0)),0,1)
	if not bool(action.get("contact_confirmed",false)):
		return smoothstep(0,.5,nt)*(1.0-smoothstep(.65,1.0,nt))
	var phase_tail:float=1.0-smoothstep(.65,1.0,nt)
	if int(_control_touch.get("sequence",-2))!=int(action.get("sequence",-1)) or not _control_rolling.get("position") is Vector3:return phase_tail
	var side:int=int(action.get("side",1))
	var contact:Dictionary=avatar.get_foot_contact(side,String(action.get("surface","INSIDE")))
	var point:Vector3=contact.get("point",_control_touch.point)
	var gap:float=absf(point.distance_to(_control_rolling.position)-float(_control_rolling.get("radius",.11)))
	var separated:float=maxf(0,gap-float(_control_touch.initial_radial_gap))
	var toe:int=avatar.skeleton.find_bone("toe."+avatar.side_suffix(side))
	var release_distance:float=maxf(.010,avatar.skeleton.get_bone_rest(toe).origin.length()*.25)
	return minf(phase_tail,1.0-smoothstep(0,release_distance,separated))

func _planted_ankle(avatar,side:String)->Dictionary:
	var plants:Dictionary=avatar._plants
	if not plants.has(side) or bool(plants[side].get("releasing",false)):return {}
	var sk:Skeleton3D=avatar.skeleton
	var plant:Dictionary=plants[side]
	var world_rotation:Quaternion=(plant.rotation as Quaternion).slerp(Quaternion(Vector3.UP,float(plant.yaw)),smoothstep(0,.065,float(plant.age)))
	var rotation:Quaternion=sk.global_basis.get_rotation_quaternion().inverse()*world_rotation
	return {"point":sk.to_local(plant.point)-rotation*avatar._sole_offset(side),"rotation":rotation}

func should_hold_control_support(avatar,side:String,clip:String)->bool:
	if not _ordinary_low_control(avatar,clip) or side==avatar.side_suffix(int(avatar._action.get("side",1))) or _control_load(avatar)<=.5:return false
	var anchor:Dictionary=_planted_ankle(avatar,side)
	if anchor.is_empty():return false
	var sk:Skeleton3D=avatar.skeleton
	var hip:Vector3=sk.get_bone_global_pose(avatar.cached_bone_id("thigh."+side)).origin
	var maximum:float=sk.get_bone_rest(avatar.cached_bone_id("shin."+side)).origin.length()+sk.get_bone_rest(avatar.cached_bone_id("foot."+side)).origin.length()-.012
	if hip.distance_to(anchor.point)>maximum:return false
	_held_control_support=side
	return true

func apply_control_phase(avatar,delta:float,state:Dictionary)->void:
	var clip:String=String(avatar._base_clip)
	_control_info={"revision":"ordinary_support_body_06","eligible":false,"held_support":_held_control_support,"bone_writes":false}
	var running_transfer:bool=bool(avatar._carry039.direction_eligible) and (speed>1.1 or not _running_support.is_empty()) and bool(avatar._grounded) and state.get("interaction",{}).is_empty() and String(avatar._action.get("kind","")) in ["","CARRY","CLOSE","TURN","SHIELD","SPRINT"] and not avatar._action.has("cut_style")
	var actor:Node=avatar.get_parent()
	var near_transfer:bool=false
	if actor!=null and actor.get("foot")!=null and actor.has_method("get_ball_direction"):
		var follow=actor.foot.ordinary_scheduler.follow_step
		near_transfer=not follow.near_step.is_empty() and follow.near_control(actor,actor.match_controller.ball,actor.get_ball_direction()) and bool(avatar._grounded)
	_control_info["body_led_near"]=near_transfer
	if not _ordinary_low_control(avatar,clip) and not running_transfer and not near_transfer:
		_control_offset=Vector3.ZERO
		_running_support=""
		return
	var sk:Skeleton3D=avatar.skeleton
	var active:String=avatar.side_suffix(int(avatar._action.get("side",1)))
	var support:String="R" if active=="L" else "L"
	if (running_transfer or near_transfer) and avatar._action.is_empty():
		# Keep the current real plant until release; do not swap support because
		# a tactical target or rendered frame changed.
		if _planted_ankle(avatar,_running_support).is_empty():
			_running_support="L" if not _planted_ankle(avatar,"L").is_empty() else "R"
		support=_running_support
	elif running_transfer or near_transfer:_running_support=support
	var anchor:Dictionary=_planted_ankle(avatar,support)
	var ready:bool=not anchor.is_empty()
	if ready:
		var support_pose:Transform3D=sk.get_bone_global_pose(avatar.cached_bone_id("foot."+support))
		var support_rotation:Quaternion=sk.global_basis.get_rotation_quaternion()*support_pose.basis.get_rotation_quaternion()
		var sole_y:float=sk.to_global(support_pose.origin).y+avatar._minimum_offset(support,support_rotation)
		ready=sole_y-float(avatar._ground_y)<=.012
	var load_weight:float=(.55 if near_transfer else _control_load(avatar)) if ready else 0.0
	var compression:float=0.0
	if running_transfer or near_transfer:
		var plant:Dictionary=avatar._plants.get(support,{})
		var support_seconds:float=float(avatar._carry039.fraction)/maxf(float(avatar._carry039.rate),.8)
		var phase:float=clampf(float(plant.get("age",0))/maxf(support_seconds,.05),0,1)
		compression=sin(PI*phase) if ready else 0.0
		load_weight=(.4+.6*compression)*(smoothstep(.05,.8,speed) if near_transfer else smoothstep(.5,2.0,speed)) if ready else 0.0
	var wanted:=Vector3.ZERO
	if ready:
		var pelvis:Vector3=sk.get_bone_global_pose(int(ids.hips)).origin
		wanted.x=clampf((anchor.point as Vector3).x-pelvis.x,-.035,.035)
		var hip:Vector3=sk.get_bone_global_pose(avatar.cached_bone_id("thigh."+support)).origin+Vector3(wanted.x,0,0)
		var maximum:float=sk.get_bone_rest(avatar.cached_bone_id("shin."+support)).origin.length()+sk.get_bone_rest(avatar.cached_bone_id("foot."+support)).origin.length()-.012
		var horizontal:float=Vector2(hip.x-(anchor.point as Vector3).x,hip.z-(anchor.point as Vector3).z).length()
		var allowed:float=sqrt(maxf(0,maximum*maximum-horizontal*horizontal))
		wanted.y=clampf((anchor.point as Vector3).y+allowed-hip.y,-.020,0)
		wanted*=load_weight
		if running_transfer or near_transfer:
			# Compression/rebound belongs to the planted step, not an independent
			# bob clock. Existing post-IK reach checks below may reduce this offset.
			wanted.y=maxf(-.040,wanted.y-.026*compression*smoothstep(.8,3.0,speed)-.010*braking)
	if delta>0:_control_offset=_control_offset.lerp(wanted,1.0-exp(-10.0*delta))
	if running_transfer:_control_offset*=smoothstep(.08,.8,speed)
	_control_info["running_transfer"]=running_transfer
	_control_info["stance_compression"]=compression
	_control_info.merge({"eligible":true,"support_foot":support,"support_ready":ready,"motion_load_weight":load_weight,"offset_m":_control_offset,"contact_confirmed":bool(avatar._action.get("contact_confirmed",false)),"contact_tick":int(avatar._action.get("contact_tick",-1)),"plan_state":_control_rolling.get("plan_state","UNSPECIFIED"),"contact_age_s":_control_rolling.get("contact_age_s",-1.0),"ball_velocity":_control_rolling.get("velocity",Vector3.ZERO),"committed_exit_velocity":_control_touch.get("exit_velocity",Vector3.ZERO)},true)
	if _control_offset.length_squared()<.000000001:return
	# Preserve both completed real ankles/rotations. No foot target or gate edit.
	var goals:Dictionary={}
	for side in ["L","R"]:goals[side]=sk.get_bone_global_pose(avatar.cached_bone_id("foot."+side))
	var rotations:Dictionary={}
	for name in ["spine","chest","neck","thigh.L","shin.L","foot.L","toe.L","thigh.R","shin.R","foot.R","toe.R"]:
		var id:int=avatar.cached_bone_id(name);rotations[id]=sk.get_bone_pose_rotation(id)
	var hip_id:int=int(ids.hips)
	var initial_hip:Vector3=sk.get_bone_pose_position(hip_id)
	var hip_parent:int=sk.get_bone_parent(hip_id)
	var parent_basis:Basis=sk.get_bone_global_pose(hip_parent).basis if hip_parent>=0 else Basis.IDENTITY
	var local_offset:Vector3=parent_basis.inverse()*_control_offset
	var torso_length:float=sk.get_bone_rest(int(ids.spine)).origin.length()+sk.get_bone_rest(int(ids.chest)).origin.length()
	var roll:float=atan2(_control_offset.x,maxf(torso_length,.10))
	var forward:Vector3=sk.global_basis.inverse()*(state.get("forward",Vector3.FORWARD) as Vector3)
	var accepted:=false
	var preserved_error:float=0.0
	var strength:=1.0
	for attempt in 4:
		sk.set_bone_pose_position(hip_id,initial_hip+local_offset*strength)
		for name in ["spine","chest","neck"]:
			var id:int=int(ids[name]);var fraction:float=-.65 if name=="spine" else -.35 if name=="chest" else 1.0
			sk.set_bone_pose_rotation(id,Quaternion(Vector3.FORWARD,roll*fraction*strength)*(rotations[id] as Quaternion))
		var reachable:=true
		for side in ["L","R"]:
			var hip:Vector3=sk.get_bone_global_pose(avatar.cached_bone_id("thigh."+side)).origin
			var a:float=sk.get_bone_rest(avatar.cached_bone_id("shin."+side)).origin.length()
			var b:float=sk.get_bone_rest(avatar.cached_bone_id("foot."+side)).origin.length()
			var d:float=hip.distance_to((goals[side] as Transform3D).origin)
			if d>a+b-.0001 or d<absf(a-b)+.025:reachable=false
		if reachable:
			accepted=true
			preserved_error=0.0
			for side in ["L","R"]:
				var goal:Transform3D=goals[side]
				if not avatar._solve_leg(side,goal.origin,goal.basis.get_rotation_quaternion(),forward):accepted=false
				# The recovery guard preserves the original toe as well.
				var toe:int=avatar.cached_bone_id("toe."+side);sk.set_bone_pose_rotation(toe,rotations[toe])
			for side in ["L","R"]:
				var actual:Transform3D=sk.get_bone_global_pose(avatar.cached_bone_id("foot."+side))
				var goal:Transform3D=goals[side]
				preserved_error=maxf(preserved_error,actual.origin.distance_to(goal.origin))
				var q:Quaternion=actual.basis.get_rotation_quaternion();var old_q:Quaternion=goal.basis.get_rotation_quaternion()
				if q.dot(old_q)<0:old_q=Quaternion(-old_q.x,-old_q.y,-old_q.z,-old_q.w)
				if actual.origin.distance_to(goal.origin)>.00001 or maxf(maxf(absf(q.x-old_q.x),absf(q.y-old_q.y)),maxf(absf(q.z-old_q.z),absf(q.w-old_q.w)))>.00001:accepted=false
			if accepted:break
		# Restore a failed attempt before trying a smaller geometric transfer.
		sk.set_bone_pose_position(hip_id,initial_hip)
		for id in rotations:sk.set_bone_pose_rotation(int(id),rotations[id])
		strength*=.5
	_control_info["bone_writes"]=accepted
	_control_info["preserved_ankle_error_m"]=preserved_error if accepted else 0.0
	_control_info["accepted_strength"]=strength if accepted else 0.0
	_control_info["applied_offset_m"]=_control_offset*strength if accepted else Vector3.ZERO
	if accepted:_control_restore={"hip_id":hip_id,"hip_position":initial_hip,"rotations":rotations}

func control_support_snapshot(avatar)->Dictionary:
	var sk:Skeleton3D=avatar.skeleton
	if not is_instance_valid(sk) or ids.is_empty():return {"support_phase":"UNSPECIFIED"}
	var support:Dictionary={}
	for side in ["L","R"]:
		var plant:Dictionary=avatar._plants.get(side,{})
		var phase:String="RELEASING" if bool(plant.get("releasing",false)) else "PLANTED" if not plant.is_empty() else "SWING"
		var hip:Vector3=sk.to_global(sk.get_bone_global_pose(avatar.cached_bone_id("thigh."+side)).origin)
		var knee:Vector3=sk.to_global(sk.get_bone_global_pose(avatar.cached_bone_id("shin."+side)).origin)
		var foot:Transform3D=sk.get_bone_global_pose(avatar.cached_bone_id("foot."+side))
		var ankle:Vector3=sk.to_global(foot.origin)
		var a:float=sk.get_bone_rest(avatar.cached_bone_id("shin."+side)).origin.length()
		var b:float=sk.get_bone_rest(avatar.cached_bone_id("foot."+side)).origin.length()
		var rotation:Quaternion=sk.global_basis.get_rotation_quaternion()*foot.basis.get_rotation_quaternion()
		var sole_min:float=ankle.y+avatar._minimum_offset(side,rotation)-float(avatar._ground_y)
		support[side]={"state":phase,"hip":hip,"knee":knee,"ankle":ankle,"sole_min_above_ground_m":sole_min,"sole_near_ground":sole_min<=.012,"leg_margin_m":a+b-hip.distance_to(ankle),"knee_flexion_deg":180.0-rad_to_deg((hip-knee).angle_to(ankle-knee)),"anchor":plant.get("point",Vector3.ZERO)}
	var epoch:Dictionary=avatar.get_pose_refresh_debug() if avatar.has_method("get_pose_refresh_debug") else {}
	return {"support_phase":support,"gait_clip":String(avatar._base_clip),"gait_phase":float(avatar._phase),"body_yaw":avatar.visual.global_rotation.y,"hips_world":sk.to_global(sk.get_bone_global_pose(int(ids.hips)).origin),"pose_tick":int(epoch.get("pose_tick",-1)),"pose_world_step":int(epoch.get("pose_world_step",-1)),"captured_physics_tick":Engine.get_physics_frames(),"source_stage":"read_only_last_completed_model_pose","body_phase":_control_info.duplicate(true),"rolling":_control_rolling.duplicate()}
