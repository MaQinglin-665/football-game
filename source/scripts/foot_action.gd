class_name FootballFootAction
extends RefCounted
const DribbleRhythm := preload("res://scripts/dribble_rhythm.gd")
const PassChoice := preload("res://scripts/pass_contact_choice.gd")
var pass_choice:Dictionary={}
enum Phase { IDLE, PREPARE, CONTACT, RECOVER }
var actor: Node3D
var match_controller: Node
var phase := Phase.IDLE
var kind := ""
var elapsed := 0.0
var windup := .04
var window := .06
var recovery := .10
var direction := Vector3.FORWARD
var foot_direction := Vector3.FORWARD
var endpoint := Vector3.ZERO
# Standing tackle only: one locked shoe trajectory and one contact settlement.
var tackle_contact_consumed := false
var tackle_motion_blocked := false
var tackle_motion_blocked_elapsed := -1.0
var side := 1
var next_side := 1
var bias := Vector3.ZERO
var impulse := 3.5
var interval := .22
var hit := false
var attempted := false
var last_result := ""
var attempts := 0
var hits := 0
var misses := 0
var toe_world := Vector3.ZERO
var previous_toe := Vector3.ZERO
var surface := "INSTEP"
var kick_intent: Dictionary = {}
var receiver: Node3D
var buffer: Dictionary = {}
var buffer_time := 0.0
var start_local := Vector3.ZERO
var contact_target := Vector3.ZERO
var actual_contact: Dictionary = {}
var total_impulse_ns := Vector3.ZERO
var foul_reported := false
var restarting := false
var sequence := 0
var deliberate_touch := false
var heavy_scope: Dictionary = {}
var contact_failure := ""
var shot_style := "compact"
var action_trace: Array[Dictionary] = []
var contact_tick := -1
var failure_reported := false
var contact_elapsed := -1.0
var rolling_velocity_target := Vector3.ZERO
var rolling_target_ready := false
var rolling_contact_seconds := 0.0
var touch_plan: Dictionary = {}
const OrdinaryScheduler := preload("res://scripts/ordinary_touch_scheduler.gd")
var ordinary_scheduler := OrdinaryScheduler.new()
var cut_roll_until:int=-1
var release_until:Dictionary={} # Physics-frame deadlines, one per shoe.

func protects_shoe(shoe_side:int)->bool:
	if not idle() and side==shoe_side:return true
	return Engine.get_physics_frames()<int(release_until.get(shoe_side,-1))

func shared_ordinary_control() -> bool:
	return actor.is_human or "shared_last_result" in actor

func recovery_start() -> float:
	return float(touch_plan.get("recovery_start_elapsed",windup+window)) if planned_dribble() else windup+window

func trace_stage(stage: String, reason := "") -> void:
	action_trace.append({"stage":stage,"reason":reason,"sequence":sequence,"kind":kind,"elapsed":elapsed,"physics_frame":Engine.get_physics_frames()})
	if action_trace.size()>48: action_trace.pop_front()

func finish_failed(reason: String) -> void:
	if failure_reported or hit or kind!="SHOT": return
	failure_reported = true
	contact_failure = reason
	last_result = reason
	trace_stage("miss",reason)
	match_controller.report_foot_contact(actor,kind,toe_world,surface,match_controller.ball.velocity,match_controller.ball.velocity,false,{"action_sequence":sequence,"failure_reason":reason,"reach_error":actual_contact.get("reach_error",-1.0)})
	if actor.is_human:
		match_controller.message("球已离脚，靠近后再射" if reason in ["possession_changed","ownership_lost","outside_reach","buffer_expired"] else "射门被身体挡住" if reason=="body_blocked" else "未触到球，调整站位再射",1.3)

func continuous_control() -> bool:
	return shared_ordinary_control() and not deliberate_touch and kind in ["CLOSE","TURN","SHIELD","PULL"]

func _init(owner: Node3D, game: Node) -> void:
	actor = owner
	match_controller = game

func idle() -> bool:
	return phase==Phase.IDLE

func has_buffer() -> bool:
	return not buffer.is_empty()

func clear_buffer(reason := "cancelled") -> void:
	if not buffer.is_empty() and buffer.get("kind","")=="KICK" and String(buffer.intent.action).begins_with("pass_"):
		trace_stage("pass_cancelled",reason)
		if actor.is_human and reason in ["buffer_expired","buffer_context_changed","possession_changed"]:match_controller.message("传球预约已取消：球已离脚或等待超时，请重新按传球",1.3)
	if not buffer.is_empty() and buffer.kind=="KICK" and String(buffer.intent.action).begins_with("shoot_"):
		trace_stage("miss",reason)
		action_trace.back()["kind"] = "SHOT"
		action_trace.back()["intent_sequence"] = buffer.intent.get("sequence",0)
		contact_failure = reason
		last_result = reason
		if actor.is_human and reason!="cancelled": match_controller.message("射门等待已结束，靠近球后重按",1.3)
	if not buffer.is_empty() and bool(buffer.get("one_touch_pass",false)):
		last_result = reason
		if actor.is_human and reason in ["buffer_expired","receive_pass_unreachable","receive_pass_context_changed"]: match_controller.message("一脚传球预约取消，请重新传球",1.0)
	buffer.clear()

