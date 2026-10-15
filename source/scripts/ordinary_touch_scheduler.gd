extends RefCounted
const DribbleRhythm := preload("res://scripts/dribble_rhythm.gd")
## Read-only ordinary-touch preparation. Inputs select intent, not force.
## Shared actors use the same ball/shoe/support state. No model bone writes.
var last_decision: Dictionary = {}
var committed_sequence := -1
var committed_side := 0
var recovered_to_stance := true
var stance_started_tick := -1
var dominant_control_enabled := true
var continuous_control_enabled := true
var step_serial := 0
var consumed_support_episode := -1
var last_exit_velocity := Vector3.ZERO
var step_intent:Dictionary = {}
var follow_step := preload("res://scripts/dribble_follow_step.gd").new()
func _init()->void:
	for arg in OS.get_cmdline_user_args():
		if arg=="--dominant-control=A":dominant_control_enabled=false
		if arg=="--continuous-control=A":continuous_control_enabled=false

func has_active_body_control_request(actor:Node3D)->bool:
	if not turn_stage.is_empty():return false
	# Admission metadata only. Active requests still read the current completed pose.
	var active:bool=last_decision.get("intent","")=="CROSS_BODY_INSIDE" and (actor.foot.idle() or actor.foot.kind in ["CLOSE","TURN","SHIELD"])
	return actor.is_human and active if continuous_control_enabled and not step_intent.is_empty() else dominant_control_enabled and active

func body_control_snapshot(actor:Node3D)->Dictionary:
	# Readonly handoff for the body author: synchronize load/unload to the
	# existing support/contact episode, never a separate bob oscillator.
	var support:Dictionary=actor.avatar.get_control_support_snapshot() if actor.avatar.has_method("get_control_support_snapshot") else {}
	var touch_side:int=int(last_decision.get("side",1)) if actor.foot.idle() else actor.foot.side
	var opposite:String=actor.avatar.side_suffix(-touch_side)
	var body_phases:Dictionary=support.get("support_phase",{}) if support.get("support_phase") is Dictionary else {}
	var planted:Dictionary=body_phases.get(opposite,{})
	var state:String="SUPPORT_STEP" if last_decision.get("position_first",false) else "FREE_ROLL"
	if not actor.foot.idle():
		state="RECOVER" if actor.foot.hit or actor.foot.phase==actor.foot.Phase.RECOVER else "INSIDE_CONTACT" if actor.foot.phase==actor.foot.Phase.CONTACT else "WEIGHT_SHIFT"
	var result:Dictionary={"phase":state,"support_side":opposite,"touch_side":touch_side,"surface":String(last_decision.get("surface","INSIDE")) if actor.foot.idle() else actor.foot.surface,"active":dominant_control_enabled and last_decision.get("intent","")=="CROSS_BODY_INSIDE" and (actor.foot.idle() or actor.foot.kind in ["CLOSE","TURN","SHIELD"]),"support_grounded":planted.get("state","")=="PLANTED" and bool(planted.get("sole_near_ground",false)),"support_knee_flexion_deg":planted.get("knee_flexion_deg",0.0),"support_leg_margin_m":planted.get("leg_margin_m",0.0),"pose_tick":support.get("pose_tick",-1),"position_first":last_decision.get("position_first",false),"dominant_side":last_decision.get("dominant_side",1)}
	if continuous_control_enabled and not step_intent.is_empty():
		result.merge(step_intent.duplicate(true),true)
		result["active"]=actor.is_human and last_decision.get("intent","")=="CROSS_BODY_INSIDE" and (actor.foot.idle() or actor.foot.kind in ["CLOSE","TURN","SHIELD"])
		if not actor.foot.idle():result["phase"]=state
	return result


