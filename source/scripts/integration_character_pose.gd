extends "res://addons/football_motion/fp_body_visibility_01.gd"
## B host stance adapter. The motion addon owns normal gait/support/contacts.
## Dedicated kick/sole/tackle stance is retained only until actual regression.
var planted_support: Dictionary = {}
var active_socket: Dictionary = {}
var weight_shift := Vector3.ZERO
const TEAM_COLOR_PRESETS := {"blue":Color("1d5fff"),"yellow":Color("ffdd00"),"red":Color("ef2532")}
var color_preset := "blue"
const ShotMotion := preload("res://scripts/shooting_motion.gd")
var shooting_motion := ShotMotion.new()
var tackle_motion := preload("res://scripts/tackle_motion.gd").new()
var _shot_body_sampled := false
var ai_run_ankles=preload("res://scripts/ai_run_ankles.gd").new()
var ai_body_presentation=preload("res://scripts/ai_body_presentation.gd").new()
const CarryRun07 := preload("res://addons/football_motion/carry_run_07.gd")
var _carry_run07 = CarryRun07.new()

func setup(team: int, jersey: int, first_person: bool) -> void:
	super.setup(team,jersey,first_person)
	preload("res://scripts/broadcast_body.gd").apply(self,first_person)
	if not action_pose_sampled.is_connected(_sample_shot_body): action_pose_sampled.connect(_sample_shot_body)
	if has_method("set_upper_body_overlay_enabled"): call("set_upper_body_overlay_enabled",false)

func _sample_shot_body(sk: Skeleton3D, _clip: String, action: Dictionary, _state: Dictionary, _delta: float) -> void:
	if String(action.get("kind",""))=="TACKLE":
		tackle_motion.sample_body(sk,action)
		return
	if String(action.get("kind",""))!="SHOT": return
	shooting_motion.sample_body(sk,action)
	_shot_body_sampled = true

func set_color_preset(preset: String) -> void:
	var normalized := preset.to_lower()
	if not TEAM_COLOR_PRESETS.has(normalized): return
	color_preset = normalized
	super.set_color_preset(normalized.to_upper())

func clear_foot_action() -> void:
	super.clear_foot_action()
	active_socket.clear()
	planted_support.clear()
	shooting_motion.reset()

func get_foot_contact(side: int, surface: String) -> Dictionary:
	if not active_socket.is_empty() and not _action.is_empty() and side_suffix(side)==side_suffix(int(_action.get("side",1))) and surface.to_upper()==String(_action.get("surface","INSTEP")).to_upper(): return active_socket.duplicate()
	return super.get_foot_contact(side,surface)

const Perf11Probe:=preload("res://scripts/perf11_probe.gd")
const SpikeWatch:=preload("res://scripts/frame_spike_watch.gd")
const PoseFlush:=preload("res://scripts/pose_flush_probe.gd")
func update_pose(delta: float, state: Dictionary) -> void:
	if not Perf11Probe.sampling and not SpikeWatch.enabled:
		_update_pose_impl(delta,state)
		PoseFlush.complete(skeleton)
		return
	var started:int=Time.get_ticks_usec()
	_update_pose_impl(delta,state)
	PoseFlush.complete(skeleton)
	var elapsed:int=Time.get_ticks_usec()-started
	if Perf11Probe.sampling:
		Perf11Probe.pose_usec+=elapsed
		Perf11Probe.pose_calls+=1
	if SpikeWatch.enabled:
		SpikeWatch.pose_us+=elapsed;SpikeWatch.pose_calls+=1
		if delta<=0:SpikeWatch.zero_pose_calls+=1
		var actor=get_parent()
		if actor.is_human:SpikeWatch.human_pose_us+=elapsed
		elif actor.is_goalkeeper:SpikeWatch.keeper_pose_us+=elapsed

