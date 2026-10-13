extends "res://addons/football_character/football_character.gd"
## Drop-in foot03 subclass: sampling->body motion->anchors->real target IK.
signal ground_step(event:Dictionary)
signal locomotion_transition(event:Dictionary)
signal action_pose_sampled(skeleton:Skeleton3D,clip:String,action:Dictionary,state:Dictionary,delta:float)
const BodyMotion:=preload("res://addons/football_motion/body_motion.gd")
const LocomotionIntent039:=preload("res://addons/football_motion/locomotion_intent_039.gd")
const CarryGait039:=preload("res://addons/football_motion/carry_gait_039.gd")
const DirectionalGait039:=preload("res://addons/football_motion/directional_gait_039.gd")
const TransitionSteps039:=preload("res://addons/football_motion/transition_steps_039.gd")
const LateralSupport09:=preload("res://addons/football_motion/lateral_support_09.gd")
var _lateral09=LateralSupport09.new()
var _lateral_request09:Dictionary={}
var _body=BodyMotion.new()
var _motion_state:Dictionary={}
var _control_hub:Node
var _free_run_gait:=false
var _free_gait_initialized:=false
var _free_gait_active:=false
var _motion039=LocomotionIntent039.new()
var _stride039:=1.0
var _leg_ids039:Dictionary={}
var _stance_fraction039:=0.0
var _carry039=CarryGait039.new()
var _directional039=DirectionalGait039.new()
var _steps039=TransitionSteps039.new()

func setup(team:int,jersey:int,first_person:bool)->void:
	super.setup(team,jersey,first_person)
	_motion039.first_person=first_person
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	for node in mesh_nodes:
		var canonical_name:=String(node.name).replace("_",".")
		if String(node.name) in manifest.get("first_person_hide",[]) or canonical_name in manifest.get("first_person_hide",[]):node.visible=not first_person

func update_pose(delta:float,state:Dictionary)->void:
	var pose_state:=state.duplicate()
	pose_state["motion039_first_person"]=_motion039.first_person
	var velocity:Vector3=state.get("velocity",Vector3.ZERO)
	var speed:=Vector2(velocity.x,velocity.z).length()
	# Legacy press/jockey may label a full-speed actor as walking. Select its
	# actual run gait so the torso and arms do not follow a 500+ step/min walk.
	var mode:String=String(state.get("locomotion","idle")).to_lower()
	var free_gait:bool=_action.is_empty() and String(state.get("control_tier","")).to_upper()=="FREE" and bool(state.get("grounded",true)) and mode in ["idle","walk","jog","run","sprint","jockey","press","start","stop","retreat","backpedal","strafe"]
	_motion039.update(maxf(0,delta),state,_action,_plants)
	free_gait=free_gait and _motion039.eligible
	_carry039.prepare(maxf(0,delta),state,_action)
	var direction_allowed039:bool=free_gait or _carry039.direction_eligible and speed<=2.10
	_directional039.prepare(maxf(0,delta),state,_action,direction_allowed039,_carry039.active)
	if free_gait:
		var view_forward:Vector3=state.get("forward",Vector3.FORWARD)
		var offset:float=clampf(_motion039.yaw_offset,-PI/3.0,PI/3.0) if _motion039.first_person else _motion039.yaw_offset
		offset*=1.0-_directional039.direction_weight
		pose_state.forward=view_forward.rotated(Vector3.UP,offset)
		pose_state["motion039_yaw_offset"]=offset
		pose_state["motion039_counter_yaw"]=-.35*sin(offset)
	_free_gait_active=free_gait
	if free_gait:
		# Visual gait uses actual speed for AI and player alike. No input branch.
		# Reuse the released 2.10/1.85 hysteresis band; retain its phase/blend/IK.
		if not _free_gait_initialized:
			_free_run_gait=speed>2.10;_free_gait_initialized=true
		elif _free_run_gait:
			if speed<1.85:_free_run_gait=false
		elif speed>2.10:_free_run_gait=true
		pose_state.locomotion="idle" if speed<.08 else "run" if _free_run_gait else "walk"
	else:
		_free_gait_initialized=false
		if speed>3.0 and mode in ["idle","walk","jog","jockey","press","shield","start","stop"]:pose_state.locomotion="run"
	ensure_loaded()
	_lateral09.prepare(self,maxf(0,delta),pose_state,_read_lateral_request09())
	_steps039.prepare(self,maxf(0,delta),pose_state,(free_gait or _carry039.direction_eligible) and _allows_transition_steps())
	if _steps039.active and free_gait:
		var view039:Vector3=state.get("forward",Vector3.FORWARD)
		var yaw039:float=_steps039.yaw_offset(view039,float(pose_state.get("motion039_yaw_offset",0)),_motion039.first_person)
		pose_state.forward=view039.rotated(Vector3.UP,yaw039)
		pose_state["motion039_yaw_offset"]=yaw039
		pose_state["motion039_counter_yaw"]=-.35*sin(yaw039)
	_motion_state=pose_state
	_body.restore_control_phase(self)
	_bind_control_events()
	_body.prepare_control_context(self,pose_state,_read_control_rolling())
	_body.update(delta,pose_state,_action)
	super.update_pose(delta,pose_state)
	_body.apply_control_phase(self,delta,pose_state)
	_lateral09.observe(self)
	_steps039.observe(self)
	for event039 in _steps039.take_events():locomotion_transition.emit(event039)
	for event in _body.ground_events(self,delta,pose_state):ground_step.emit(event)