func consider(actor: Node3D, ball: Node3D, aim: Vector3, mode: String, changed_direction: bool) -> Dictionary:
	if actor.is_human or DribbleRhythm.enabled(actor):
		return playable_plan(actor,ball,aim,mode,changed_direction)
	var run := Vector3(actor.velocity.x, 0, actor.velocity.z)
	var offset := Vector3(ball.position.x-actor.position.x, 0, ball.position.z-actor.position.z)
	var rolling := Vector3(ball.velocity.x, 0, ball.velocity.z)
	var low: bool = not actor.sprinting and not high_gear(actor)
	# Keep the released running branch while this narrow low-control batch is tested.
	if not low:
		if DribbleRhythm.enabled(actor):
			var need_running:bool=changed_direction or DribbleRhythm.needs_touch(actor,ball,aim)
			last_decision={"ready":need_running,"cadence_managed":false,"reason":"intercept_next_stride" if need_running else "roll_sufficient"}
			return last_decision
		last_decision = {"ready":true, "cadence_managed":false, "reason":"running_unchanged"}
		return last_decision
	# AI-safe roll needs no new shoe/support snapshot. Human path is unchanged.
	# Both ends of the conservative horizon stay inside the old rescue pocket.
	if not actor.is_human and DribbleRhythm.enabled(actor) and committed_sequence>=0 and not changed_direction:
		var end_offset := offset+(rolling-run)*.105
		if offset.length()<=.80 and end_offset.length()<=.80 and minf(offset.dot(aim),end_offset.dot(aim))>=ball.radius and not DribbleRhythm.needs_touch(actor,ball,aim):
			last_decision = {"ready":false,"cadence_managed":false,"reason":"roll_sufficient","ai_support_lazy":true}
			return last_decision
	var snapshot: Dictionary = {}
	if actor.avatar.has_method("get_control_support_snapshot"):
		snapshot = actor.avatar.call("get_control_support_snapshot")
	var phases: Dictionary = snapshot.get("support_phase",{}) if snapshot.get("support_phase") is Dictionary else {}
	if committed_side!=0:
		var prior_foot: Dictionary = phases.get(actor.avatar.side_suffix(committed_side),{})
		if prior_foot.get("state","")=="PLANTED" and bool(prior_foot.get("sole_near_ground",false)):
			recovered_to_stance = true
	var right := Vector3(-actor.body_facing.z,0,actor.body_facing.x)
	var push := aim.dot(right)
	# A stance-relative cross-body touch is a dominant INSIDE intent, not
	# an automatic outside touch by whichever foot lies along the input.
	# The current roster has no handedness field: explicit actor metadata can
	# override the right-foot default without changing model/profile files.
	var dominant := -1 if int(actor.get_meta("dominant_foot_side",1))<0 else 1
	var across_dominant: bool = dominant_control_enabled and actor.is_human and turn_stage.is_empty() and mode=="TURN" and push*dominant<-.5
	if not across_dominant: stance_started_tick = -1
	var pressure_side := 0
	if is_instance_valid(actor.match_controller):
		for opponent in actor.match_controller.players:
			if opponent==actor or opponent.team==actor.team: continue
			var threat: Vector3 = opponent.position-ball.position
			threat.y = 0
			if threat.length()<.65 and absf(threat.dot(right))>.10:
				pressure_side = int(signf(threat.dot(right)))
	var target: Vector3 = ball.position+ball.velocity*.035-aim*ball.radius
	var options: Array[Dictionary] = []
	for side in [-1,1]:
		var suffix: String = actor.avatar.side_suffix(side)
		var opposite: String = "R" if suffix=="L" else "L"
		var surface := "INSIDE"
		var foot_direction := aim
		if mode=="TURN":
			surface = "OUTSIDE"
			if absf(push)>.5:
				foot_direction = actor.body_facing
				surface = "OUTSIDE" if side==int(signf(push)) else "INSIDE"
		var socket: Dictionary = actor.avatar.get_foot_contact(side,surface)
		var travel: float = (socket.point+run*.035).distance_to(target)
		var limit := 6.5
		if actor.avatar.has_method("_foot_speed_limit"):
			limit = float(actor.avatar.call("_foot_speed_limit",suffix))
		var support: Dictionary = phases.get(opposite,{})
		var supported: bool = support.get("state","")=="PLANTED" and bool(support.get("sole_near_ground",false)) and float(support.get("leg_margin_m",0))>=0
		var possible: bool = travel <= limit*(.035+.070) and offset.length()<=ball.tuning.foot_reach+ball.radius
		# Prefer a real support base and the smaller upcoming shoe travel.
		# This does not force alternation, plant a foot or certify future IK.
		options.append({"side":side,"surface":surface,"foot_direction":foot_direction,"travel_m":travel,"supported":supported,"possible":possible,"recovered":side!=committed_side or recovered_to_stance,"score":travel-(.12 if supported else 0.0),"opposite_state":support.get("state","UNSPECIFIED"),"dominant_inside":across_dominant and side==dominant and surface=="INSIDE","pressure_exposed":pressure_side==side})
	options.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return float(a.score)<float(b.score))
	var selected: Dictionary = options[0]
	for option in options:
		if option.possible:
			selected = option
			break
	var lead_time: float = clampf(float(selected.travel_m)/6.5+.035,.035,.105)
	var predicted: Vector3 = offset+(rolling-run)*lead_time
	var ahead: float = predicted.dot(aim)
	var lateral: float = predicted.slide(aim).length()
	# Existing motor working pocket/follow threshold: do not schedule another
	# tap just because the old 120ms timer expired while the roll is sufficient.
	var need: bool = ahead<.28 or lateral>.20 or predicted.length()>.80
	if DribbleRhythm.enabled(actor):need=DribbleRhythm.needs_touch(actor,ball,aim)
	var urgent: bool = changed_direction or predicted.length()>.80 or (ahead<ball.radius and lateral<.20) or (committed_sequence<0 and (rolling-run).dot(aim)<-.25)
	for option in options:
		if option.possible and (option.supported or urgent or phases.is_empty()) and (option.recovered or urgent or phases.is_empty()):
			selected = option
			break
	if across_dominant and continuous_control_enabled:
		return _consider_continuous_inside(actor,ball,aim,snapshot,phases,options,need,urgent)
	if not across_dominant:step_intent.clear()
	# Apply preference only among immediately usable choices. Do not wait for
	# the dominant shoe, grow reach, or override a safe opposite-foot fallback.
	var preference := "geometry_support_fallback"
	if across_dominant:
		for option in options:
			var eligible: bool = option.possible and (option.supported or urgent or phases.is_empty()) and (option.recovered or urgent or phases.is_empty())
			var support_safe: bool = option.supported or not selected.supported or phases.is_empty()
			var close_cost: bool = float(option.travel_m)<=float(selected.travel_m)+.24
			if option.dominant_inside and eligible and support_safe and close_cost and not option.pressure_exposed:
				selected = option
				preference = "dominant_inside_reachable"
				break
	var position_first := false
	if across_dominant and pressure_side==0 and offset.length()<.70 and (rolling-run).length()<1.5:
		for option in options:
			if not option.dominant_inside: continue
			# Move the body now, while the ordinary locomotion support step lands.
			# At most one existing 105ms shoe preparation horizon is offered;
			# a rescue remains immediately available for pressure/escape/expiry.
			var near_window: bool = float(option.travel_m)<6.5*.16
			if near_window and (not option.supported or not option.possible or not option.recovered):
				if stance_started_tick<0: stance_started_tick=Engine.get_physics_frames()
				var elapsed_s: float = float(Engine.get_physics_frames()-stance_started_tick)/float(Engine.physics_ticks_per_second)
				position_first = elapsed_s<.105
				if position_first: selected=option;preference="support_step_body_then_inside"
			else:
				stance_started_tick=-1
			break
	var ready: bool = bool(selected.possible) and (need or urgent) and (bool(selected.supported) or urgent or phases.is_empty()) and (bool(selected.recovered) or urgent or phases.is_empty())
	if position_first: ready=false
	var reason := "ready" if ready else "roll_sufficient" if not need and not urgent else "shoe_outside_next_window" if not selected.possible else "recovery_wait" if not selected.recovered else "support_wait"
	if position_first: reason="position_for_dominant_inside"
	if ready and not selected.supported: reason = "responsive_prepare_transfer"
	last_decision = selected.duplicate()
	last_decision.merge({"ready":ready,"cadence_managed":true,"reason":reason,"urgent":urgent,"predicted_ahead_m":ahead,"predicted_lateral_m":lateral,"lookahead_s":lead_time,"captured_pose_tick":snapshot.get("pose_tick",-1),"options":options,"dominant_side":dominant,"intent": "CROSS_BODY_INSIDE" if across_dominant else "DIRECTIONAL_CONTROL","selection_reason":preference,"ball_lateral_m":offset.dot(right),"ball_forward_m":offset.dot(actor.body_facing),"body_facing":actor.body_facing,"pressure_side":pressure_side,"position_first":position_first},true)
	return last_decision