func _update_pose_impl(delta: float, state: Dictionary) -> void:
	ensure_loaded()
	ai_body_presentation.prepare(self,delta,state,_action)
	ai_run_ankles.prepare(self,delta,state,_action)
	finish_display_gait()
	_carry_run07.restore(self)
	_carry_run07.update(delta,state,_action)
	visual.position = Vector3.ZERO
	active_socket.clear()
	planted_support.clear()
	if String(_action.get("kind",""))=="TACKLE":
		weight_shift=tackle_motion.shift(_action,state,global_position)
		visual.position=global_basis.inverse()*weight_shift
		super.update_pose(delta,state)
		var side:int=int(_action.side)
		active_socket=super.get_foot_contact(side,String(_action.surface)).duplicate()
		var support_target:Vector3=tackle_motion.support_target(_action,global_position,global_position.y)
		var support_ok:bool=apply_foot_target(-side,"SOLE",support_target,state.get("forward",Vector3.FORWARD))
		planted_support=super.get_foot_contact(-side,"SOLE")
		planted_support["valid"]=support_ok
		planted_support["target"]=support_target
		# Commit final post-support shoes, so the next gait begins from the shown pose.
		for foot_side in [-1,1]:
			var suffix:String=side_suffix(foot_side)
			var pose:Transform3D=skeleton.get_bone_global_pose(cached_bone_id("foot."+suffix))
			var world:Transform3D=skeleton.global_transform*pose
			_last_contacts[suffix]=skeleton.to_global(skeleton.get_bone_global_pose(cached_bone_id("contact_sole."+suffix)).origin)
			_last_ankles[suffix]={"point":world.origin,"rotation":world.basis.get_rotation_quaternion()}
			_last_local_ankles[suffix]={"point":pose.origin,"rotation":pose.basis.get_rotation_quaternion()}
		return
	if String(_action.get("kind",""))=="SHOT":
		_shot_body_sampled = false
		shooting_motion.prepare(self,_action,state)
		# ShotMotion owns additional bone writes after the base sample.
		invalidate_pose_snapshot()
		super.update_pose(delta,state)
		shooting_motion.apply(self,delta,state,_action,_shot_body_sampled)
		active_socket = shooting_motion.active_contact.duplicate()
		planted_support = shooting_motion.support_contact.duplicate()
		weight_shift = shooting_motion.shift
		# Locomotion resumes from the actual completed shot pose.
		for foot_side in [-1,1]:
			var suffix := side_suffix(foot_side)
			var pose := skeleton.get_bone_global_pose(skeleton.find_bone("foot."+suffix))
			var world := skeleton.global_transform*pose
			_last_contacts[suffix] = skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone("contact_sole."+suffix)).origin)
			_last_ankles[suffix] = {"point":world.origin,"rotation":world.basis.get_rotation_quaternion()}
			_last_local_ankles[suffix] = {"point":pose.origin,"rotation":pose.basis.get_rotation_quaternion()}
		return
	shooting_motion.reset()
	super.update_pose(delta,state)
	if _action.is_empty() or String(_action.get("kind","")).to_upper() in ["CARRY","CLOSE","SHIELD","TURN","SPRINT"]:
		_carry_run07.apply(self,delta,state)
		weight_shift = Vector3.ZERO
		return
	var side := int(_action.get("side",1))
	var surface := String(_action.get("surface","INSTEP")).to_upper()
	var support := super.get_foot_contact(-side,"SOLE")
	var support_target: Vector3 = support.point
	support_target.y = global_position.y+.006
	var forward: Vector3 = state.get("forward",Vector3.FORWARD)
	forward.y = 0
	forward = forward.normalized()
	var t := float(_action.get("normalized_time",.5))
	var weight := smoothstep(0,1,t/.5) if t<.5 else 1.0-smoothstep(0,1,(t-.65)/.35) if t>.65 else 1.0
	var tackle := String(_action.get("kind",""))=="TACKLE"
	var kick := String(_action.get("kind","")) in ["PASS","SHOT"]
	var passing := String(_action.get("kind",""))=="PASS"
	var sole := surface=="SOLE"
	var lateral_touch := String(_action.get("kind",""))=="TURN"
	# Ordinary repeated touches must not receive a full-shot crouch every .2s.
	# The source clip already lowers the hips; an extra 75mm caused deep flexion.
	weight_shift = forward*(.14 if tackle else .10 if lateral_touch else .085 if kick or sole else .035)*weight+Vector3.DOWN*(.065 if tackle else .028 if passing else .075 if kick else .040 if sole else .020 if lateral_touch else .012)*weight
	if String(_action.get("kind",""))=="RECEIVE":
		var toward:Vector3=_action.world_target-global_position;toward.y=0
		var extension:float=clampf((toward.length()-.48)*.42,0,.20)
		weight_shift=(toward.normalized()*extension+Vector3.DOWN*lerpf(.030,.065,clampf(float(_action.get("receive_speed",0))/14.0,0,1)))*weight
	visual.position = global_basis.inverse()*weight_shift
	super.update_pose(0,state)
	# Capture active validity before independently solving the other leg. The
	# frozen wrapper's per-query reach state must not let the support solve turn
	# an unreachable active foot into an accepted contact.
	active_socket = super.get_foot_contact(side,surface).duplicate()
	var support_ok := apply_foot_target(-side,"SOLE",support_target,forward)
	planted_support = super.get_foot_contact(-side,"SOLE")
	planted_support["valid"] = support_ok and planted_support.point.distance_to(support_target)<.035
	planted_support["target"] = support_target

func get_carry_run_debug()->Dictionary:return _carry_run07.debug()

func _sample(clip:String,seconds:float)->void:
	super._sample(clip,seconds)
	ai_body_presentation.apply_before_support(self,_motion_state,_action)

func update_display_gait(delta:float,state:Dictionary)->void:
	ai_body_presentation.prepare(self,delta,state,{})
	ai_run_ankles.prepare(self,delta,state,{})
	super.update_display_gait(delta,state)

func _display_sample_style(state:Dictionary)->void:
	ai_body_presentation.apply_before_support(self,state,{})
	ai_run_ankles.apply(self,state.get("forward",Vector3.FORWARD),ai_run_ankles.pose_delta)

func _update_support(dt:float,base:String,speed:float,forward:Vector3)->void:
	preload("res://scripts/pass_body_motion.gd").apply(self,_action)
	preload("res://scripts/cut_pull_body.gd").apply(self,_action)
	preload("res://scripts/body_intent_pose.gd").apply(self,_motion_state,_action)
	if ai_run_ankles.apply(self,forward,dt):return
	super._update_support(dt,base,speed,forward)

func _bound_control_motion(side:String,forward:Vector3)->void:
	if ai_run_ankles.active:return # This free-run trajectory replaces, not stacks with, the control shoe limiter.
	super._bound_control_motion(side,forward)

func _allows_transition_steps()->bool:
	return not ai_run_ankles.active

# Shared phase remains the only gait clock; stationary guards do not march in place.
func _gait_cadence(base:String,speed:float,duration:float)->float:
	if ai_run_ankles.active:return ai_run_ankles.cadence()
	return super._gait_cadence(base,speed,duration)
func _gait_direction_sign(mode:String)->float:
	return 1.0 if ai_run_ankles.active else super._gait_direction_sign(mode)

func _display_gait_rate(speed:float,duration:float,idle:bool)->float:
	return ai_run_ankles.cadence() if ai_run_ankles.active else (1.0/duration if idle else LocomotionIntent039.cycles(speed))