func _sample(clip:String,seconds:float)->void:
	super._sample(clip,seconds)
	_body.apply(self,clip,_phase)
	if not _action.is_empty() or not _motion_state.get("interaction",{}).is_empty():action_pose_sampled.emit(skeleton,clip,_action,_motion_state,_pose_delta)

func get_full_body_debug()->Dictionary:
	var result:Dictionary=_body.debug()
	result["locomotion039"]=_motion039.debug()
	result["stride_amplitude039"]=_stride039
	result["steps_per_second039"]=_cadence*2.0
	result["stance_fraction039"]=_stance_fraction039
	result["carry_gait039"]=_carry039.debug()
	result["directional_gait039"]=_directional039.debug()
	result["transition_steps039"]=_steps039.debug()
	return result

func _restart_gait_phase(base:String)->void:
	if not _free_gait_active and not _carry039.active:super._restart_gait_phase(base)

func _select_gait_base(base:String)->String:
	if _steps039.active and base=="Idle":return "Walk"
	return _carry039.select_base(base)

func _align_transition_gait_phase(phase:float)->float:
	var fraction:float=_stance_fraction039 if _stance_fraction039>0 else float(_profiles.get(_base_clip,{}).get("stance_fraction",.58))
	return _steps039.phase_hint(phase,fraction)

func _gait_direction_sign(mode:String)->float:
	return 1.0 if _directional039.directional else super._gait_direction_sign(mode)

func _gait_cadence(base:String,speed:float,duration:float)->float:
	var authored:float=super._gait_cadence(base,speed,duration)
	_stride039=1.0
	if _carry039.active and base in ["Dribble","DribbleJog"]:
		_stance_fraction039=_carry039.fraction
		return _carry039.rate
	if not _free_gait_active or base=="Idle":
		_stance_fraction039=0.0
		return authored
	var fraction:float=float(_profiles[base]["stance_fraction"])
	var rate:float=LocomotionIntent039.cycles(speed)
	var safe_fraction:float=minf(fraction,float(_profiles[base]["stance_distance"])*rate/maxf(speed,.001))
	if _stance_fraction039<=0:_stance_fraction039=safe_fraction
	elif _pose_delta>0:_stance_fraction039=minf(safe_fraction,lerpf(_stance_fraction039,safe_fraction,1.0-exp(-10.0*_pose_delta)))
	# Visual amplitude limits, not a promise of physical stride length.
	_stride039=clampf(authored/maxf(rate,.001),.65,1.25)
	return rate

func _shape_sampled_gait(clip_name:String)->void:
	if not _free_gait_active or not _action.is_empty() or not clip_name in ["Walk","Run"]:return
	if _leg_ids039.is_empty():
		for side in ["L","R"]:
			for stem in ["thigh.","shin."]:_leg_ids039[stem+side]=cached_bone_id(stem+side)
	# Local rotations before the existing sample refresh and body solve.
	for name in _leg_ids039:
		var id:int=int(_leg_ids039[name])
		if id>=0:
			var q:Quaternion=skeleton.get_bone_pose_rotation(id)
			skeleton.set_bone_pose_rotation(id,Quaternion.IDENTITY.slerp(q,_stride039))