func note_commit(sequence: int, side: int, exit_velocity:Vector3=Vector3.ZERO) -> void:
	last_exit_velocity=exit_velocity
	stance_started_tick=-1
	if not step_intent.is_empty():step_intent["committed_sequence"]=sequence
	if last_decision.get("intent","")=="CROSS_BODY_INSIDE" and side==int(last_decision.get("dominant_side",1)):
		consumed_support_episode=int(last_decision.get("step_episode",-1))
	committed_sequence = sequence
	committed_side = side
	recovered_to_stance = false

func _consider_continuous_inside(actor:Node3D,ball:Node3D,aim:Vector3,snapshot:Dictionary,phases:Dictionary,options:Array[Dictionary],need:bool,urgent:bool)->Dictionary:
	var dominant:int=-1 if int(actor.get_meta("dominant_foot_side",1))<0 else 1
	var chosen:Dictionary={}
	var rescue:Dictionary={}
	for option in options:
		if option.side==dominant:chosen=option
		else:rescue=option
	var support_side:String=actor.avatar.side_suffix(-dominant)
	var support:Dictionary=phases.get(support_side,{})
	var sole:Dictionary=actor.avatar.get_foot_contact(-dominant,"SOLE")
	var sole_point:Vector3=sole.point
	var other_support:Dictionary=phases.get(actor.avatar.side_suffix(dominant),{})
	var hip:Vector3=((support.get("hip",actor.position) as Vector3)+(other_support.get("hip",actor.position) as Vector3))*.5
	var offset:Vector3=ball.position-actor.position;offset.y=0
	var run:Vector3=actor.velocity;run.y=0
	var rolling:Vector3=ball.velocity;rolling.y=0
	var right:Vector3=Vector3(-actor.body_facing.z,0,actor.body_facing.x)
	if step_intent.is_empty() or step_intent.has("committed_sequence") or (step_intent.aim as Vector3).dot(aim)<.75:
		step_serial+=1
		var step_length:float=clampf(run.length()*.20,.10,.20)
		step_intent={"serial":step_serial,"phase":"SUPPORT_STEP","support_side":support_side,"touch_side":dominant,"surface":"INSIDE","aim":aim,"support_origin_world":sole_point,"support_target_world":sole_point+aim*step_length,"body_origin_world":hip,"root_origin_world":actor.position,"soft_body_target_world":ball.position-right*(.06*dominant)-actor.body_facing*.28,"step_started":false,"step_complete":false,"support_advance_m":0.0,"body_advance_m":0.0,"ready_for_touch":false,"fallback_reason":""}
	var advance:float=(sole_point-(step_intent.support_origin_world as Vector3)).dot(aim)
	var body_advance:float=(hip-(step_intent.body_origin_world as Vector3)).dot(aim)
	var lifted:bool=support.get("state","")!="PLANTED" or sole_point.y>(step_intent.support_origin_world as Vector3).y+.012
	if lifted:step_intent.step_started=true
	var motion_step:Dictionary=snapshot.get("support_step",{}) if snapshot.get("support_step") is Dictionary else {}
	var episode:int=int(motion_step.get("episode",-1))
	var motion_ready:bool=motion_step.get("side","")==support_side and int(motion_step.get("touch_side",0))==dominant and motion_step.get("phase","")=="LANDED" and bool(motion_step.get("ready_for_touch",false)) and episode!=consumed_support_episode
	var stepped:bool=motion_ready
	step_intent.step_complete=stepped
	step_intent["support_step_feedback"]=motion_step.duplicate(true)
	step_intent["motion_episode"]=episode
	step_intent.support_advance_m=advance
	step_intent.body_advance_m=body_advance
	step_intent.support_planted=bool(chosen.supported)
	step_intent.touch_foot_recovered=bool(chosen.recovered)
	# A support phase by itself is insufficient: require the next actual sole
	# advance and body shift. Do not expire this intent into an alternating foot.
	var overlap:bool=DribbleRhythm.enabled(actor) and motion_step.get("phase","")=="SWING" and float(motion_step.get("elapsed",0.0))>=float(motion_step.get("load_s",.055))+float(motion_step.get("duration",.24))-.055 and episode!=consumed_support_episode
	# Prepare the striking shoe during the final support descent. Actual impact
	# still checks this same episode is really LANDED; no second body-shift wait.
	var coordinated:bool=(motion_ready or overlap) and bool(chosen.recovered) and (DribbleRhythm.enabled(actor) or body_advance>=.020)
	var escaping:bool=offset.length()>.78 or (rolling-run).dot(aim)>.80 and offset.dot(aim)>.30
	var fallback_reason:String="pressure" if bool(chosen.pressure_exposed) else "escaping_dominant_unreachable" if not bool(chosen.possible) and escaping else ""
	var fallback:bool=not fallback_reason.is_empty() and bool(rescue.possible) and (bool(rescue.supported) or urgent) and (bool(rescue.recovered) or urgent)
	if fallback:chosen=rescue
	var ready:bool=bool(chosen.possible) and (need or urgent) and (fallback or coordinated)
	var reason:String="ready" if ready else "roll_sufficient" if not need and not urgent else "body_position_for_inside" if not chosen.possible else "support_episode_consumed" if episode==consumed_support_episode and episode>=0 else "support_step_pending:"+str(motion_step.get("blocked_reason",motion_step.get("phase","NO_MOTION_INTERFACE"))) if not step_intent.step_complete else "body_shift_pending" if body_advance<.020 else "support_landing_pending" if not chosen.supported else "dominant_recovery_pending"
	step_intent.ready_for_touch=ready
	step_intent.fallback_reason=fallback_reason if fallback else ""
	step_intent.phase="SUPPORT_READY" if coordinated else "WEIGHT_SHIFT" if step_intent.step_complete else "SUPPORT_STEP"
	last_decision=chosen.duplicate()
	last_decision.merge({"ready":ready,"cadence_managed":true,"reason":reason,"urgent":urgent,"dominant_side":dominant,"intent":"CROSS_BODY_INSIDE","selection_reason":"rescue_"+fallback_reason if fallback else "persistent_dominant_inside","position_first":not ready and not fallback,"ball_lateral_m":offset.dot(right),"ball_forward_m":offset.dot(actor.body_facing),"captured_pose_tick":snapshot.get("pose_tick",-1),"options":options,"step_episode":episode,"support_overlap_s":maxf(0.0,float(motion_step.get("load_s",.055))+float(motion_step.get("duration",.24))-float(motion_step.get("elapsed",0.0))) if overlap else 0.0,"step_intent":step_intent.duplicate(true)},true)
	return last_decision

