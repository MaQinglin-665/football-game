class_name FootballGiveGoPlan
extends RefCounted
## Original, cancellable support plan. It never moves bodies or changes a ball.
## This host requires control before kicking: this batch uses control then return.
var roster: Dictionary = {}
var active: Dictionary = {}
var last_plan: Dictionary = {}
var events: Array[Dictionary] = []
var clock := 0.0

func configure(rows: Dictionary) -> void:
	roster = rows.duplicate(true)
	active.clear()
	last_plan.clear()
	events.clear()
	clock = 0

func consume_contact(event: Dictionary, pass_plan: Dictionary, now: float) -> bool:
	clock = now
	if event.get("kind","")!="FOOT_TOUCH" or not event.get("success",false): return false
	var actor_id := int(event.get("actor_id",-1))
	var target_id := int(event.get("receiver_id",-1))
	var action := String(event.get("tactical_action",event.get("action","")))
	if not roster.has(actor_id): return false
	if not active.is_empty():
		if action in ["PASS","CROSS","CUTBACK","CLEARANCE","SHOT"]:
			if action=="PASS" and actor_id==int(active.wall_id) and target_id==int(active.runner_id) and active.state in ["RETURN_WINDOW","RETURN_READY"] and not pass_plan.is_empty():
				active.state = "RETURN_IN_FLIGHT"
				active.return_pass_id = pass_plan.pass_id
				active.deadline = now+3.5
				active.return_contact = _contact_identity(event)
				_event("RETURN","actual_return_pass_contact")
				return true
			cancel("wall_chose_other_action" if actor_id==int(active.wall_id) else "other_confirmed_kick",now)
			return true
		if int(event.get("carrier_id",-1))==actor_id and event.get("action","") in ["RECEIVE","STOP","SETTLE","PULL","CONTROL"]:
			if actor_id==int(active.wall_id) and active.state in ["SELECT_RUN","RUNNING"]:
				active.state = "RETURN_WINDOW"
				active.wall_controlled_at = now
				active.wall_control_contact = _contact_identity(event)
				active.deadline = minf(float(active.deadline),now+2.2)
				_event("CONTROL","actual_wall_control_contact")
				return true
			if actor_id==int(active.runner_id) and active.state=="RETURN_IN_FLIGHT":
				active.state = "COMPLETED"
				active.completion_contact = _contact_identity(event)
				_event("COMPLETE","actual_runner_control_contact")
				last_plan = active.duplicate(true)
				active.clear()
				return true
			if actor_id==int(active.wall_id) and active.state in ["RETURN_WINDOW","RETURN_READY"]: return true
			cancel("other_player_control_contact",now)
			return true
		return false
	if action!="PASS" or pass_plan.is_empty() or not roster.has(target_id) or target_id==actor_id: return false
	if int(roster[actor_id].team)!=int(roster[target_id].team): return false
	if roster[actor_id].role in ["goalkeeper","center_back"] or roster[target_id].role=="goalkeeper": return false
	active = {"pass_id":pass_plan.pass_id,"runner_id":actor_id,"wall_id":target_id,"team":int(roster[actor_id].team),"state":"SELECT_RUN","started_at":now,"deadline":now+7.0,"runner_start":Vector3.ZERO,"runner_goal":Vector3.ZERO,"return_target":Vector3.ZERO,"return_pass_id":"","return_mode":"CONTROL_THEN_RETURN","one_touch_supported":false,"runner_human_advisory":false,"wall_human_advisory":false,"return_requested":false,"cancel_reason":"","completion_contact":null,"wall_controlled_at":-1.0,"first_pass_contact":_contact_identity(event)}
	_event("CANDIDATE","confirmed_pass_pair")
	return true

func fail_action(actor_id: int, now: float, action := "PASS") -> void:
	if action=="PASS" and not active.is_empty() and actor_id==int(active.wall_id) and active.state=="RETURN_READY": cancel("return_foot_action_failed",now)

func cancel(reason: String, now: float) -> void:
	clock = now
	if active.is_empty(): return
	active.state = "CANCELED"
	active.cancel_reason = reason
	_event("CANCEL",reason)
	last_plan = active.duplicate(true)
	active.clear()