func _update_support(dt: float, base: String, speed: float, forward: Vector3) -> void:
	_body._held_control_support=""
	if not _grounded:
		_plants.clear()
		return
	# Bounded horizontal load transfer, once after clip blending.
	var hips09:int=cached_bone_id("hips")
	skeleton.set_bone_pose_position(hips09,skeleton.get_bone_pose_position(hips09)+Vector3(_lateral09.pelvis_x,0,0))
	for side in ["L", "R"]:
		var p := fposmod(_phase+(.5 if side == "R" else 0.0), 1.0)
		var fraction:float=1.0 if base == "Idle" else (_stance_fraction039 if (_free_gait_active or _carry039.active) and _stance_fraction039>0 else float(_profiles[base]["stance_fraction"]))
		var wanted := base == "Idle" or p < fraction
		if not _action.is_empty():
			if side == side_suffix(int(_action.get("side", 1))): wanted = false
			elif speed <= .35:
				wanted = true
			elif _body.should_hold_control_support(self,side,base):
				wanted = true
			elif _carry039.hold_support(side,_action,_plants,_last_contacts,_ground_y):
				wanted = true
		wanted=_steps039.support_wanted(side,wanted)
		if _lateral09.owns(side):
			if String(_lateral09.step.phase) in ["SWING","LANDING","LANDED"]:
				_lateral09.solve(self,side,forward)
				continue
			wanted=true
		# The opposite foot bears weight during preparation; active action IK stays authoritative.
		if not _lateral09.step.is_empty() and _action.is_empty():wanted=true
		var foot_id := cached_bone_id("foot."+side)
		var pose := skeleton.get_bone_global_pose(foot_id)
		var world_rotation := (skeleton.global_basis*pose.basis).get_rotation_quaternion()
		if _plants.has(side) and not wanted: _begin_release(side, pose)
		if not _plants.has(side):
			if not wanted: continue
			var socket_world := skeleton.to_global(pose.origin+pose.basis*_sole_offset(side))
			var anchor: Vector3 = _last_contacts.get(side, socket_world)
			_plants[side] = {"point": anchor, "rotation": world_rotation, "age": 0.0, "yaw": visual.global_rotation.y, "releasing": false}
		var plant: Dictionary = _plants[side]
		if plant["releasing"]:
			_release_support(side, dt, pose, forward)
			continue
		plant["age"] += dt
		var flat := Quaternion(Vector3.UP, float(plant["yaw"]))
		world_rotation = (plant["rotation"] as Quaternion).slerp(flat, smoothstep(0.0, .065, float(plant["age"])))
		var anchor: Vector3 = plant["point"]
		anchor.y = _ground_y+.005-_minimum_offset(side, world_rotation)+(world_rotation*_sole_offset(side)).y
		plant["point"] = anchor
		var local_rotation := skeleton.global_basis.get_rotation_quaternion().inverse()*world_rotation
		var ankle := skeleton.to_local(anchor)-local_rotation*_sole_offset(side)
		if not _solve_leg(side, ankle, local_rotation, skeleton.global_basis.inverse()*forward):
			_plant_releases += 1
			if skeleton.to_global(ankle).distance_to(skeleton.to_global(pose.origin)) > .6:
				# A teleport is a discontinuity in the actor itself, so reset safely.
				_plants.erase(side)
			else:
				_begin_release(side, pose)
				_release_support(side, dt, pose, forward)

# Appended to MotionAvatar by build_candidate.py; no ball/actor writes.

func _read_control_rolling()->Dictionary:
	var actor:Node=get_parent()
	if actor==null or not actor.has_method("get_ball_direction"):return {}
	var game:Node=actor.get("match_controller") as Node
	if not is_instance_valid(game) or not game.has_method("ball_snapshot") or not is_instance_valid(game.get("ball")):return {}
	var result:Dictionary=game.call("ball_snapshot")
	var foot:RefCounted=actor.get("foot") as RefCounted
	if is_instance_valid(foot):
		var plan:Dictionary=foot.get("touch_plan")
		if int(plan.get("sequence",-1))==int(_action.get("sequence",-2)):
			var support:Dictionary=plan.get("support",{})
			if support.get("velocity") is Vector3:result["begin_velocity"]=support.velocity
		result["plan_state"]=plan.get("state","UNSPECIFIED")
		result["contact_age_s"]=maxf(0,float(foot.get("elapsed"))-float(foot.get("contact_elapsed"))) if bool(foot.get("hit")) else -1.0
	return result