# Per-actor scalars; these helpers never sample or solve a skeleton.
var _direction_tick := -1
var _accepted_direction := Vector3.ZERO
var _candidate_direction := Vector3.ZERO
var _candidate_tick := -1
var _gear_tick := -1
var _gear_initialized := false
var _high_gear := false
var turn_stage := ""
var turn_aim := Vector3.ZERO
var turn_incoming := Vector3.ZERO
var _turn_tick := -1
var _turn_request := -1
var _brake_contact := false
var turn_reason := ""
var _rolling_cut047 := false
var _cut_lifted047 := 0
var _cut_landed047 := 0
# A real EXIT completes an input intent, not just one shoe animation.
var _completed_turn_aim046 := Vector3.ZERO
var _exit_root_target043 := Vector3.ZERO
var _exit_root_target_valid043 := false

func stable_direction(actor:Node3D)->Vector3:
	if actor.is_human:
		var current:Vector3=actor.get_ball_direction();current.y=0
		_accepted_direction=current.normalized() if current.length_squared()>.0001 else actor.body_facing
		return _accepted_direction
	var tick:int=Engine.get_physics_frames()
	if _direction_tick==tick:return _accepted_direction
	_direction_tick=tick
	var raw:Vector3=actor.get_ball_direction();raw.y=0
	if raw.length_squared()<.0001:raw=actor.body_facing
	raw=raw.normalized()
	if not actor.move_requested or actor.stop_requested>0 or actor.match_controller.ball.carrier!=actor:
		_accepted_direction=raw;_candidate_tick=-1
		return raw
	if _accepted_direction.length_squared()<.01:
		_accepted_direction=raw;_candidate_tick=-1
	elif raw.dot(_accepted_direction)>=cos(deg_to_rad(8.0)):
		_candidate_tick=-1 # Small aim corrections stay responsive.
		_accepted_direction=raw
	else:
		if _candidate_tick<0 or raw.dot(_candidate_direction)<cos(deg_to_rad(8.0)):
			_candidate_direction=raw;_candidate_tick=tick
		var dwell:float=float(tick-_candidate_tick)/float(Engine.physics_ticks_per_second)
		if dwell>=clampf(actor.match_controller.tuning.dribble_direction_debounce_seconds,.060,.080):
			_accepted_direction=raw;_candidate_tick=-1
	return _accepted_direction

func high_gear(actor:Node3D)->bool:
	var tick:int=Engine.get_physics_frames()
	if _gear_tick==tick:return _high_gear
	_gear_tick=tick
	var speed:float=Vector2(actor.velocity.x,actor.velocity.z).length()
	var enter:float=maxf(.01,actor.match_controller.tuning.dribble_high_enter_mps)
	var leave:float=clampf(actor.match_controller.tuning.dribble_high_exit_mps,0,enter-.01)
	if not _gear_initialized:_high_gear=speed>enter;_gear_initialized=true
	elif _high_gear:
		if speed<leave:_high_gear=false
	elif speed>enter:_high_gear=true
	return _high_gear