func tick(snapshot: Dictionary, reception: Dictionary, now: float) -> Dictionary:
	clock = now
	if active.is_empty(): return {}
	var by_id := {}
	for p in snapshot.get("players",[]):
		if p.get("active",true): by_id[int(p.id)] = p
	var runner: Dictionary = by_id.get(int(active.runner_id),{})
	var wall: Dictionary = by_id.get(int(active.wall_id),{})
	if runner.is_empty() or wall.is_empty():
		cancel("participant_unavailable",now)
		return {}
	if now>=float(active.deadline):
		cancel("deadline",now)
		return {}
	var team := int(active.team)
	var opponents: Array[Dictionary] = []
	for p in by_id.values():
		if int(p.team)!=team: opponents.append(p)
	var ball: Vector3 = snapshot.ball_position
	if absf(ball.x)>float(snapshot.field_half_width)+.25 or absf(ball.z)>float(snapshot.field_half_length)+.25:
		cancel("ball_outside_pitch",now)
		return {}
	var owner := int(snapshot.get("carrier_id",-1))
	if owner>=0 and owner!=int(active.wall_id) and not (owner==int(active.runner_id) and active.state=="RETURN_IN_FLIGHT"):
		cancel("opponent_or_other_teammate_controls",now)
		return {}
	if active.state=="SELECT_RUN":
		var gap: float = _flat(runner.position-wall.position).length()
		if gap<3.0 or gap>18.0:
			cancel("pair_not_short_combination",now)
			return {}
		active.runner_start = runner.position
		var chosen: Dictionary = _choose_run(runner,wall,opponents,snapshot)
		if chosen.is_empty():
			cancel("no_safe_forward_space",now)
			return {}
		active.runner_goal = chosen.point
		active.state = "RUNNING"
		_event("RUN","available_forward_space")
	active.runner_human_advisory = runner.get("human",false)
	active.wall_human_advisory = wall.get("human",false)
	active.return_requested = false
	active.return_preparing = false
	if active.state=="RETURN_IN_FLIGHT":
		var follow: Dictionary = reception.get("active",{})
		if follow.get("pass_id","")!=active.return_pass_id:
			cancel("return_receive_plan_ended_without_control_contact",now)
			return {}
		return active.duplicate(true)
	active.receiver_offside_now = _offside(runner.position,team,ball,opponents)
	if not _lane_clear(runner.position,active.runner_goal,opponents,.80):
		cancel("runner_route_blocked",now)
		return {}
	var run_eta: float = _flat(active.runner_goal-runner.position).length()/6.2+.35
	if active.state=="RUNNING" and run_eta>float(active.deadline)-now:
		cancel("runner_cannot_reach_in_time",now)
		return {}
	if active.state=="RUNNING":
		if reception.get("active",{}).get("pass_id","")!=active.pass_id:
			cancel("initial_receive_plan_ended_without_control_contact",now)
			return {}
		return active.duplicate(true)
	if owner!=int(active.wall_id):
		cancel("wall_lost_control",now)
		return {}
	var advanced: float = _progress(runner.position,team)-_progress(active.runner_start,team)
	if advanced<.8:
		if now-float(active.wall_controlled_at)>.9: cancel("runner_not_advancing",now)
		return active.duplicate(true)
	var distance: float = _flat(runner.position-wall.position).length()
	var horizon := clampf(distance/10.0,.15,.55)
	var target: Vector3 = runner.position+_flat(runner.get("velocity",Vector3.ZERO))*horizon
	if not runner.get("human",false):
		# Do not lead beyond the planned legal space when the runner brakes.
		if _flat(target-runner.position).length()>_flat(active.runner_goal-runner.position).length(): target = active.runner_goal
	active.return_target = target
	active.progress_gain = _progress(target,team)-_progress(wall.position,team)
	active.target_offside_now = _offside(target,team,ball,opponents)
	if active.receiver_offside_now and runner.get("human",false):
		active.reason = "return_receiver_offside_wait"
		return active.duplicate(true)
	if not _lane_clear(ball,target,opponents,1.20) or _openness(target,opponents)<2.0:
		cancel("return_lane_closed",now)
		return {}
	if distance<3.0 or distance>18.0 or float(active.progress_gain)<1.4: return active.duplicate(true)
	var aim := _flat(target-ball).normalized()
	active.return_direction = aim
	active.wall_setup_target = _flat(ball)-aim*.44+_flat(snapshot.ball_velocity)*.14
	active.return_preparing = true
	# Do not replace a committed physical return with a new movement command.
	if wall.get("foot_action","")=="PASS" and active.state=="RETURN_READY":
		active.return_requested = true
		return active.duplicate(true)
	if wall.get("foot_action","") in ["SHOT","TACKLE"] or not wall.get("kick_ready",false) or not wall.get("can_kick",false): return active.duplicate(true)
	var offset := _flat(ball-wall.position)
	if offset.length()>.62 or offset.normalized().dot(aim)<.86 or _flat(snapshot.ball_velocity-wall.velocity).length()>2.8: return active.duplicate(true)
	active.return_requested = true
	active.state = "RETURN_READY"
	active.reason = "controlled_ball_open_return_lane"
	return active.duplicate(true)