func begin(action: String, aim: Vector3, motion_bias := Vector3.ZERO, force := 3.5, period := .22, preparation: Dictionary = {}) -> bool:
	# Explicit standing challenge adopts the current unconsumed receive leg.
	# No ball/ownership mutation: a fresh real shoe contact is still required.
	var adopt_receive:bool=action=="TACKLE" and kind=="RECEIVE" and not hit
	if (not idle() and not adopt_receive) or not match_controller.can_foot_action(actor,action): return false
	if action not in ["CLOSE","TURN","SHIELD"]:ordinary_scheduler.reset_turn(actor,"other_action_priority")
	var cfg: FootballControlTuning = match_controller.tuning
	kind = action
	deliberate_touch = false
	sequence += 1
	elapsed = 0
	hit = false
	attempted = false
	foul_reported = false
	total_impulse_ns = Vector3.ZERO
	contact_failure = ""
	failure_reported = false
	contact_tick = -1
	contact_elapsed = -1.0
	rolling_target_ready = false
	rolling_contact_seconds = 0.0
	touch_plan.clear()
	pass_choice.clear()
	kick_intent.clear()
	heavy_scope.clear()
	direction = Vector3(aim.x,0,aim.z).normalized()
	if direction.length()<.1: direction = actor.facing
	foot_direction = direction
	if action in ["PULL","RECEIVE"]: foot_direction = actor.body_facing
	bias = motion_bias
	impulse = force
	interval = period
	surface = "SOLE" if action in ["STOP","SETTLE","PULL"] else "TOE" if action=="TACKLE" else "INSIDE" if action in ["PASS","RECEIVE","CLOSE","SHIELD"] else "OUTSIDE" if action=="TURN" else "INSTEP"
	side = next_side
	next_side = -next_side
	# Prefer the nearer foot during reception; deliberate kicks alternate.
	var side_center: Vector3 = preparation.get("tackle_center",match_controller.ball.position) if action=="TACKLE" else match_controller.ball.position
	var lateral := Vector3(-actor.facing.z,0,actor.facing.x).dot(side_center-actor.position)
	if action in ["RECEIVE","TACKLE","SHOT","PASS","STOP","SETTLE","PULL"] and absf(lateral)>.10: side = 1 if lateral>0 else -1
	if shared_ordinary_control() and action in ["CLOSE","SHIELD"] and absf(lateral)>.12:
		side = 1 if lateral>0 else -1
	if action=="SPRINT":
		var point := ball_surface(match_controller.ball.position)
		var left: Dictionary = actor.avatar.get_foot_contact(-1,"INSTEP")
		var right: Dictionary = actor.avatar.get_foot_contact(1,"INSTEP")
		side = -1 if (left.point as Vector3).distance_to(point)<(right.point as Vector3).distance_to(point) else 1
	if action=="TURN":
		var right := Vector3(-actor.body_facing.z,0,actor.body_facing.x)
		var push_side := direction.dot(right)
		if absf(push_side)>.5:
			# The shoe stays along the player's stance while its inside/outside
			# surface sends the ball sideways. Turning the whole shoe 90 degrees
			# made the old socket unreachable even though the input was correct.
			foot_direction = actor.body_facing
			if shared_ordinary_control() and absf(lateral)<.10:
				surface = "INSIDE"
				side = -1 if push_side>0 else 1
			elif lateral*push_side<(-.04 if shared_ordinary_control() else -.08):
				surface = "INSIDE"
				side = 1 if lateral>0 else -1
			else:
				surface = "OUTSIDE"
				side = 1 if push_side>0 else -1
	if action in ["CLOSE","TURN","SHIELD"] and bool(preparation.get("cadence_managed",false)):
		side = int(preparation.get("side",side))
		surface = String(preparation.get("surface",surface))
		foot_direction = preparation.get("foot_direction",foot_direction)
	if action in ["CLOSE","TURN","SHIELD"] and DribbleRhythm.braking_turn(actor,direction):
		foot_direction=actor.body_facing # Do not rotate the shoe 180 degrees to brake.
	windup = cfg.touch_prepare
	window = .075
	recovery = cfg.touch_recover
	if action=="TACKLE":
		surface=String(preparation.get("tackle_surface","INSIDE" if bool(preparation.get("intercept",false)) else "TOE"))
		foot_direction=preparation.get("tackle_foot_direction",actor.body_facing)
		tackle_contact_consumed = false
		tackle_motion_blocked = false
		tackle_motion_blocked_elapsed = -1.0
		windup = maxf(clampf(float(preparation.get("contact_eta_s",.09))*.55,.025,.07),float(preparation.get("tackle_travel_s",.025)))
		window = maxf(.12,float(preparation.get("contact_eta_s",.09))-windup+.085)
		recovery = .18
		attempts += 1
	elif action=="RECEIVE":
		windup = clampf(float(preparation.get("receive_eta",.045))*.45,.025,.075)
		window = clampf(float(preparation.get("receive_eta",.10))-windup+.10,.13,.24)
		recovery = .11
	elif action=="PULL":
		windup=.030
		window=.090
		recovery=cfg.retreat_recovery_seconds
	elif action in ["STOP","SETTLE"]:
		windup = .035
		window = .09
		recovery = .10
	elif action in ["PASS","SHOT"]:
		windup = .055 if action=="PASS" else .14
		window = .065
		recovery = .21 if action=="PASS" else .19
	elif action=="SPRINT":
		windup = .11
		window = .12
		recovery = .14
	elif shared_ordinary_control() and action in ["CLOSE","TURN","SHIELD"]:
		windup = .035
		window = .07
		recovery = .095 if actor.is_human else .115
		# A moving cushion needs enough real shoe travel time when the player
		# comes down from running pace. Keep contact eligibility unchanged.
		if Vector2(actor.velocity.x,actor.velocity.z).length()>cfg.normal_ball_speed+.3 and not actor.sprinting:
			window = .13
	if actor.is_human and action in ["CLOSE","TURN","SHIELD"] and preparation.has("support_overlap_s"):
		windup=maxf(windup,float(preparation.support_overlap_s))
	if shared_ordinary_control() and action in ["CLOSE","TURN","SHIELD"] and preparation.has("contact_eta_s"):
		windup=maxf(windup,float(preparation.contact_eta_s))
	if action=="TACKLE":
		var left:Dictionary=actor.avatar.get_foot_contact(-1,surface)
		var right:Dictionary=actor.avatar.get_foot_contact(1,surface)
		var aim_point:Vector3=ball_surface(side_center)
		side=-1 if (left.point as Vector3).distance_squared_to(aim_point)<(right.point as Vector3).distance_squared_to(aim_point) else 1
	if action=="TACKLE":side=int(preparation.get("tackle_side",side))
	if action=="PASS":
		var target_point:Vector3=ball_surface(match_controller.ball.position+match_controller.ball.velocity*windup)
		var left_cost:float=(actor.avatar.get_foot_contact(-1,surface).point as Vector3).distance_to(target_point)
		var right_cost:float=(actor.avatar.get_foot_contact(1,surface).point as Vector3).distance_to(target_point)
		if lateral>.10:left_cost+=.22
		elif lateral<-.10:right_cost+=.22
		side=-1 if left_cost<right_cost else 1
		next_side=-side
	var initial: Dictionary = actor.avatar.get_foot_contact(side,surface)
	start_local = initial.point-actor.position
	contact_target = ball_surface(match_controller.ball.position+match_controller.ball.velocity*windup)
	if shared_ordinary_control() and action in ["CLOSE","TURN","SHIELD"]:
		contact_target=ball_surface(preparation.get("reserved_center",OrdinaryScheduler.predict_ball_center(match_controller.ball,windup)))
	if action=="TACKLE":
		# Preparation carries a known observation, never a CONTACT-time homing target.
		var center: Vector3 = preparation.get("tackle_center",match_controller.ball.position)
		contact_target = preparation.get("tackle_point",ball_surface(center))
	if action=="RECEIVE":touch_plan={"receive_reach":float(preparation.get("receive_reach",1.08)),"receive_speed":match_controller.ball.velocity.length()}
	if action=="TACKLE":touch_plan={"intercept":bool(preparation.get("intercept",false)),"locked_center":preparation.get("tackle_center",match_controller.ball.position)}
	if action=="TACKLE":
		touch_plan["support_origin"]=actor.avatar.get_foot_contact(-side,"SOLE").point
		touch_plan["root_origin"]=actor.position
		touch_plan["start_world"]=initial.point
	endpoint = (contact_target-actor.position).limit_length(cfg.foot_reach)
	previous_toe = initial.point
	toe_world = initial.point
	phase = Phase.PREPARE
	if shared_ordinary_control() and action in ["CLOSE","TURN","SHIELD"]:
		touch_plan = {"sequence":sequence,"state":"PREPARE","foot":side,"surface":surface,"contact_point":contact_target,"normal":Vector3.ZERO,"contact_elapsed":-1.0,"exit_velocity":Vector3.ZERO,"support":control_support_snapshot(),"response_seconds":.035,"mode":action,"legacy_sole_receive":false}
		touch_plan["locked_prepare_target"]=contact_target
		touch_plan["turn_stage"]=preparation.get("turn_stage","")
		touch_plan["contact_eta_s"]=windup
		touch_plan["future_support_phase"]=preparation.get("future_support_phase",-1.0)
		touch_plan["future_swing_phase"]=preparation.get("future_swing_phase",-1.0)
		touch_plan["window_source"]=preparation.get("window_source","support_episode_or_direct")
		if DribbleRhythm.turn_enabled(actor):touch_plan["turn_entry_velocity"]=actor.velocity
		touch_plan["cadence_managed"] = bool(preparation.get("cadence_managed",false))
		touch_plan["dominant_cross_body"] = preparation.get("intent","")=="CROSS_BODY_INSIDE" and side==int(preparation.get("dominant_side",1)) and surface=="INSIDE"
		touch_plan["support_step_episode"]=int(preparation.get("step_episode",-1))
	restarting = match_controller.is_restart_taker(actor)
	last_result = "preparing"
	if action=="SHOT": trace_stage("windup")
	return true

func request_heavy_touch(aim: Vector3, context_epoch: int) -> bool:
	if match_controller.ball.carrier!=actor: return false
	if not begin("SPRINT",aim,aim*3.0,6.0,match_controller.tuning.sprint_interval): return false
	heavy_scope = {"actor":actor.get_instance_id(),"ball":match_controller.ball.get_instance_id(),"epoch":context_epoch}
	return true