func reset_turn(actor:Node3D,reason:String)->void:
	if _turn_request>=0 and actor.avatar.has_method("cancel_dribble_steps040"):
		actor.avatar.cancel_dribble_steps040(_turn_request)
	turn_stage="";_turn_request=-1;_brake_contact=false;turn_reason=reason
	_exit_root_target_valid043=false
	_completed_turn_aim046=Vector3.ZERO
	_rolling_cut047=false;_cut_lifted047=0;_cut_landed047=0

func update_turn(actor:Node3D,ball:Node3D,aim:Vector3)->void:
	if actor.is_human:
		if not turn_stage.is_empty():reset_turn(actor,"input_owned_turn")
		return
	var run:Vector3=actor.velocity;run.y=0
	var rolling:Vector3=ball.velocity;rolling.y=0
	var eligible:bool=DribbleRhythm.turn_enabled(actor) and actor.move_requested and actor.stop_requested<=0 and not actor.shielding and not actor.close_control and ball.carrier==actor and not actor.foot.has_buffer() and (actor.foot.idle() or actor.foot.planned_dribble())
	if not eligible:
		reset_turn(actor,"authority_or_action_changed");return
	if not turn_stage.is_empty():
		if aim.dot(turn_aim)<.75 or float(Engine.get_physics_frames()-_turn_tick)/float(Engine.physics_ticks_per_second)>2.6:
			reset_turn(actor,"direction_changed_or_timeout");return
		if _rolling_cut047:
			# Cached physical sole lift -> planted transitions, using the same
			# floor/plant authority as core steps, not elapsed animation phases.
			var support_bits:int=actor.avatar.ordinary_support_bits047()
			_cut_lifted047|=support_bits>>2
			_cut_landed047|=(support_bits&3)&_cut_lifted047
		if turn_stage=="CUT90" and actor.foot.idle():
			var offset:Vector3=ball.position-actor.position;offset.y=0
			if (offset+(rolling-run)*.165).length()>.80:
				turn_stage="BRAKE";_rolling_cut047=false # Existing escape-pocket rescue.
		if turn_stage=="BRAKE" and _rolling_cut047 and _brake_contact and actor.foot.idle():
			turn_stage="CUT90"
		elif turn_stage=="BRAKE" and _brake_contact and actor.foot.idle() and run.length()<=.90 and rolling.length()<=.70:
			_turn_request=actor.avatar.request_dribble_steps040(turn_incoming,turn_aim)
			if _turn_request>=0:turn_stage="STEPS"
		elif turn_stage=="STEPS":
			var status:String=actor.avatar.dribble_steps_status040(_turn_request)
			if status=="COMPLETE":turn_stage="EXIT"
			elif status=="ABORT":reset_turn(actor,"landing_aborted")
		return
	# Same accepted input cannot reopen a completed transaction just because
	# the body still has the opposite setup velocity, including after shoe IDLE.
	if completed_direction046(aim):return
	_completed_turn_aim046=Vector3.ZERO
	# Keep the approved slow lateral/inside-support path unchanged.
	var turn_dot:float=run.normalized().dot(aim)
	var needs_two_steps:bool=high_gear(actor) and run.length()>1.85 and turn_dot<cos(deg_to_rad(75.0)) or run.length()>.55 and turn_dot<cos(deg_to_rad(135.0))
	if needs_two_steps and actor.avatar.has_method("request_dribble_steps040"):
		turn_stage="BRAKE";turn_aim=aim;turn_incoming=run.normalized()
		_turn_tick=Engine.get_physics_frames();_brake_contact=false;turn_reason="brake_before_two_landings"
		# Only the fast lateral entry is a rolling cut. Reversals and released
		# low/medium paths retain the explicit stopped two-step transaction.
		_rolling_cut047=run.length()>3.20 and turn_dot>=cos(deg_to_rad(135.0)) and absf(aim.dot(actor.body_facing))<.5
		_cut_lifted047=0;_cut_landed047=0

func completed_direction046(aim:Vector3)->bool:
	var flat:Vector3=aim;flat.y=0
	return _completed_turn_aim046.length_squared()>.01 and flat.length_squared()>.0025 and flat.normalized().dot(_completed_turn_aim046)>=cos(deg_to_rad(8.0))

func keep_incoming042(actor:Node3D,raw:Vector3)->bool:
	if actor.is_human:return false
	# SharedMovement must resume the normal follow motor, rather than preserve
	# the old setup velocity behind update_turn's completed-intent guard.
	if completed_direction046(raw):return false
	if not DribbleRhythm.turn_enabled(actor) or actor.stop_requested>0 or actor.foot.has_buffer() or not (actor.foot.idle() or actor.foot.planned_dribble()):return false
	if turn_stage=="BRAKE":return not _brake_contact
	if not turn_stage.is_empty() or raw.length_squared()<.0025:return false
	var run:Vector3=actor.velocity;run.y=0
	raw.y=0
	var turn_dot:float=run.normalized().dot(raw.normalized())
	return high_gear(actor) and run.length()>1.85 and turn_dot<cos(deg_to_rad(75.0)) or run.length()>.55 and turn_dot<cos(deg_to_rad(135.0))