func _bind_control_events()->void:
	var actor:Node=get_parent()
	if actor==null or not actor.has_method("get_ball_direction"):return
	var game:Node=actor.get("match_controller") as Node
	if not is_instance_valid(game):return
	var hub:Node=game.get("contact_hub") as Node
	if not is_instance_valid(hub) or not hub.has_signal("contact_resolved") or hub==_control_hub:return
	if is_instance_valid(_control_hub) and _control_hub.is_connected("contact_resolved",_on_control_contact):_control_hub.disconnect("contact_resolved",_on_control_contact)
	if not hub.is_connected("contact_resolved",_on_control_contact):hub.connect("contact_resolved",_on_control_contact)
	_control_hub=hub

func _on_control_contact(event:Dictionary)->void:
	if event.get("actor")!=get_parent():return
	_body.note_control_touch(event,_read_control_rolling())

func get_control_support_snapshot()->Dictionary:
	var actor39:Node=get_parent()
	if actor39!=null and actor39.has_method("ensure_contact_pose_current"):actor39.ensure_contact_pose_current()
	var result:Dictionary=_body.control_support_snapshot(self)
	result["support_step"]=_lateral09.snapshot()
	return result

# Optional explicit readonly intent contract. No actor/ball writes.
func set_lateral_support_request09(value:Dictionary)->void:
	_lateral_request09=value.duplicate(true)

func _read_lateral_request09()->Dictionary:
	if not _lateral_request09.is_empty():return _lateral_request09
	var actor:Node=get_parent()
	if actor==null or not actor.has_method("get_ball_direction"):return {}
	var foot:RefCounted=actor.get("foot") as RefCounted
	if not is_instance_valid(foot):return {}
	var scheduler:RefCounted=foot.get("ordinary_scheduler") as RefCounted
	if not is_instance_valid(scheduler) or not scheduler.has_method("body_control_snapshot"):return {}
	# Inactive lateral support never consumes leg geometry. Keep live reads for active support.
	if scheduler.has_method("has_active_body_control_request") and not scheduler.call("has_active_body_control_request",actor):return {}
	return scheduler.call("body_control_snapshot",actor)

# Ordinary-carry clock; optional near-ball reach query reuses the completed pose.
var _ordinary_leg_geometry041:Dictionary={}
func ordinary_gait_clock040(with_reach:bool=false)->Dictionary:
	var fraction:float=_stance_fraction039 if _stance_fraction039>0 else float(_profiles.get(_base_clip,{}).get("stance_fraction",.58))
	var direction_sign:float=_gait_direction_sign(String(_motion_state.get("locomotion","idle")).to_lower())
	var result:Dictionary={"phase":_phase,"rate":_cadence,"signed_rate":_cadence*direction_sign,"fraction":fraction,"grounded_L":_steps039._grounded(self,"L"),"grounded_R":_steps039._grounded(self,"R"),"transition_active":_steps039.active and _steps039._dribble_request>=0}
	# Only the near-ball admission query asks for two current hips. Cache IDs/rest
	# lengths once; no full snapshot, force update, pose write, or solve.
	if with_reach and is_instance_valid(skeleton):
		for side041 in ["L","R"]:
			if not _ordinary_leg_geometry041.has(side041):
				var hip_id:int=cached_bone_id("thigh."+side041)
				var shin_id:int=cached_bone_id("shin."+side041)
				var foot_id:int=cached_bone_id("foot."+side041)
				if mini(hip_id,mini(shin_id,foot_id))<0:continue
				_ordinary_leg_geometry041[side041]={"hip_id":hip_id,"length":skeleton.get_bone_rest(shin_id).origin.length()+skeleton.get_bone_rest(foot_id).origin.length()-.012}
			var geometry:Dictionary=_ordinary_leg_geometry041[side041]
			var ankle:Dictionary=_last_ankles.get(side041,{})
			if ankle.is_empty():continue
			result["reach_"+side041]={"hip":skeleton.to_global(skeleton.get_bone_global_pose(int(geometry.hip_id)).origin),"ankle":ankle.point,"length":geometry.length}
	return result

func yield_ordinary_transition041()->void:
	# Arbitration only. Never forge landings or interrupt the explicit transaction.
	if not _action.is_empty() or not _steps039.active or _steps039._dribble_request>=0:return
	_steps039._event("ABORT","ordinary_touch_reservation_priority")
	_steps039.active=false;_steps039.stage="IDLE";_steps039.sink=0;_steps039.arm=0
	_steps039._cooldown=.12