func ball_surface(center: Vector3) -> Vector3:
	if surface=="SOLE": return center+Vector3.UP*match_controller.ball.radius
	var toward := direction
	if bias.length()>.2 and kind not in ["PASS","SHOT","TACKLE"]: toward = Vector3(bias.x,0,bias.z).normalized()
	if kind=="SPRINT" or kind=="PASS" and surface=="INSTEP":
		# A shoe instep lies above its sole on the turf. Reach a real point
		# slightly above the sphere's equator rather than asking its mesh to
		# sink into the floor; socket validity and distance checks still apply.
		var height := .035
		var radius: float = match_controller.ball.radius
		return center+Vector3.UP*height-toward*sqrt(maxf(0,radius*radius-height*height))
	var outward := -toward
	var run := Vector3(actor.velocity.x,0,actor.velocity.z)
	if continuous_control() and kind=="TURN" and run.length()>3.0 and run.normalized().dot(direction)<-.60:
		# A bounded point ON the same sphere makes the selected inside surface
		# reachable during fast reversal; no ball move, added reach or suction.
		var nearer := Vector3(actor.position.x-center.x,0,actor.position.z-center.z).slide(outward)
		if nearer.length()>.02: outward = outward*cos(deg_to_rad(30.0))+nearer.normalized()*sin(deg_to_rad(30.0))
	return center+outward*match_controller.ball.radius

func control_support_snapshot() -> Dictionary:
	# Optional readonly model interface. Missing data never delays an input.
	var snapshot: Dictionary = {}
	if actor.avatar.has_method("get_control_support_snapshot"):
		var supplied = actor.avatar.call("get_control_support_snapshot")
		if supplied is Dictionary: snapshot = supplied.duplicate(true)
	var run := Vector3(actor.velocity.x,0,actor.velocity.z)
	snapshot["velocity"] = run
	var acceleration = actor.get("motion_acceleration")
	snapshot["acceleration"] = acceleration if acceleration is Vector3 else Vector3.ZERO
	if not snapshot.has("support_phase"): snapshot["support_phase"] = "UNSPECIFIED"
	if not snapshot.has("body_yaw"): snapshot["body_yaw"] = atan2(-actor.body_facing.x,-actor.body_facing.z)
	snapshot["turn_intent"] = atan2(run.cross(direction).y,run.dot(direction)) if run.length()>.1 else 0.0
	return snapshot

func planned_dribble() -> bool:
	return continuous_control() and kind in ["CLOSE","TURN","SHIELD"] and not touch_plan.is_empty()

func pose_request() -> Dictionary:
	var progress := clampf(elapsed/maxf(windup+window+recovery,.001),0,1)
	var normalized := .5*elapsed/maxf(windup,.001) if phase==Phase.PREPARE else .5+.15*(elapsed-windup)/maxf(window,.001) if phase==Phase.CONTACT else .65+.35*(elapsed-recovery_start())/maxf(recovery,.001)
	var target := contact_target
	if kind in ["SHOT","PASS","RECEIVE"] and phase==Phase.PREPARE:
		# Predict from the current rolling ball, not the release-time position.
		contact_target = ball_surface(match_controller.ball.position+match_controller.ball.velocity*maxf(0,windup-elapsed))
		target = contact_target
	if phase==Phase.CONTACT and kind!="TACKLE" and (not hit or kind in ["RECEIVE","STOP","SETTLE","PULL"] or continuous_control()) and not planned_dribble():
		target = ball_surface(match_controller.ball.position)
		contact_target = target
	if kind=="TACKLE":
		# One forecast locked in world space. A presented block does not chase
		# the ball during CONTACT; only a real passing ball can strike it.
		target=contact_target
		if phase==Phase.CONTACT and not bool(touch_plan.get("intercept",false)):
			target+=direction*(clampf((elapsed-windup)/maxf(window,.001),0,1)*.06)
	var local := target-actor.position
	if kind!="SHOT": local = local.limit_length(float(touch_plan.get("receive_reach",match_controller.tuning.foot_reach)))
	target = actor.position+local
	# Keep the forecast world point; root motion must not cumulatively clamp it.
	if kind=="SHOT":
		var full := shot_style=="full"
		var origin := actor.position+start_local
		if phase==Phase.PREPARE:
			var t := clampf(elapsed/maxf(windup,.001),0,1)
			var back := origin-foot_direction*(.40 if full else .13)+Vector3.UP*(.18 if full else .045)
			if t<.38: target = origin.lerp(back,smoothstep(0,.38,t))
			else:
				var strike := smoothstep(.38,1,t)
				target = back.lerp(target,strike)+Vector3.UP*sin(PI*strike)*(.06 if full else .02)
		elif hit:
			var follow := clampf((elapsed-contact_elapsed)/.075,0,1)
			target = contact_target+(foot_direction*(.22 if full else .09)+Vector3.UP*(.16 if full else .045))*smoothstep(0,1,follow)
			if phase==Phase.RECOVER: target = target.lerp(origin,smoothstep(0,1,(elapsed-windup-window)/maxf(recovery,.001)))
		elif phase==Phase.RECOVER: target = target.lerp(origin,smoothstep(0,1,(elapsed-windup-window)/maxf(recovery,.001)))
	elif kind=="PASS":
		var origin:Vector3=actor.position+start_local
		var power:float=float(kick_intent.get("power",.3))
		var heel:bool=surface=="HEEL"
		var loft:bool=bool(pass_choice.get("loft",false))
		var swing:Vector3=direction
		var back_size:float=.11 if heel else lerpf(.16,.42 if loft else .30,power)
		if phase==Phase.PREPARE:
			var t:float=clampf(elapsed/maxf(windup,.001),0,1)
			var back:Vector3=origin-swing*back_size+Vector3.UP*(.035 if heel else .045+(.14 if loft else .06)*power)
			target=origin.lerp(back,smoothstep(0,.32,t)) if t<.32 else back.lerp(target,smoothstep(.32,1,t))
		elif hit:
			var follow:float=smoothstep(0,1,clampf((elapsed-contact_elapsed)/.09,0,1))
			target=contact_target+(swing*(.14 if heel else lerpf(.23,.36,power))+Vector3.UP*(.065 if heel else .18 if loft else .09))*follow
			if phase==Phase.RECOVER:target=target.lerp(origin,smoothstep(0,1,(elapsed-recovery_start())/maxf(recovery,.001)))
		elif phase==Phase.RECOVER:target=target.lerp(origin,smoothstep(0,1,(elapsed-recovery_start())/maxf(recovery,.001)))
	elif kind=="TACKLE" and touch_plan.has("withdraw_point"):
		var t:float=clampf((elapsed-float(touch_plan.withdraw_elapsed))/maxf(recovery,.001),0,1)
		var point:Vector3=touch_plan.withdraw_point
		var right:Vector3=Vector3(-foot_direction.z,0,foot_direction.x)
		var cleared:Vector3=point+(touch_plan.withdraw_away as Vector3)*.16+right*float(side)*.055+Vector3.UP*.07
		var stance:Vector3=actor.position+right*float(side)*.17+foot_direction*.035
		stance.y=point.y
		target=point.lerp(cleared,smoothstep(0,.55,t)) if t<.55 else cleared.lerp(stance,smoothstep(.55,1,t))
	elif (kind in ["STOP","SETTLE","PULL"] or touch_plan.has("cut_style")) and phase==Phase.RECOVER:
		var t:float=clampf((elapsed-recovery_start())/maxf(recovery,.001),0,1)
		var point:Vector3=touch_plan.get("release_point",contact_target)
		var right:=Vector3(-actor.body_facing.z,0,actor.body_facing.x)
		# Repeated retreating sole touches recover towards the next reachable
		# step, not all the way behind a ball that is still in front.
		var reach:float=.20 if kind=="PULL" and not deliberate_touch and actor.move_requested else .03
		var stance:Vector3=actor.position+right*float(side)*.16+actor.body_facing*reach
		stance.y=actor.position.y+.06
		var clear:Vector3=point+right*float(side)*.065+Vector3.UP*.065
		target=point.lerp(clear,smoothstep(0,.4,t)) if t<.4 else clear.lerp(stance,smoothstep(.4,1,t))
	elif planned_dribble() and hit:
		# World-space release first; return along the outside of this shoe's lane.
		# The action alone owns this path, including early ordinary recovery.
		var t:float=clampf((elapsed-float(touch_plan.contact_elapsed))/maxf(recovery,.001),0,1)
		var origin:Vector3=touch_plan.contact_point
		var right:Vector3=Vector3(-actor.body_facing.z,0,actor.body_facing.x)
		var away:Vector3=(touch_plan.release_normal as Vector3)*.13+right*float(side)*.09
		var cleared:Vector3=origin+away+Vector3.UP*.075
		var stance:Vector3=actor.position+right*float(side)*.16+actor.body_facing*.04
		stance.y=origin.y
		target=origin.lerp(cleared,smoothstep(0,.45,t)) if t<.45 else cleared.lerp(stance,smoothstep(.45,1,t))
	elif kind=="RECEIVE" and hit and touch_plan.has("receive_release_point"):
		var t:float=clampf((elapsed-float(touch_plan.receive_release_elapsed))/maxf(recovery,.001),0,1)
		var point:Vector3=touch_plan.receive_release_point
		var away:Vector3=touch_plan.receive_release_normal
		var right:Vector3=Vector3(-actor.body_facing.z,0,actor.body_facing.x)
		var cleared:Vector3=point+away*.10+right*float(side)*.035+Vector3.UP*.035
		var stance:Vector3=actor.position+Vector3(-actor.body_facing.z,0,actor.body_facing.x)*float(side)*.16
		stance.y=point.y
		target=point.lerp(cleared,smoothstep(0,.5,t)) if t<.5 else cleared.lerp(stance,smoothstep(.5,1,t))
	elif phase==Phase.PREPARE:
		var t:float=clampf(elapsed/maxf(windup,.001),0,1)
		target = (actor.position+start_local).lerp(target,smoothstep(0,1,t))
		if kind=="TACKLE":target+=Vector3.UP*sin(PI*t)*.035
		if kind in ["STOP","SETTLE","PULL"]:target+=Vector3.UP*sin(PI*t)*.045
		elif touch_plan.has("cut_style"):target-=direction*sin(PI*t)*.065
	elif phase==Phase.RECOVER: target = target.lerp(actor.position+start_local,smoothstep(0,1,(elapsed-windup-window)/maxf(recovery,.001)))
	return {"cut_style":touch_plan.get("cut_style",""),"receive_speed":touch_plan.get("receive_speed",0),"kind":kind,"phase":Phase.keys()[phase],"normalized_time":clampf(normalized,0,1),"side":side,"world_target":target,"strike_target":contact_target,"direction":foot_direction,"surface":surface,"power":float(kick_intent.get("power",.9 if kind=="SPRINT" else .3)),"progress":progress,"sequence":sequence,"contact_confirmed":hit,"contact_tick":contact_tick,"shot_style":shot_style,"support_origin":touch_plan.get("support_origin",Vector3.ZERO),"root_origin":touch_plan.get("root_origin",actor.position)}