func turn_motion(actor:Node3D)->Vector3:
	# Motor acceleration/collision still applies; no position or ball force write.
	if turn_stage=="STEPS":return turn_aim*.30
	if turn_stage=="EXIT":
		# Two landings may leave the ball across the hips. Reposition the PERSON
		# into the existing front pocket before accelerating along the exit aim.
		var offset:Vector3=actor.match_controller.ball.position-actor.position-actor.body_facing*.28
		# Lateral exit uses the admitted swing shoe's hip/socket geometry.
		# A ball-centred pocket can leave that hip on the wrong side of the ball.
		if _exit_root_target_valid043:offset=_exit_root_target043-actor.position
		offset.y=0
		if _exit_root_target_valid043:
			# Close the remaining lateral setup distance within a motor horizon,
			# capped at the existing slow two-step admission speed. Taper for the
			# actual profile's stopping distance instead of a fixed slow crawl.
			var distance:float=offset.length()
			var decel:float=maxf(.001,actor.profile.brake_deceleration_mps2)
			var pace:float=minf(.90,minf(distance/.18,sqrt(2.0*decel*distance)))
			return offset.normalized()*pace
		return (offset*2.0).limit_length(.60)
	if turn_stage=="BRAKE" and not _brake_contact:
		# Stay alongside the rolling ball until a REAL braking touch exists.
		# Stopping the body first made the locked interception recede every tick.
		var ball:Node3D=actor.match_controller.ball
		var run:Vector3=actor.velocity;run.y=0
		var offset:Vector3=ball.position-actor.position;offset.y=0
		var rolling:Vector3=ball.velocity;rolling.y=0
		var follow:float=maxf(0,rolling.dot(turn_incoming)+(offset.dot(turn_incoming)-.30)/.18)
		return turn_incoming*minf(run.length(),follow)
	return Vector3.ZERO

func note_turn_contact(actor:Node3D,stage:String)->void:
	if stage=="BRAKE" and turn_stage=="BRAKE":_brake_contact=true
	elif stage in ["EXIT","CUT90"] and turn_stage==stage:
		var completed_aim:Vector3=turn_aim
		reset_turn(actor,"exit_contact_confirmed")
		_completed_turn_aim046=completed_aim