func ordinary_support_bits047()->int:
	# Near-carrier observation only; cached feet, no pose refresh/bone query.
	var bits:int=0
	for side047 in ["L","R"]:
		var bit:int=1 if side047=="L" else 2
		if _steps039._grounded(self,side047):bits|=bit
		var foot047:Dictionary=_last_ankles.get(side047,{})
		if not foot047.is_empty():
			var gap:float=(foot047.point as Vector3).y+_minimum_offset(side047,foot047.rotation)-float(_ground_y)
			if gap>.018:bits|=bit<<2
	return bits

func request_dribble_steps040(incoming:Vector3,desired:Vector3)->int:
	if not _action.is_empty() or not _lateral09.step.is_empty():return -1
	return _steps039.request_dribble_turn(incoming,desired)

func dribble_steps_status040(request:int)->String:
	return _steps039.dribble_status(request)

func cancel_dribble_steps040(request:int)->void:
	_steps039.cancel_dribble(request)

var _display_gait_active:=false
var _display_gait_run:=false
var _display_blend_from:Array=[]
var _display_blend_age:=0.0
var _display_updates:=0
func update_display_gait(delta:float,state:Dictionary)->void:
	ensure_loaded()
	var dt:float=maxf(0,delta)
	var velocity:Vector3=state.get("velocity",Vector3.ZERO)
	var speed:float=Vector2(velocity.x,velocity.z).length()
	if not _display_gait_active:
		_display_gait_active=true;_display_gait_run=speed>2.10
		_display_blend_from=_save_pose();_display_blend_age=0
		_body.restore_control_phase(self)
	elif _display_gait_run and speed<1.85:_display_gait_run=false
	elif not _display_gait_run and speed>2.10:_display_gait_run=true
	var clip:String="Idle" if speed<(.08 if _base_clip=="Idle" else .04) else "Run" if _display_gait_run else "Walk"
	if clip!=_base_clip:
		_display_blend_from=_save_pose();_display_blend_age=0
	var forward:Vector3=state.get("forward",Vector3.FORWARD)
	var yaw:float=atan2(-forward.x,-forward.z)
	visual.global_rotation=Vector3(0,lerp_angle(visual.global_rotation.y,yaw,1.0-exp(-18.0*dt)),0)
	visual.position=Vector3.ZERO
	var duration:float=animation_player.get_animation(clip).length
	_cadence=_display_gait_rate(speed,duration,clip=="Idle")
	_phase=fposmod(_phase+dt*_cadence,1.0)
	_free_gait_active=false # Display sampling deliberately omits contact/support solvers.
	super._sample(clip,_phase*duration)
	_display_blend_age+=dt
	if not _display_blend_from.is_empty() and _display_blend_age<.12:
		var weight:float=smoothstep(0,.12,_display_blend_age)
		for i in skeleton.get_bone_count():
			skeleton.set_bone_pose_position(i,(_display_blend_from[i].position as Vector3).lerp(skeleton.get_bone_pose_position(i),weight))
			skeleton.set_bone_pose_rotation(i,(_display_blend_from[i].rotation as Quaternion).slerp(skeleton.get_bone_pose_rotation(i),weight))
	else:_display_blend_from.clear()
	_display_sample_style(state) # Final ankle targets must survive the pose blend.
	_base_clip=clip;_clip=clip;_blend_key=clip
	skeleton.force_update_all_bone_transforms()
	_display_updates+=1
func finish_display_gait()->void:
	if not _display_gait_active:return
	_display_gait_active=false
	# Drop stale distant world plants before re-entering full contact IK. The next
	# solve uses the current root/ball and blends from this completed visible pose.
	_blend_from=_save_pose();_blend_time=0.0
	_plants.clear();_last_ankles.clear();_last_local_ankles.clear();_last_contacts.clear()
	_free_gait_initialized=false
	if has_method("invalidate_pose_snapshot"):call("invalidate_pose_snapshot")

func _display_sample_style(_state:Dictionary)->void:pass

func _allows_transition_steps()->bool:return true

func _display_gait_rate(speed:float,duration:float,idle:bool)->float:
	return 1.0/duration if idle else LocomotionIntent039.cycles(speed)