func request_push(aim: Vector3) -> bool:
	if match_controller.ball.carrier!=actor: return false
	if not idle() or match_controller.flat_distance(actor.position,match_controller.ball.position)>.48:
		if kind in ["PASS","SHOT","TACKLE","SPRINT"]: return false
		buffer = {"kind":"PUSH","direction":aim.normalized(),"owner":match_controller.ball.carrier,"restart_id":match_controller.formation_serial}
		buffer_time = match_controller.tuning.big_touch_buffer_seconds
		return true
	return begin("SPRINT",aim,aim*3.0,6.0,match_controller.tuning.sprint_interval)

func request_stop() -> bool:
	if not idle() or actor.action_cooldown>0 or not match_controller.ball.can_kick(actor):
		if not idle() and kind in ["PASS","SHOT","TACKLE"]: return false
		if not can_schedule_kick():return false
		buffer = {"kind":"STOP","owner":match_controller.ball.carrier,"restart_id":match_controller.formation_serial}
		buffer_time = .26
		return true
	return begin("STOP",actor.get_ball_direction(),Vector3.ZERO,0,.22)

func request_cut(aim:Vector3)->bool:
	if match_controller.ball.carrier!=actor or not can_schedule_kick():return false
	if not idle():
		if kind in ["PASS","SHOT","TACKLE"]:return false
		if buffer.get("kind","")=="CUT":return false
		buffer={"kind":"CUT","direction":aim,"owner":match_controller.ball.carrier,"restart_id":match_controller.formation_serial}
		buffer_time=.34
		return true
	var forward:Vector3=actor.body_facing.normalized()
	var right:=Vector3(-forward.z,0,forward.x)
	var lateral:float=(match_controller.ball.position-actor.position).dot(right)
	var desired:Vector3=Vector3(aim.x,0,aim.z)
	if desired.length_squared()<.01 or absf(desired.normalized().dot(right))<.25:
		desired=-right*(1.0 if lateral>=0 else -1.0)+forward*.12
	desired=desired.normalized()
	var foot_side:int=(1 if lateral>0 else -1) if absf(lateral)>.07 else (-1 if desired.dot(right)>0 else 1)
	var part:String="INSIDE" if desired.dot(right)*foot_side<0 else "OUTSIDE"
	if not begin("TURN",desired,desired*2.4,3.8,.34,{"cadence_managed":true,"side":foot_side,"surface":part,"foot_direction":forward}):return false
	deliberate_touch=true
	touch_plan["cut_style"]="INSIDE_CUT" if part=="INSIDE" else "OUTSIDE_PUSH"
	windup=maxf(windup,.055);window=.10;recovery=.18
	contact_target=ball_surface(match_controller.ball.position+match_controller.ball.velocity*windup)
	return true

func request_nudge(aim: Vector3) -> bool:
	if idle():
		var accepted := begin("PULL" if aim.dot(actor.body_facing)<-.35 else "TURN",aim,aim*.85,1.2,match_controller.tuning.turn_interval)
		if accepted: deliberate_touch = true
		return accepted
	if kind in ["PASS","SHOT","TACKLE"]: return false
	# One next-touch slot; ownership/restart checks below cancel it immediately.
	# This is the foot scheduler, not the input module's pass micro-buffer.
	buffer = {"kind":"NUDGE","direction":aim.normalized(),"owner":match_controller.ball.carrier,"restart_id":match_controller.formation_serial}
	buffer_time = .24
	return true

func can_schedule_kick()->bool:
	var ball:Node3D=match_controller.ball
	if ball.can_pass(actor):return true
	if not actor.is_human or ball.carrier!=actor or ball.position.y>=.40 or not match_controller.can_reach_ball(actor):return false
	var offset:Vector3=ball.position-actor.position;offset.y=0
	var relative:Vector3=ball.velocity-actor.velocity;relative.y=0
	var eta:float=clampf(-offset.dot(relative)/maxf(relative.length_squared(),.01),0,.20)
	return offset.length()<1.28 and (offset+relative*eta).length()<.98 and offset.dot(actor.facing)>-.15