func reserve_window(actor:Node3D,ball:Node3D,aim:Vector3,preparation:Dictionary,mode:String="CLOSE")->Dictionary:
	if actor.is_human or preparation.get("window_source","")=="input_reachable":return preparation
	if not actor.avatar.has_method("ordinary_gait_clock040"):return preparation
	# A dominant inside request already owns a predicted support-descent window;
	# keep its actual landing episode gate and its approved foot preference.
	if preparation.get("intent","")=="CROSS_BODY_INSIDE":return preparation
	# Only the already-near prospective toucher needs a current cached pose.
	# This uses the existing epoch guard; it does not force a second solve.
	if actor.has_method("ensure_contact_pose_current"):actor.ensure_contact_pose_current()
	var moving_window:bool=high_gear(actor) or not turn_stage.is_empty()
	# Free CUT/BRAKE scrubs the gait phase and owns support goals. Yield it before
	# predicting an ordinary strike. Explicit two-landing transactions never yield.
	if moving_window:actor.avatar.yield_ordinary_transition041()
	var clock:Dictionary=actor.avatar.ordinary_gait_clock040(moving_window)
	if turn_stage=="CUT90" and _cut_landed047!=3:
		return {"ready":false,"reason":"cut90_actual_support_transfer","cut_support_landed_mask":_cut_landed047}
	if clock.get("transition_active",false):
		return {"ready":false,"reason":"transition_owns_feet"}
	var rate:float=float(clock.get("signed_rate",clock.get("rate",0))) if moving_window else maxf(0,float(clock.get("rate",0)))
	var fraction:float=clampf(float(clock.get("fraction",.58)),.01,1.0)
	var phase:float=float(clock.get("phase",0))
	var run:Vector3=actor.velocity;run.y=0
	var sides:Array=[int(preparation.side)] if preparation.has("side") else [-1,1]
	if moving_window and sides.size()==1:sides.append(-int(sides[0]))
	var rejected:Dictionary={"phase":0,"actual_support":0,"support_leg":0,"touch_leg":0,"body_reach":0,"local_shoe_budget":0}
	var best:Dictionary={}
	var exit_position:Dictionary={}
	for candidate_side in sides:
		var shoe_side:int=int(candidate_side)
		var suffix:String=actor.avatar.side_suffix(shoe_side)
		var opposite:String=actor.avatar.side_suffix(-shoe_side)
		var surface:String=String(preparation.get("surface","INSIDE"))
		var shoe_direction:Vector3=preparation.get("foot_direction",aim)
		if moving_window and mode=="TURN":
			var right:Vector3=Vector3(-actor.body_facing.z,0,actor.body_facing.x)
			var push:float=aim.dot(right)
			surface="OUTSIDE"
			if absf(push)>.5:
				shoe_direction=actor.body_facing
				surface="OUTSIDE" if shoe_side==int(signf(push)) else "INSIDE"
		var socket:Dictionary=actor.avatar.get_foot_contact(shoe_side,surface)
		# Query the action that WILL run, not the previous idle action's limit.
		var limit:float=float(actor.avatar.LATERAL_TOUCH_FOOT_SPEED if mode=="TURN" else actor.avatar.GAIT_FOOT_SPEED) if moving_window else float(actor.avatar._foot_speed_limit(suffix))
		for sample in range(14):
			var eta:float=.035+float(sample)*.010
			var p:float=fposmod(phase+rate*eta+(.5 if suffix=="R" else 0.0),1.0)
			var support_p:float=fposmod(p+.5,1.0)
			var stationary:bool=run.length()<.12 and bool(clock.get("grounded_"+opposite,false))
			# Future opposite stance AND future free swing, with one-tick margin.
			var margin:float=absf(rate)/float(Engine.physics_ticks_per_second)
			var overlap:bool=support_p>=margin and support_p+margin<fraction and p>=fraction
			if not stationary and not overlap:
				rejected.phase+=1;continue
			# Do not lift the strike foot while the supposed support is still
			# releasing/airborne. Wait in gait; future phase alone is not a plant.
			if moving_window and not bool(clock.get("grounded_"+opposite,false)):
				rejected.actual_support+=1;continue
			var center:Vector3=predict_ball_center(ball,eta)
			var target:Vector3=center-aim*ball.radius
			var root_delta:Vector3=predict_root_delta041(actor,eta) if moving_window else run*eta
			if turn_stage=="EXIT" and mode=="TURN":
				# Only a phase-admitted shoe with real opposite support proposes a
				# BODY destination. Reuse the same cached geometry as the reach gate.
				var exit_reach:Dictionary=clock.get("reach_"+suffix,{})
				if not exit_reach.is_empty():
					var exit_ankle:Vector3=target-((socket.point as Vector3)-(exit_reach.ankle as Vector3))
					var shift:Vector3=exit_ankle-(exit_reach.hip as Vector3);shift.y=0
					if absf(exit_ankle.y-(exit_reach.hip as Vector3).y)<float(exit_reach.length) and (exit_position.is_empty() or shift.length_squared()<float(exit_position.cost)):
						exit_position={"target":actor.position+shift,"cost":shift.length_squared(),"side":shoe_side}
			if moving_window:
				var support_reach:Dictionary=clock.get("reach_"+opposite,{})
				if support_reach.is_empty() or ((support_reach.hip as Vector3)+root_delta).distance_to(support_reach.ankle)>float(support_reach.length):
					rejected.support_leg+=1;continue
			if turn_stage in ["EXIT","CUT90"]:
				# Reuse the two cached hip/ankle entries already read for support.
				# Socket offset is a planning estimate; actual IK/contact stays final.
				var touch_reach:Dictionary=clock.get("reach_"+suffix,{})
				if touch_reach.is_empty():
					rejected.touch_leg+=1;continue
				var ankle_target:Vector3=target-((socket.point as Vector3)-(touch_reach.ankle as Vector3))
				if ((touch_reach.hip as Vector3)+root_delta).distance_to(ankle_target)>float(touch_reach.length):
					rejected.touch_leg+=1;continue
			if (center-actor.position-root_delta).length()>ball.tuning.foot_reach+ball.radius:
				rejected.body_reach+=1;continue
			# The real servo bounds LOCAL ankle travel. Subtract root translation;
			# comparing world travel to 6.5m/s double-counted running speed.
			var shoe_start:Vector3=(socket.point as Vector3)+(root_delta if moving_window else Vector3.ZERO)
			if shoe_start.distance_to(target)>limit*eta*(.80 if moving_window else 1.0):
				rejected.local_shoe_budget+=1;continue
			if best.is_empty() or eta<float(best.contact_eta_s):
				best=preparation.duplicate()
				if moving_window:best["foot_direction"]=shoe_direction
				best.merge({"ready":true,"cadence_managed":true,"side":shoe_side,"surface":surface,"contact_eta_s":eta,"reserved_center":center,"future_support_phase":support_p,"future_swing_phase":p,"window_source":"cached_gait_prediction","reason":"future_support_swing_window"},true)
			break
	# The motor works toward a feasible future stance even when the CURRENT
	# support/touch reach rejects this reservation. No rejection is bypassed.
	if best.is_empty() and not exit_position.is_empty():
		_exit_root_target043=exit_position.target
		_exit_root_target_valid043=true
	if moving_window:
		if not best.is_empty():
			best["window_revision"]="local_servo_actual_support041"
			if turn_stage=="CUT90":best["cut_support_landed_mask"]=_cut_landed047
			best["reservation_rejections"]=rejected
		else:
			return {"ready":false,"reason":"await_actual_support_for_window" if int(rejected.actual_support)>0 else "future_window_unreachable","reservation_rejections":rejected,"signed_phase_rate":rate}
	return best if not best.is_empty() else {"ready":false,"reason":"future_window_unreachable"}

static func predict_root_delta041(actor:Node3D,eta:float)->Vector3:
	# Bounded first-order motor estimate, no solve or collision promise.
	var run:Vector3=actor.velocity;run.y=0
	var scheduler=actor.foot.ordinary_scheduler
	if scheduler.turn_stage in ["BRAKE","CUT90"] and scheduler._brake_contact:
		var speed:float=run.length()
		var decel:float=maxf(.001,actor.profile.brake_deceleration_mps2)
		var stop_time:float=minf(eta,speed/decel)
		return run.normalized()*(speed*stop_time-.5*decel*stop_time*stop_time)
	return run*eta

static func predict_ball_center(ball:Node3D,seconds:float)->Vector3:
	var flat:Vector3=ball.velocity;flat.y=0
	var speed:float=flat.length()
	if not ball.grounded or speed<.001:return ball.position+ball.velocity*seconds
	var loss:float=maxf(0,FootballBallForces.rolling_deceleration_mps2(speed,ball.profile))
	var travel_time:float=minf(seconds,speed/loss) if loss>.001 else seconds
	return ball.position+flat.normalized()*(speed*travel_time-.5*loss*travel_time*travel_time)