func _choose_run(runner: Dictionary, wall: Dictionary, opponents: Array[Dictionary], snapshot: Dictionary) -> Dictionary:
	var team := int(runner.team)
	var attack := Vector3.FORWARD if team==0 else Vector3.BACK
	var right := Vector3.RIGHT if team==0 else Vector3.LEFT
	var away := -1.0 if _flat(runner.position-wall.position).dot(right)<0 else 1.0
	var best := {}
	var best_score := -INF
	var run_scale := clampf(float(snapshot.field_half_length)/26.0,.75,1.0)
	for distance in [5.8*run_scale,8.0*run_scale]:
		for lateral in [away*1.8,0.0,-away*2.8]:
			var point: Vector3 = runner.position+attack*distance+right*lateral
			point.y = 0
			if absf(point.x)>float(snapshot.field_half_width)-2 or absf(point.z)>float(snapshot.field_half_length)-3: continue
			if not _lane_clear(runner.position,point,opponents,.8): continue
			var open := _openness(point,opponents)
			if open<2.2 or _flat(point-wall.position).length()<3.5: continue
			var score: float = minf(open,8)*.4+distance*.5-absf(lateral)*.12
			if score>best_score:
				best_score = score
				best = {"point":point,"score":score}
	return best

func _offside(point: Vector3, team: int, ball: Vector3, opponents: Array[Dictionary]) -> bool:
	var defenders: Array[float] = []
	for p in opponents: defenders.append(_progress(p.position,team))
	defenders.sort()
	if defenders.size()<2: return false
	var line := maxf(_progress(ball,team),defenders[-2])
	return _progress(point,team)>0 and _progress(point,team)>line-.65

func _lane_clear(a: Vector3, b: Vector3, opponents: Array[Dictionary], clearance: float) -> bool:
	var line := _flat(b-a)
	if line.length_squared()<.01: return true
	for p in opponents:
		var position: Vector3 = p.position+_flat(p.get("velocity",Vector3.ZERO))*.20
		var fraction := _flat(position-a).dot(line)/line.length_squared()
		if fraction>.04 and fraction<.98 and _flat(position-(a+line*fraction)).length()<clearance: return false
	return true

func _openness(point: Vector3, opponents: Array[Dictionary]) -> float:
	var nearest := INF
	for p in opponents: nearest = minf(nearest,_flat(point-p.position).length())
	return nearest

func _progress(point: Vector3, team: int) -> float: return -point.z if team==0 else point.z
func _flat(v: Vector3) -> Vector3: return Vector3(v.x,0,v.z)
func _contact_identity(e: Dictionary) -> Dictionary:
	return {"actor_id":int(e.get("actor_id",-1)),"physics_frame":int(e.get("physics_frame",-1)),"serial":int(e.get("serial",-1)),"action":e.get("action","")}
func _event(kind: String, reason: String) -> void:
	events.append({"time":clock,"event":kind,"pass_id":active.pass_id,"runner_id":active.runner_id,"wall_id":active.wall_id,"reason":reason})
	if events.size()>128: events.pop_front()
func debug_snapshot() -> Dictionary:
	return {"active":active.duplicate(true),"last_plan":last_plan.duplicate(true),"events":events.duplicate(true)}