func request_semantic_kick(intent: Dictionary, _speed := 0.0, _lift := 0.0, target: Node3D = null) -> bool:
	var passing:bool=String(intent.action).begins_with("pass_")
	var legal_ball:bool=match_controller.ball.can_pass(actor) if passing else match_controller.ball.can_kick(actor)
	if passing and not bool(intent.get("one_touch_pass",false)) and actor.action_cooldown<=0 and match_controller.ball.can_kick(actor) and kind in ["CLOSE","TURN","SHIELD","CARRY","PULL"] and not hit:
		# A released deliberate pass takes the current ordinary preparation slot.
		# No second ball impulse and no waiting for the old dribble target to be struck.
		var old_side:int=side
		cancel("explicit_pass_preempts_ordinary_prepare")
		release_until[old_side]=Engine.get_physics_frames()+int(ceil(.10*Engine.physics_ticks_per_second))
	if kind in ["PASS","SHOT"] and hit and phase in [Phase.CONTACT,Phase.RECOVER]:cancel("next_kick_interrupts_follow_through")
	# A completed dribble touch need not hold a deliberate shot behind its
	# cosmetic recovery. The new swing starts at the actual current socket.
	if String(intent.action).begins_with("shoot_") and phase==Phase.RECOVER and kind in ["CARRY","CLOSE","SHIELD","TURN","SPRINT"]:
		cancel("shot_interrupt_recovery")
	if String(intent.action).begins_with("pass_") and hit and phase in [Phase.CONTACT,Phase.RECOVER] and kind in ["CARRY","CLOSE","SHIELD","TURN"]:
		cancel("explicit_pass_after_touch")
	if String(intent.action).begins_with("pass_") and kind=="RECEIVE" and hit and match_controller.ball.carrier==actor and match_controller.ball.can_kick(actor):
		cancel("pass_after_confirmed_receive")
	if bool(intent.get("one_touch_pass",false)):
		return _request_receive_pass(intent,target)
	if not idle() or actor.action_cooldown>0 or not legal_ball:
		if not idle() and kind in ["PASS","SHOT","TACKLE"]: return false
		if not can_schedule_kick():return false
		buffer = {"kind":"KICK","intent":intent.duplicate(true),"target":target,"owner":match_controller.ball.carrier,"restart_id":match_controller.formation_serial}
		buffer_time = .26
		trace_stage("queued",String(intent.action))
		return true
	var action := "PASS" if String(intent.action).begins_with("pass_") else "SHOT"
	if not legal_ball:return false
	var selected:Dictionary=PassChoice.choose(actor,match_controller.ball,intent) if passing else {}
	if passing and selected.is_empty():return false
	if not begin(action,intent.direction): return false
	actor.action_cooldown = .32 if action=="PASS" else .65
	kick_intent = intent.duplicate(true)
	if action=="PASS":_configure_pass(selected)
	receiver = target
	if action=="PASS":
		actor.stop_requested = 0.0
		trace_stage("inputaccepted","pass")
	if action=="PASS" and String(intent.action)=="pass_ground" and is_instance_valid(target):
		kick_intent["ground_pass_reference"] = target.position
		kick_intent["ground_pass_aim_offset"] = 0.0
	if action=="SHOT":
		var relative: Vector3 = match_controller.ball.position-actor.position
		var relative_speed: Vector3 = match_controller.ball.velocity-actor.velocity
		shot_style = "compact" if Vector2(relative.x,relative.z).length()<=.66 and Vector2(relative_speed.x,relative_speed.z).length()<1.8 else "full"
		# Forceful strikes use the full-body path for both human and AI; timing is unchanged.
		if float(intent.get("power",0))>=.55:shot_style="full"
		trace_stage("inputaccepted")
	return true

func _configure_pass(selected:Dictionary)->void:
	pass_choice=selected.duplicate(true)
	side=int(selected.side);surface=String(selected.surface);foot_direction=selected.foot_direction;next_side=-side
	kick_intent["contact_surface"]=surface;kick_intent["contact_side"]=side
	if surface=="HEEL":
		kick_intent.power=selected.power;kick_intent.elevation_deg=0.0
	windup=lerpf(.080,.115,float(kick_intent.get("power",0)))
	window=.085;recovery=.22
	start_local=(actor.avatar.get_foot_contact(side,surface).point as Vector3)-actor.position
	contact_target=ball_surface(match_controller.ball.position+match_controller.ball.velocity*windup)

func request_kick(action: String, aim: Vector3, power: float, lift: float, target: Node3D) -> bool:
	var normalized := clampf((power-3.5)/13.5,0,1) if action=="PASS" else clampf((power-9)/23,0,1)
	return request_semantic_kick({"action":"pass_ground" if action=="PASS" else "shoot_straight","direction":aim.normalized(),"power":normalized,"elevation_deg":rad_to_deg(atan2(lift,maxf(power,.1))),"spin":Vector3.ZERO},0,0,target)

func advance(delta: float) -> void:
	if kind=="PASS" and not hit and bool(kick_intent.get("one_touch_pass",false)) and not _receive_plan_current(kick_intent):
		cancel("receive_plan_superseded")
	if not buffer.is_empty() and bool(buffer.get("one_touch_pass",false)):
		if not _receive_plan_current(buffer.intent) or match_controller.phase!=match_controller.Phase.PLAY or not match_controller.can_foot_action(actor,"PASS") or buffer.get("ball_id",-1)!=match_controller.ball.get_instance_id() or buffer.get("generation",-1)!=match_controller.match_generation or buffer.get("epoch",-1)!=match_controller.input_bridge.authority_epoch:
			clear_buffer("receive_pass_context_changed")
	if not buffer.is_empty():
		buffer_time -= delta
		if buffer_time<=0 or buffer.owner!=match_controller.ball.carrier or int(buffer.restart_id)!=match_controller.formation_serial:
			if buffer_time<=0 and buffer.get("kind","")=="PUSH" and actor.is_human: match_controller.message("这脚未能触到球，请靠近后再大趟",1.4)
			clear_buffer("buffer_expired" if buffer_time<=0 else "buffer_context_changed")
	if idle() or (kind=="RECEIVE" and not hit and bool(buffer.get("one_touch_pass",false))):
		if not buffer.is_empty():
			if buffer.kind=="KICK" and not bool(buffer.get("one_touch_pass",false)) and (actor.action_cooldown>0 or not (match_controller.ball.can_pass(actor) if String(buffer.intent.action).begins_with("pass_") else match_controller.ball.can_kick(actor))):return
			if bool(buffer.get("one_touch_pass",false)):
				var receive_window := receive_pass_window()
				if receive_window.is_empty():
					clear_buffer("receive_pass_unreachable")
					return
				if float(receive_window.time_s)>.11: return
			if buffer.kind=="PUSH" and match_controller.flat_distance(actor.position,match_controller.ball.position)>.48: return
			var request := buffer.duplicate()
			buffer.clear()
			if request.kind=="STOP": request_stop()
			elif request.kind=="NUDGE": request_nudge(request.direction)
			elif request.kind=="CUT": request_cut(request.direction)
			elif request.kind=="PUSH": request_push(request.direction)
			else:
				var dispatched:bool=request_semantic_kick(request.intent,0,0,request.target)
				if not dispatched:
					trace_stage("dispatch_failed",String(request.intent.action))
					if actor.is_human:match_controller.message("传球未执行：当前脚下不可达或动作受阻",1.3)
		return
	if not match_controller.can_foot_action(actor,kind):
		cancel("permission_changed")
		return
	elapsed += delta
	var previous_phase := phase
	phase = Phase.PREPARE if elapsed<windup else Phase.CONTACT if elapsed<recovery_start() else Phase.RECOVER
	if kind in ["SHOT","PASS"] and previous_phase!=phase:
		trace_stage("contact_window" if phase==Phase.CONTACT else "recovery")
	if kind=="TACKLE" and phase==Phase.RECOVER and not touch_plan.has("withdraw_point"):begin_tackle_withdraw()
	if kind=="TACKLE" and not hit and phase in [Phase.PREPARE,Phase.CONTACT]:
		var next_pose:Dictionary=pose_request()
		if not match_controller.standing_tackle_motion_clear(self,next_pose.world_target):
			touch_plan["blocked_withdraw_tick"]=Engine.get_physics_frames()
			contact_failure="path_closed_before_extension"
			begin_tackle_withdraw()
	actor.refresh_pose(0)
	actual_contact = actor.avatar.get_foot_contact(side,surface)
	if phase==Phase.CONTACT and planned_dribble() and hit and bool(touch_plan.get("cadence_managed",false)) and not touch_plan.has("recovery_start_elapsed"):
		# Observe release with the actual socket. The model owns all ankle poses.
		var release_gap: float = actual_contact.point.distance_to(match_controller.ball.position)-match_controller.ball.radius
		if release_gap>float(touch_plan.get("contact_radial_gap_m",0.0))+.010:
			touch_plan["recovery_start_elapsed"] = elapsed
			touch_plan["release_observed_tick"] = Engine.get_physics_frames()
	previous_toe = toe_world
	toe_world = actual_contact.point
	if kind=="TACKLE" and not hit and phase in [Phase.PREPARE,Phase.CONTACT]:
		tackle_motion_blocked = false
		if not match_controller.standing_tackle_motion_clear(self):
			tackle_motion_blocked = true
			tackle_motion_blocked_elapsed = elapsed
			contact_failure = "body_blocked"
	if phase==Phase.CONTACT:
		if not hit or kind in ["RECEIVE","STOP","SETTLE","PULL"] or continuous_control(): _try_contact(delta)
	if kind=="TACKLE" and not hit and not foul_reported and (phase in [Phase.PREPARE,Phase.CONTACT] or int(touch_plan.get("blocked_withdraw_tick",-1))==Engine.get_physics_frames()):
		foul_reported = match_controller.observe_tackle_leg_contact(self,delta)
		if tackle_motion_blocked or foul_reported:begin_tackle_withdraw()
	if elapsed>=recovery_start()+recovery:
		if not hit:
			misses += 1
			last_result = "missed_contact"
			if kind=="PASS" and actor.is_human:
				trace_stage("pass_missed",contact_failure)
				match_controller.message("传球挥空：球未进入这一步的触球位置，请重新按传球",1.3)
			if kind=="SHOT": finish_failed(contact_failure if contact_failure!="" else "missed_contact")
			else: match_controller.report_foot_contact(actor,kind,toe_world,surface,match_controller.ball.velocity,match_controller.ball.velocity,false,{"action_sequence":sequence})
		var receive_after:bool=kind=="TACKLE" and hit and bool(touch_plan.get("defense_follow_receive",false))
		phase = Phase.IDLE
		kind = ""
		actor.avatar.clear_foot_action()
		if receive_after:
			var ball:Node3D=match_controller.ball
			if not is_instance_valid(ball.carrier) and match_controller.can_touch_ball(actor) and ball.position.y<.30 and match_controller.flat_distance(actor.position,ball.position)<.65 and (ball.velocity-actor.velocity).length()<3.0 and match_controller.can_reach_ball(actor):
				begin("RECEIVE",ball.position-actor.position,Vector3.ZERO,0,.18) # Must touch again to claim.