# One human planner owns the next contact estimate, including during recovery.
# Gait supplies preferences; it cannot veto a reachable directional input.
func playable_plan(actor:Node3D,ball:Node3D,aim:Vector3,mode:String,changed:bool)->Dictionary:
	var run:Vector3=actor.velocity;run.y=0
	var offset:Vector3=ball.position-actor.position;offset.y=0
	var follow:Dictionary=follow_step.consider(actor,ball,aim)
	if not follow.is_empty() and not bool(follow.ready):
		last_decision=follow
		return follow
	if Engine.get_physics_frames()<actor.foot.cut_roll_until and ball.carrier==actor and offset.length()<.95:
		return {"ready":false,"reason":"cut_free_roll"}
	var ready:bool=changed or DribbleRhythm.needs_touch(actor,ball,aim)
	# A completed follow can preserve the gap while both ball and body coast
	# to walking speed. Request the next legal touch to maintain intended pace;
	# never accelerate the ball between contacts or skip the completed step.
	var requested:float=ball.tuning.sprint_ball_speed if actor.sprinting else ball.tuning.normal_ball_speed
	if actor.close_control or actor.shielding:requested=ball.tuning.close_speed
	if not actor.is_human:requested=minf(requested,maxf(0.0,float(actor.ai_touch_pace)))
	var roll:=Vector3(ball.velocity.x,0,ball.velocity.z)
	var advancing:bool=aim.dot(actor.body_facing)>.65 and roll.length()>.35 and roll.normalized().dot(aim)>.85
	if not follow.is_empty() and bool(follow.ready) and advancing and requested>2.1 and roll.dot(aim)<requested-.55 and offset.length()<.75:
		ready=true
	var collecting:bool=actor.is_human and actor.gather_after_sprint and not actor.sprinting
	if collecting:ready=offset.length()<.55
	var wait:float=maxf(0.0,actor.foot.recovery_start()+actor.foot.recovery-actor.foot.elapsed) if actor.foot.planned_dribble() and actor.foot.hit else 0.0
	var right:Vector3=Vector3(-actor.body_facing.z,0,actor.body_facing.x)
	var lateral:float=offset.dot(right)
	var best:Dictionary={}
	# During follow-through, prefer the shoe whose opposite support is loaded.
	# This is a preference, not a hard landing gate for emergency recovery.
	var support_phases:Dictionary={}
	if not follow.is_empty():support_phases=actor.avatar.get_control_support_snapshot().get("support_phase",{})
	for shoe_side in [-1,1]:
		var surface:String="INSIDE"
		if aim.dot(right)*shoe_side>.25:surface="OUTSIDE"
		if collecting:surface="SOLE"
		var socket:Dictionary=actor.avatar.get_foot_contact(shoe_side,surface)
		var eta:float=.045
		for sample in range(3):
			var center:Vector3=predict_ball_center(ball,wait+eta)
			var point:Vector3=center+Vector3.UP*ball.radius if collecting else center-aim*ball.radius
			var travel:float=((socket.point as Vector3)+playable_root_delta(actor,run,wait+eta)).distance_to(point)
			eta=clampf(travel/6.5+.018,.045,.125)
		var center:Vector3=predict_ball_center(ball,wait+eta)
		var point:Vector3=center+Vector3.UP*ball.radius if collecting else center-aim*ball.radius
		var cost:float=((socket.point as Vector3)+playable_root_delta(actor,run,wait+eta)).distance_to(point)
		# Do not sweep a far shoe across the stance when the near one can act.
		if lateral*shoe_side<-.06:
			# Opposed lateral cuts use the shoe on the ball side, not a far
			# outside surface swept across both legs while the hips turn away.
			var rolling:Vector3=Vector3(ball.velocity.x,0,ball.velocity.z)
			cost+=.75 if actor.is_human and rolling.length()>1.5 and rolling.normalized().dot(aim)<-.5 else .22
		if shoe_side==committed_side:cost+=.045
		var support:Dictionary=support_phases.get(actor.avatar.side_suffix(-shoe_side),{})
		if support.get("state","")=="PLANTED" and bool(support.get("sole_near_ground",false)):cost-=.10
		if best.is_empty() or cost<float(best.cost):
			best={"ready":ready,"cadence_managed":true,"side":shoe_side,"surface":surface,"foot_direction":actor.body_facing,"contact_eta_s":eta,"reserved_center":center,"cost":cost,"window_source":"input_reachable","reason":"ready" if ready else "roll_sufficient","lookahead_s":wait+eta,"intent":"DIRECTIONAL_CONTROL"}
	if not follow.is_empty():best["follow_step"]=follow
	if actor.is_human and actor.gather_after_sprint and not actor.sprinting:
		best["surface"]="SOLE"
		best["follow_collect"]=true
	elif actor.is_human and actor.sprinting and changed:
		best["follow_cut"]=true
	last_decision=best
	return best

static func playable_root_delta(actor:Node3D,run:Vector3,seconds:float)->Vector3:
	if actor.is_human:return run*seconds
	# AI reservation used constant velocity while its actual motor was braking
	# or turning. Use the same integrator already used to budget its exit ball.
	var maximum:float=actor.motor_speed_limit(actor.sprint_intent)
	var desired:Vector3=actor.move_intent*maximum;desired.y=0
	return DribbleRhythm.TurnControl.predict_motor(run,desired,actor.profile,actor.sprint_intent,seconds).displacement