func visual_toe() -> Vector3:
	return toe_world

var physical_contact_sample:Dictionary={}

func resolve_physical_contact(shoe_side:int,point:Vector3,normal:Vector3,delta:float)->bool:
	var active_block:bool=kind in ["TACKLE","RECEIVE"] and phase==Phase.PREPARE and elapsed>=.008
	if (phase!=Phase.CONTACT and not active_block) or hit or shoe_side!=side or not (kind in ["RECEIVE","TACKLE"] or kind=="PASS" and bool(kick_intent.get("one_touch_pass",false))):return false
	if not match_controller.can_foot_action(actor,kind):return false
	var ball:Node3D=match_controller.ball
	if ball.position.y>.46 or point.distance_to(ball.position)>ball.radius+.04:return false
	var physical_reach:float=float(touch_plan.get("receive_reach",1.08))+.015 if kind=="RECEIVE" else match_controller.tuning.tackle_reach
	if match_controller.flat_distance(actor.position,ball.position)>physical_reach+ball.radius:return false
	if active_block:
		windup = elapsed
		phase = Phase.CONTACT
	# This proof exists only on the call stack of World.move_and_collide.
	physical_contact_sample={"center":ball.position,"point":point,"normal":normal,"fraction":1.0,"gap":point.distance_to(ball.position)}
	var socket:Vector3=toe_world
	toe_world=point
	_try_contact(delta)
	toe_world=socket
	physical_contact_sample.clear()
	return hit

func _try_contact(delta: float) -> void:
	if kind=="TACKLE" and tackle_motion_blocked:
		contact_failure = "body_blocked"
		return
	var ball: MatchFootball = match_controller.ball
	if kind=="PASS" and not pass_choice.is_empty() and not PassChoice.still_legal(actor,ball,pass_choice):
		contact_failure="selected_pass_unreachable"
		return
	var rolling_touch := planned_dribble()
	if touch_plan.has("cut_style") and hit:return
	if rolling_touch and hit: return
	if kind=="PASS" and bool(kick_intent.get("one_touch_pass",false)) and not _receive_plan_current(kick_intent):
		contact_failure = "receive_plan_superseded"
		return
	if kind=="RECEIVE" and not ball.receive_ab_legacy and hit: return
	if not heavy_scope.is_empty() and (heavy_scope.actor!=actor.get_instance_id() or heavy_scope.ball!=ball.get_instance_id() or heavy_scope.epoch!=match_controller.input_bridge.authority_epoch): return
	if kind=="SHOT" and not actor.avatar.planted_support.get("valid",false) and not (bool(actor.avatar.planted_support.get("planted",false)) and absf((actor.avatar.planted_support.get("point",Vector3.UP) as Vector3).y-actor.position.y)<.09):
		contact_failure = "support_not_ready"
		return
	var tackle_sample:Dictionary=match_controller.standing_tackle_contact_sample(self) if kind=="TACKLE" else {}
	var kick_fit:bool=kind in ["PASS","SHOT"] and float(actual_contact.get("reach_error",1.0))<=.075 and toe_world.distance_to(ball.position)<=ball.radius+.065
	var assisted:bool=kick_fit or (not tackle_sample.is_empty() if kind=="TACKLE" else rolling_touch and actor.is_human and float(actual_contact.get("reach_error",1.0))<=.10 and toe_world.distance_to(ball.position)<=ball.radius+.10)
	if not actual_contact.get("valid",false) and not assisted and physical_contact_sample.is_empty():
		contact_failure = "foot_unreachable"
		return
	if ball.position.y>.46:
		contact_failure = "ball_too_high"
		return
	if kind=="RECEIVE" and is_instance_valid(ball.carrier) and ball.carrier!=actor: return
	var one_touch_contact: bool = kind=="PASS" and bool(kick_intent.get("one_touch_pass",false)) and not is_instance_valid(ball.carrier)
	if one_touch_contact and physical_contact_sample.is_empty() and not actor.avatar.planted_support.get("valid",false):
		contact_failure = "support_not_ready"
		return
	if kind not in ["TACKLE","RECEIVE"] and ball.carrier!=actor and not restarting and not one_touch_contact:
		contact_failure = "ownership_lost"
		return
	if kind!="TACKLE" and not match_controller.can_reach_ball(actor):
		contact_failure = "body_blocked"
		return
	if planned_dribble() and touch_plan.get("window_source","")=="cached_gait_prediction":
		# Prediction schedules the swing; only actual cached ground support admits impact.
		var clock040:Dictionary=actor.avatar.ordinary_gait_clock040()
		if not bool(clock040.get("grounded_"+actor.avatar.side_suffix(-side),false)):
			contact_failure="predicted_support_not_landed"
			return
	if planned_dribble() and bool(touch_plan.get("dominant_cross_body",false)):
		var support_snapshot: Dictionary = control_support_snapshot()
		var support_foot: Dictionary = support_snapshot.get("support_phase",{}).get(actor.avatar.side_suffix(-side),{})
		if not support_foot.is_empty() and (support_foot.get("state","")!="PLANTED" or not bool(support_foot.get("sole_near_ground",false)) or float(support_foot.get("leg_margin_m",0.0))<0):
			contact_failure="support_transfer_not_ready"
			return
		var admitted_episode:int=int(touch_plan.get("support_step_episode",-1))
		if admitted_episode>=0:
			var step_feedback:Dictionary=support_snapshot.get("support_step",{})
			if step_feedback.get("phase","")!="LANDED" or not bool(step_feedback.get("ready_for_touch",false)) or int(step_feedback.get("episode",-1))!=admitted_episode:
				contact_failure="support_step_changed_before_contact"
				return
	var closest := Geometry3D.get_closest_point_to_segment(toe_world,ball.position,ball.position+ball.velocity*delta)
	var contact_margin:float=.10 if rolling_touch and actor.is_human else .055
	if physical_contact_sample.is_empty() and (kind=="TACKLE" and tackle_sample.is_empty() or kind!="TACKLE" and (absf(closest.distance_to(toe_world)-ball.radius)>contact_margin or toe_world.distance_to(ball.position)>ball.radius+contact_margin+.01)):
		contact_failure = "outside_reach"
		return
	var before: Vector3 = ball.velocity
	var success := false
	var control_claimed := false
	if kind=="TACKLE":
		contact_failure = ""
		success = match_controller.resolve_tackle_contact(actor,direction,toe_world)
		if success:
			begin_tackle_withdraw()
			release_until[side]=Engine.get_physics_frames()+int(ceil(.18*Engine.physics_ticks_per_second))
			hits += 1
	elif kind in ["PASS","SHOT"]:
		if kind=="PASS" and kick_intent.has("space_target"):
			var target:Vector3=kick_intent.space_target
			if match_controller.tactical_director.clock>float(kick_intent.space_valid_until) or ball.position.distance_to(kick_intent.space_origin)>1.5:
				contact_failure="space_pass_expired"
				return
			var aim:Vector3=target-ball.position;aim.y=0
			if aim.length()<2.0 or aim.normalized().dot(direction)<.85:
				contact_failure="space_pass_changed"
				return
			kick_intent.direction=aim.normalized()
			if String(kick_intent.action)=="pass_ground":kick_intent.power=preload("res://addons/football_ground_pass/ground_pass_solution.gd").power_for_distance(aim.length(),match_controller.physics_profile)
		if kind=="PASS" and not kick_intent.has("space_target") and not restarting and String(kick_intent.get("action",""))=="pass_ground" and is_instance_valid(receiver) and (not actor.is_human or match_controller.assist) and match_controller.physics_profile.ground_pass_distance_mapping_enabled:
			var solution := preload("res://addons/football_ground_pass/ground_pass_solution.gd")
			kick_intent = solution.solve(ball.position,receiver.position,receiver.velocity,kick_intent,kick_intent.get("ground_pass_reference",receiver.position),match_controller.physics_profile)
		if kind=="PASS" and surface=="HEEL":
			var final_aim:Vector3=kick_intent.direction
			if final_aim.dot(direction)<.85:
				contact_failure="heel_outlet_changed";return
			kick_intent.power=minf(float(kick_intent.power),.16);kick_intent.elevation_deg=0.0
		success = match_controller.on_kick_contact(actor,kind,kick_intent,receiver,restarting,toe_world,sequence)
	elif kind in ["RECEIVE","STOP","SETTLE","PULL"] or continuous_control():
		var target_velocity := Vector3.ZERO if kind in ["STOP","SETTLE"] else Vector3(actor.velocity.x,0,actor.velocity.z)*.82
		var receive_outlet:=Vector3.ZERO
		if kind=="RECEIVE" and not ball.receive_ab_legacy:
			# Shoe geometry retains the radial aim. Exit motion reads the actor's
			# actual command; an idle player cushions rather than inventing a lead.
			target_velocity = Vector3.ZERO
			var planned_outlet := Vector3.ZERO
			if not actor.is_human and actor.has_method("planned_receive_direction"):
				planned_outlet = actor.planned_receive_direction()
			if actor.move_requested or planned_outlet.length_squared()>.01:
				var receive_direction: Vector3 = planned_outlet if planned_outlet.length_squared()>.01 else actor.get_ball_direction()
				receive_direction.y = 0
				if receive_direction.length()>.05:
					target_velocity=preload("res://scripts/receive_contact.gd").lead_velocity(ball,actor,receive_direction)
			# One bounded impulse at this real shoe contact, using actual dt.
			# Compensate relaxation; buffer_contact still enforces its force cap.
			receive_outlet=target_velocity
			var duration := minf(delta,1.0/60.0)
			var gain := 1.0 if ball.profile.receiver_relaxation_time_s<=0 else 1.0-exp(-duration/ball.profile.receiver_relaxation_time_s)
			target_velocity = before+(target_velocity-before)/maxf(gain,.001)
		if shared_ordinary_control() and kind in ["STOP","SETTLE"]:
			target_velocity = ball.stopping_touch_velocity(actor)
		elif kind=="PULL" and deliberate_touch:
			target_velocity = Vector3(actor.velocity.x,0,actor.velocity.z)*.5+direction*.85
		elif continuous_control():
			# A direction change cushions the outgoing roll with the shoe that
			# is already touching it; the next scheduled shoe supplies the new
			# directional lead. Do not keep pushing the old input for a cycle.
			if rolling_touch:
				if not rolling_target_ready:
					var accepted_aim:Vector3=ordinary_scheduler.stable_direction(actor)
					if DribbleRhythm.can_steer(actor,accepted_aim):
						# Solve the changed result ONCE at this actual shoe contact.
						# Do not cancel preparation, move the contact point, change feet,
						# add another impulse or redirect a ball already released.
						var outgoing_aim:Vector3=accepted_aim
						rolling_velocity_target=ball.close_touch_velocity(actor,outgoing_aim,kind)
						touch_plan["rhythm_original_direction"]=direction
						touch_plan["rhythm_steered_direction"]=outgoing_aim
					else:
						rolling_velocity_target = ball.close_touch_velocity(actor,direction,kind) if touch_plan.get("turn_stage","")=="BRAKE" else ball.stopping_touch_velocity(actor) if direction.dot(accepted_aim)<.75 else ball.close_touch_velocity(actor,direction,kind)
					rolling_target_ready = true
				target_velocity = rolling_velocity_target
			else:
				target_velocity = ball.stopping_touch_velocity(actor) if direction.dot(actor.get_ball_direction())<.75 else ball.close_touch_velocity(actor,direction,kind)
		elif kind=="PULL":
			var radial := Vector3(ball.position.x-actor.position.x,0,ball.position.z-actor.position.z)
			target_velocity = Vector3(actor.velocity.x,0,actor.velocity.z)-radial.normalized()*clampf((radial.length()-.52)*2.0,0,1.2)
		var contact_duration := minf(delta,.035-rolling_contact_seconds) if rolling_touch else delta
		var result: Dictionary
		if rolling_touch: result = ball.commit_dribble_result(actor,target_velocity,toe_world,float(touch_plan.response_seconds),interval)
		elif kind=="RECEIVE" and not ball.receive_ab_legacy:
			var normal:Vector3=physical_contact_sample.get("normal",(ball.position-toe_world).normalized())
			result=preload("res://scripts/receive_contact.gd").settle(ball,actor,toe_world,normal,receive_outlet,side)
		else: result = ball.buffer_contact(toe_world,target_velocity,1.0,contact_duration)
		success = result.get("accepted",false)
		if success:
			contact_failure=""
			if kind=="RECEIVE" and ball.carrier!=actor and ball.reception_ready(actor):
				ball.take(actor)
				control_claimed = true
			ball.record_touch(actor,before,interval,kind,toe_world,not continuous_control() or not hit)
			if kind=="RECEIVE":
				window=maxf(0,elapsed-windup)
				touch_plan["receive_exit_velocity"]=ball.velocity
				touch_plan["receive_release_point"]=toe_world
				touch_plan["receive_release_normal"]=(toe_world-ball.position).normalized()
				touch_plan["receive_release_elapsed"]=elapsed
				release_until[side]=Engine.get_physics_frames()+int(ceil(.14*Engine.physics_ticks_per_second))
			if rolling_touch:
				rolling_contact_seconds = float(touch_plan.response_seconds)
				touch_plan.merge({"state":"FREE_ROLL","desired_velocity":rolling_velocity_target,"contact_point":toe_world,"contact_local":toe_world-actor.position,"release_normal":(toe_world-ball.position).normalized(),"normal":actual_contact.normal,"contact_elapsed":elapsed,"exit_velocity":ball.velocity},true)
				touch_plan["contact_radial_gap_m"] = maxf(0.0,toe_world.distance_to(ball.position)-ball.radius)
				if not actor.is_human:
					ordinary_scheduler.note_commit(sequence,side,ball.velocity)
				if actor.is_human:
					touch_plan["recovery_start_elapsed"]=elapsed
					release_until[side]=Engine.get_physics_frames()+int(ceil((recovery+.045)*Engine.physics_ticks_per_second))
				ordinary_scheduler.note_commit(sequence,side,ball.velocity)
				ordinary_scheduler.note_turn_contact(actor,String(touch_plan.get("turn_stage","")))
			if kind=="STOP":
				actor.sole_stopped = true
				if actor.is_human: match_controller.message("脚底停球",.8)
	else:
		var desired := Vector3(actor.velocity.x,0,actor.velocity.z)+bias
		if touch_plan.has("cut_style"):desired=Vector3(actor.velocity.x,0,actor.velocity.z)+direction*2.4
		if kind=="SPRINT": desired = direction*clampf(maxf(Vector2(actor.velocity.x,actor.velocity.z).length()+3.0,match_controller.tuning.big_touch_speed),6.0,9.2)
		success = ball.apply_foot_contact(actor,desired,impulse,interval,kind,toe_world)
	if not success:
		if kind!="TACKLE" or contact_failure=="": contact_failure = "kick_rejected"
		return
	total_impulse_ns += (ball.velocity-before)*ball.mass_kg
	if not hit or control_claimed:
		match_controller.report_foot_contact(actor,kind,toe_world,surface,before,ball.velocity,true,{"action_sequence":sequence,"restart_contact":restarting,"receiver":receiver,"reach_error":actual_contact.reach_error,"contact_normal":actual_contact.normal})
	if not hit or not rolling_touch:
		# AI, reception, sole and shots retain their original contact stamps.
		contact_tick = Engine.get_physics_frames()
		contact_elapsed = elapsed
	hit = true
	if touch_plan.has("cut_style"):
		cut_roll_until=Engine.get_physics_frames()+int(ceil(.34*Engine.physics_ticks_per_second))
		release_until[side]=cut_roll_until
	if kind in ["STOP","SETTLE","PULL"] or touch_plan.has("cut_style"):touch_plan["release_point"]=toe_world
	if kind in ["SHOT","PASS"]: contact_target = toe_world
	contact_failure = ""
	if kind in ["SHOT","PASS"]: trace_stage("ballimpulse")
	attempted = true
	last_result = "contact"
	# Publish the real touch before possession context cancels this action.
	# Otherwise push_free -> sync_context erased kind before audio/QA saw it.
	if kind=="SPRINT": ball.push_free(actor)

func movement_cap() -> float:
	if touch_plan.has("cut_style") and not idle() and phase!=Phase.RECOVER:return 3.2
	if kind=="PASS" and hit and phase==Phase.RECOVER: return 100
	if kind=="PASS" and not idle():return 4.8
	if kind=="SHOT" and not idle(): return 1.3
	if kind in ["STOP","SETTLE"] and not idle(): return .45
	if kind=="PULL" and not idle(): return 1.4 if deliberate_touch else 100.0 # Automatic sole carry follows the shared motor budget in every phase.
	if kind!="TACKLE" or idle(): return 100
	return maxf(2.4,minf(4.2,Vector2(actor.velocity.x,actor.velocity.z).length())) if phase!=Phase.RECOVER else 100.0 # Withdraw while chasing; no post-miss crawl.

func cancel(reason := "cancelled") -> void:
	ordinary_scheduler.reset_turn(actor,reason)
	ordinary_scheduler._candidate_tick=-1
	ordinary_scheduler._accepted_direction=Vector3.ZERO
	ordinary_scheduler._direction_tick=-1
	finish_failed(reason)
	clear_buffer(reason)
	heavy_scope.clear()
	touch_plan.clear()
	pass_choice.clear()
	kick_intent.clear()
	phase = Phase.IDLE
	kind = ""
	elapsed = 0
	restarting = false
	if is_instance_valid(actor.avatar): actor.avatar.clear_foot_action()


func has_receive_pass() -> bool:
	return bool(buffer.get("one_touch_pass",false)) or (kind=="PASS" and not hit and bool(kick_intent.get("one_touch_pass",false)))

func receive_pass_window() -> Dictionary:
	var ball: MatchFootball = match_controller.ball
	if match_controller.phase!=match_controller.Phase.PLAY or absf(ball.position.x)>match_controller.field_half_width or absf(ball.position.z)>match_controller.field_half_length: return {}
	if is_instance_valid(ball.carrier) or ball.held or ball.pickup_block>0 or not match_controller.can_foot_action(actor,"PASS"): return {}
	if not idle() and not (kind=="RECEIVE" and not hit): return {}
	if ball.position.y>.30 or absf(ball.velocity.y)>1.0: return {}
	var offset := Vector3(ball.position.x-actor.position.x,0,ball.position.z-actor.position.z)
	var relative := Vector3(ball.velocity.x-actor.velocity.x,0,ball.velocity.z-actor.velocity.z)
	if offset.length()<.18 or offset.length()>3.2 or relative.length()<.8 or relative.length()>17.0: return {}
	if offset.normalized().dot(actor.body_facing)<.15 or not match_controller.can_reach_ball(actor): return {}
	var closing := -relative.dot(offset.normalized())
	if closing<.8: return {}
	var time_s := maxf(0.0,(offset.length()-.44)/closing)
	var point := offset+relative*time_s
	if time_s>.35 or point.length()>.72 or point.length()<.18 or point.normalized().dot(actor.body_facing)<.15: return {}
	return {"time_s":time_s,"point":point}

func _request_receive_pass(intent: Dictionary, target: Node3D) -> bool:
	if not String(intent.get("action","")).begins_with("pass_") or not _receive_plan_current(intent): return false
	var aim: Vector3 = intent.get("direction",Vector3.ZERO)
	if not aim.is_finite() or aim.length_squared()<.001 : return false
	var timing := receive_pass_window()
	if timing.is_empty(): return false
	if bool(buffer.get("one_touch_pass",false)):
		var identity := str(intent.get("one_touch_id",intent.get("gesture_id",intent.get("sequence",""))))
		var previous := str(buffer.intent.get("one_touch_id",buffer.intent.get("gesture_id",buffer.intent.get("sequence",""))))
		if (identity!="" and identity==previous) or buffer.intent==intent: return true # Retry cannot extend the same request.
	if float(timing.time_s)>.11:
		buffer = {"kind":"KICK","intent":intent.duplicate(true),"target":target,"owner":null,"restart_id":match_controller.formation_serial,"one_touch_pass":true,"ball_id":match_controller.ball.get_instance_id(),"generation":match_controller.match_generation,"epoch":match_controller.input_bridge.authority_epoch}
		buffer_time = clampf(float(intent.get("one_touch_valid_seconds",.30)),.05,.30)
		return true
	if kind=="RECEIVE": cancel("explicit_one_touch_pass")
	var selected:Dictionary=PassChoice.choose(actor,match_controller.ball,intent)
	if selected.is_empty():return false
	if not begin("PASS",aim): return false
	windup=clampf(float(timing.time_s)*.75,.012,.055)
	window=.09
	actor.stop_requested = 0.0
	actor.action_cooldown = .32
	kick_intent = intent.duplicate(true)
	_configure_pass(selected)
	windup=clampf(float(timing.time_s)*.75,.025,.080)
	receiver = target
	if is_instance_valid(target):
		kick_intent["ground_pass_reference"] = target.position
		kick_intent["ground_pass_aim_offset"] = 0.0
	return true


func _receive_plan_current(intent: Dictionary) -> bool:
	# Player reservations have no source plan; their existing scope stays authoritative.
	if not intent.has("source_receive_pass_id"): return true
	var director = match_controller.tactical_director
	var plan: Dictionary = director.receive_plan.active
	var receiver_index := int(plan.get("receiver_id",-1))
	if receiver_index<0 or receiver_index>=match_controller.players.size() or match_controller.players[receiver_index]!=actor: return false
	return plan.get("state","")=="IN_FLIGHT" and plan.get("pass_id","")==intent.source_receive_pass_id and plan.get("next_action","")=="PASS" and int(plan.get("next_receiver_id",-1))==int(intent.get("receiver_id",-2)) and director.clock<float(plan.get("next_valid_until",0.0)) and director.clock<float(intent.get("source_next_valid_until",0.0))

func begin_tackle_withdraw()->void:
	if kind!="TACKLE" or touch_plan.has("withdraw_point"):return
	var away:Vector3=toe_world-match_controller.ball.position;away.y=0
	if away.length_squared()<.001:away=-direction
	touch_plan["withdraw_point"]=toe_world
	touch_plan["withdraw_away"]=away.normalized()
	touch_plan["withdraw_elapsed"]=elapsed
	recovery=.16
	windup=minf(windup,elapsed)
	window=maxf(0,elapsed-windup)
	phase=Phase.RECOVER
