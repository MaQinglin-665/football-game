class_name FootballDefensiveTasks
extends RefCounted
## Original host implementation. Planning only: never moves bodies or touches a ball.
## Fixed-commit behavior references and limitations are documented in RESEARCH.md.
const PRESS := "PRESS"
const COVER := "COVER"
const MARK := "MARK"
const SCREEN := "SCREEN"
const HOLD := "HOLD"
const RECOVER := "RECOVER"
const MIN_PRESS_HOLD := .65
const SWITCH_GAIN_SECONDS := .45
const RECLAIM_DELAY := .8
var roster: Dictionary = {}
var tasks: Dictionary = {}
var blocked_until: Dictionary = {}
var events: Array[Dictionary] = []
var clock := 0.0
var sequence := 0
var previous_owner := -1
var loose_press_after := 0.0
var exited_this_tick: Dictionary = {}

func configure(rows: Dictionary) -> void:
	roster = rows.duplicate(true)
	tasks.clear()
	blocked_until.clear()
	events.clear()
	clock = 0.0
	sequence = 0
	previous_owner = -1
	loose_press_after = 0.0
	exited_this_tick.clear()

func cancel_all(reason: String) -> void:
	for id in tasks.keys(): _exit(int(id),reason)
	previous_owner = -1
	loose_press_after = clock

func tick(snapshot: Dictionary, delta: float) -> Dictionary:
	clock += clampf(delta,0,.5)
	exited_this_tick.clear()
	var by_id: Dictionary = {}
	for p in snapshot.get("players",[]):
		if p.get("active",true) and roster.has(int(p.id)): by_id[int(p.id)] = p
	for id in tasks.keys():
		if not by_id.has(int(id)): _exit(int(id),"owner_unavailable")
	var owner_id: int = int(snapshot.get("carrier_id",-1))
	var owner: Dictionary = by_id.get(owner_id,{})
	var owner_team: int = int(owner.get("team",-1))
	var possession_team: int = int(snapshot.get("possession_team",owner_team))
	snapshot.defense_meet=_incoming_meet(snapshot,by_id)
	if previous_owner>=0 and owner_id<0: loose_press_after = clock
	previous_owner = owner_id
	var teams: Dictionary = {}
	for team in [0,1]:
		var defending: bool = possession_team!=team
		var members: Array[Dictionary] = []
		for p in by_id.values():
			if int(p.team)==team: members.append(p)
		var goal: Vector3 = _goal(team,snapshot)
		var beaten := false
		var ready_cover: Dictionary = _find(team,COVER)
		for p in members:
			var id: int = int(p.id)
			if not tasks.has(id): continue
			var task: Dictionary = tasks[id]
			var reason := ""
			if not defending: reason = "team_has_possession"
			elif task.task==PRESS: reason = _press_exit(p,task,owner,by_id,snapshot,goal)
			elif task.task in [MARK,SCREEN]:
				var opponent: Dictionary = by_id.get(int(task.target_id),{})
				if opponent.is_empty(): reason = "target_unavailable"
				elif int(opponent.id)==owner_id:
					task.task=HOLD # Reassign directly this tick; a pass to your mark is not a forced retreat.
				elif _distance(opponent.position,task.origin)>18.0 or _distance(opponent.position,_anchor(p,snapshot))>(13.0 if snapshot.get("eleven_duties",false) else 7.0): reason = "target_left_zone"
				elif clock>=float(task.deadline): task.deadline=clock+3.8
			elif task.task==COVER:
				if _distance(snapshot.ball_position,task.origin)>20.0: reason = "ball_left_zone"
				elif clock>=float(task.deadline): task.deadline=clock+3.8
			elif task.task==RECOVER and clock>=float(task.deadline): reason = "recovery_complete"
			if reason=="beaten_recover_goal_side": beaten = true
			if not reason.is_empty(): _exit(id,reason)
		if not defending:
			teams[team] = {"active":false,"presser_id":-1,"cover_id":-1}
			continue
		# Every eligible player has one slot. An exited active task first recovers;
		# its owner cannot reclaim pressure/cover/mark on the same decision tick.
		for p in members:
			var id: int = int(p.id)
			if not tasks.has(id):
				var recovering: bool = clock<float(blocked_until.get(id,0.0))
				_assign(p,RECOVER if recovering else HOLD,-1,_anchor(p,snapshot),"task_exit_recovery" if recovering else "role_shape",.8 if recovering else 4.0,.0,snapshot)
		# Only the still-eligible protector replaces a beaten presser. The beaten
		# actor retains recovery and reclaim delay; no general cooldown bypass.
		if beaten and not ready_cover.is_empty():
			var cover_id := int(ready_cover.owner)
			if tasks.has(cover_id) and tasks[cover_id].task==COVER and by_id.has(cover_id) and clock>=float(blocked_until.get(cover_id,0.0)):
				var protector: Dictionary = by_id[cover_id]
				if _goal_side(protector.position,_press_point(owner,snapshot),goal)>=0 and _distance(protector.position,_press_point(owner,snapshot))<float(snapshot.field_half_length)*0.20:
					_assign(protector,PRESS,owner_id,_press_point(owner,snapshot),"protector_replaces_beaten",2.8,MIN_PRESS_HOLD,snapshot)
		var pressure: Dictionary = _find(team,PRESS)
		var candidate: Dictionary = _best(members,PRESS,owner,snapshot,goal)
		if not pressure.is_empty() and not candidate.is_empty() and int(candidate.id)!=int(pressure.owner) and clock>=float(pressure.min_until):
			var current: Dictionary = by_id.get(int(pressure.owner),{})
			var current_eta: float = _eta(current,_press_point(owner,snapshot),snapshot)
			if float(candidate.cost)+SWITCH_GAIN_SECONDS<current_eta and float(candidate.cost)<current_eta*.80:
				_exit(int(pressure.owner),"teammate_arrives_earlier")
				_assign(current,RECOVER,-1,_anchor(current,snapshot),"handoff_recovery",RECLAIM_DELAY,.0,snapshot)
				pressure = {}
		if pressure.is_empty() and not candidate.is_empty():
			var selected: Dictionary = by_id[int(candidate.id)]
			_assign(selected,PRESS,owner_id,_press_point(owner,snapshot),"carrier_pressure" if owner_id>=0 else "loose_ball_intercept",2.8 if owner_id>=0 else 1.6,MIN_PRESS_HOLD,snapshot)
		var cover: Dictionary = _find(team,COVER)
		if cover.is_empty():
			var covering: Dictionary = _best(members,COVER,owner,snapshot,goal)
			if not covering.is_empty():
				var selected: Dictionary = by_id[int(covering.id)]
				_assign(selected,COVER,-1,_cover_point(snapshot.ball_position,goal,snapshot),"inside_goal_side_cover",3.6,1.0,snapshot)
		# Two dangerous off-ball threats at most; reserve each opponent once.
		var reserved: Dictionary = {}
		for task in tasks.values():
			if int(task.team)==team and task.task in [MARK,SCREEN]: reserved[int(task.target_id)] = true
		var threats: Array[Dictionary] = []
		for opponent in by_id.values():
			if int(opponent.team)==team or int(opponent.id)==owner_id or roster[int(opponent.id)].role=="goalkeeper": continue
			if _distance(opponent.position,goal)>45.0*_tactical_scale(snapshot) or _distance(opponent.position,snapshot.ball_position)>28.0*_tactical_scale(snapshot): continue
			var projected:Vector3=opponent.position+Vector3(opponent.velocity.x,0,opponent.velocity.z)*.55
			var danger:float=_distance(projected,goal)+absf(float(projected.x))*.25
			var ball_depth:float=absf(goal.z-snapshot.ball_position.z)
			var player_depth:float=absf(goal.z-projected.z)
			if ball_depth<12 and absf(snapshot.ball_position.x)>10 and player_depth>ball_depth+3 and player_depth<22:danger-=10.0
			threats.append({"id":int(opponent.id),"danger":danger})
		threats.sort_custom(func(a,b): return a.danger<b.danger if absf(a.danger-b.danger)>.001 else a.id<b.id)
		var eligible := members.filter(func(p): return not p.get("human",false) and roster[int(p.id)].role!="goalkeeper").size()
		# One lane blocker in 11v11; small-sided cover combines protection and screening.
		if snapshot.get("eleven_duties",false) and _find(team,SCREEN).is_empty():
			for threat in threats:
				if reserved.has(int(threat.id)):continue
				var opponent:Dictionary=by_id[int(threat.id)]
				var blocker:Dictionary=_best(members,SCREEN,opponent,snapshot,goal)
				if blocker.is_empty():continue
				_assign(by_id[int(blocker.id)],SCREEN,int(threat.id),_screen_point(opponent,goal,snapshot),"dangerous_pass_lane",4.0,.9,snapshot)
				reserved[int(threat.id)]=true
				break
		var mark_budget := mini(4 if snapshot.get("eleven_duties",false) else 1,maxi(0,eligible-2))
		for threat in threats:
			if reserved.size()>=mark_budget: break
			if reserved.has(int(threat.id)): continue
			var opponent: Dictionary = by_id[int(threat.id)]
			var marker: Dictionary = _best(members,MARK,opponent,snapshot,goal)
			if marker.is_empty(): continue
			var selected: Dictionary = by_id[int(marker.id)]
			_assign(selected,MARK,int(opponent.id),_mark_point(opponent,goal,snapshot),"unique_off_ball_mark",3.8,1.0,snapshot)
			reserved[int(opponent.id)] = true
		for p in members:
			var id: int = int(p.id)
			if not tasks.has(id): continue
			var task: Dictionary = tasks[id]
			match String(task.task):
				PRESS: task.target = _press_point(owner,snapshot)
				COVER: task.target = _cover_point(snapshot.ball_position,goal,snapshot)
				MARK: task.target = _mark_point(by_id[int(task.target_id)],goal,snapshot)
				SCREEN: task.target = _screen_point(by_id[int(task.target_id)],goal,snapshot)
				_:
					task.target = _anchor(p,snapshot)
					if task.task==RECOVER:
						var retreat:Vector3=Vector3(goal.x-p.position.x,0,goal.z-p.position.z).normalized()
						var flank:Vector3=Vector3(-retreat.z,0,retreat.x)*(1.0 if int(p.id)%2 else -1.0)
						task.target=_clip(p.position+retreat*3.0+flank*1.2,snapshot)
					if clock>=float(task.deadline):
						task.deadline = clock+4.0
						task.renewals = int(task.get("renewals",0))+1
		var presser: Dictionary = _find(team,PRESS)
		var protector: Dictionary = _find(team,COVER)
		teams[team] = {"active":true,"presser_id":int(presser.get("owner",-1)),"cover_id":int(protector.get("owner",-1))}
	return {"tasks":tasks.duplicate(true),"teams":teams,"clock":clock}

func _press_exit(p: Dictionary, task: Dictionary, owner: Dictionary, by_id: Dictionary, snapshot: Dictionary, goal: Vector3) -> String:
	var target_id: int = int(task.target_id)
	var actual_owner: int = int(snapshot.get("carrier_id",-1))
	if target_id!=actual_owner:
		# Losing the carrier is a retarget, not a forced retreat from a loose ball.
		task.target_id = actual_owner
		task.origin = snapshot.ball_position
		task.deadline = clock+1.6
		target_id = actual_owner
	if target_id<0 and actual_owner>=0: return "loose_ball_claimed"
	if clock>=float(task.deadline): task.deadline=clock+1.6
	var point: Vector3 = _press_point(owner,snapshot)
	var remaining:float=float(snapshot.get("loss_until",{}).get(int(p.team),0))-float(snapshot.get("tactical_clock",0))
	if remaining>1.4 and _distance(point,goal)>16.0*_tactical_scale(snapshot):
		var supported:bool=false
		for partner in by_id.values():
			if int(partner.team)==int(p.team) and int(partner.id)!=int(p.id) and roster[int(partner.id)].role!="goalkeeper" and _distance(partner.position,point)<8.0 and _goal_side(partner.position,point,goal)>0:supported=true;break
		if not supported or _distance(p.position,point)>5.5:return "unsupported_transition_recover"
	if absf(point.x)>float(snapshot.get("field_half_width",34))+.5 or absf(point.z)>float(snapshot.get("field_half_length",52.5))+.5: return "ball_outside_pitch"
	if _distance(point,task.origin)>16.0*_tactical_scale(snapshot) or _distance(p.position,point)>22.0*_tactical_scale(snapshot): return "ball_left_zone"
	if actual_owner>=0 and _goal_side(p.position,point,goal)<-maxf(1.2,1.8*_tactical_scale(snapshot)): return "beaten_recover_goal_side"
	if snapshot.get("eleven_duties",false) and point.z*(-1.0 if int(p.team)==0 else 1.0)>float(snapshot.field_half_length)*(.43 if int(snapshot.get("learning_actions",{}).get(int(p.team),0))==5 else .22 if int(snapshot.get("learning_actions",{}).get(int(p.team),0))==6 else .32) and _distance(p.position,point)>5.5:return "return_to_mid_block"
	if not by_id.has(int(p.id)): return "owner_unavailable"
	return ""

func _best(members: Array[Dictionary], kind: String, target: Dictionary, snapshot: Dictionary, goal: Vector3) -> Dictionary:
	if kind==PRESS and target.is_empty() and clock<loose_press_after: return {}
	var point: Vector3 = _press_point(target,snapshot) if kind==PRESS else _cover_point(snapshot.ball_position,goal,snapshot) if kind==COVER else _screen_point(target,goal,snapshot) if kind==SCREEN else _mark_point(target,goal,snapshot)
	if kind==PRESS and (absf(point.x)>float(snapshot.get("field_half_width",34))+.5 or absf(point.z)>float(snapshot.get("field_half_length",52.5))+.5): return {}
	var best: Dictionary = {}
	for p in members:
		var id: int = int(p.id)
		var role: Dictionary = roster[id]
		if role.role=="goalkeeper" or p.get("human",false) or clock<float(blocked_until.get(id,0.0)) or exited_this_tick.has(id): continue
		# Fixed line responsibilities: wingers do not become the deep protector.
		if snapshot.get("eleven_duties",false):
			var slot:String=String(role.get("slot",""))
			if kind==COVER and slot not in ["DM","LCB","RCB"]:continue
			if kind==SCREEN and slot not in ["DM","LCM","RCM","LB","RB"]:continue
		var existing: Dictionary = tasks.get(id,{})
		if not existing.is_empty():
			if existing.task not in ([HOLD,PRESS,COVER,MARK,SCREEN] if kind==PRESS else [HOLD,PRESS]) or (existing.task==PRESS and kind!=PRESS): continue
		if kind==PRESS:
			var remaining:float=float(snapshot.get("loss_until",{}).get(int(p.team),0))-float(snapshot.get("tactical_clock",0))
			if remaining>1.4:
				var supported:bool=false
				for partner in members:
					if int(partner.id)!=id and roster[int(partner.id)].role!="goalkeeper" and _distance(partner.position,point)<8.0 and _goal_side(partner.position,point,goal)>0:supported=true;break
				if (not supported or _distance(p.position,point)>5.5) and _distance(point,goal)>16.0*_tactical_scale(snapshot):continue
			if snapshot.get("eleven_duties",false) and point.z*(-1.0 if int(p.team)==0 else 1.0)>float(snapshot.field_half_length)*(.43 if int(snapshot.get("learning_actions",{}).get(int(p.team),0))==5 else .22 if int(snapshot.get("learning_actions",{}).get(int(p.team),0))==6 else .32) and _distance(p.position,point)>5.5:continue
			if _distance(p.position,point)>22.0*_tactical_scale(snapshot) or (not target.is_empty() and _goal_side(p.position,point,goal)<-3.0): continue
		elif kind in [MARK,SCREEN]:
			if _distance(_anchor(p,snapshot),point)>16.0: continue
		var cost: float = _eta(p,point,snapshot)
		if kind==COVER: cost += -.35 if role.get("duty","")=="hold" else .1 if role.role=="midfielder" else 1.4 if role.role in ["winger","striker","full_back"] else .6
		if snapshot.get("eleven_duties",false):
			var duty := String(role.get("duty",""))
			if kind==COVER: cost += -.6 if duty=="cover" else -.3 if duty=="hold" else .6 if duty in ["finish","width","overlap"] else 0.0
			if kind==PRESS:
				cost += .6 if duty in ["hold","cover"] else -.3 if duty in ["finish","overlap"] else 0.0
				if duty=="width" and absf(point.x)<float(snapshot.field_half_width)*0.30: cost += 1.0
			if kind==MARK and duty in ["support","link"]: cost -= .25
		if kind==PRESS and role.role=="center_back": cost += .65
		if kind in [MARK,SCREEN]: cost += _distance(_anchor(p,snapshot),point)*.035
		if best.is_empty() or cost<float(best.cost)-.001 or (absf(cost-float(best.cost))<=.001 and id<int(best.id)):
			best = {"id":id,"cost":cost}
	return best

func _assign(p: Dictionary, kind: String, target_id: int, point: Vector3, reason: String, duration: float, hold: float, snapshot: Dictionary) -> void:
	var id: int = int(p.id)
	if tasks.has(id):
		var previous: Dictionary = tasks[id]
		if previous.task==kind and int(previous.target_id)==target_id: return
		_event("CHANGE",previous,"task_selected")
	sequence += 1
	var origin: Vector3 = snapshot.ball_position
	if kind in [MARK,SCREEN]:
		for opponent in snapshot.get("players",[]):
			if int(opponent.id)==target_id:
				origin = opponent.position
				break
	tasks[id] = {"owner":id,"team":int(p.team),"role":roster[id].role,"task":kind,"target_id":target_id,"target":point,"origin":origin,"started_at":clock,"min_until":clock+hold,"deadline":clock+duration,"reason":reason,"generation":sequence,"renewals":0}
	_event("START",tasks[id],reason)

func _exit(id: int, reason: String) -> void:
	if not tasks.has(id): return
	var old: Dictionary = tasks[id]
	_event("EXIT",old,reason)
	if old.task in [PRESS,COVER,MARK,SCREEN]: blocked_until[id] = clock+RECLAIM_DELAY
	exited_this_tick[id] = true
	tasks.erase(id)

func _event(action: String, task: Dictionary, reason: String) -> void:
	events.append({"time":clock,"event":action,"owner":task.owner,"team":task.team,"task":task.task,"target_id":task.target_id,"generation":task.generation,"reason":reason})
	if events.size()>256: events.pop_front()

func _find(team: int, kind: String) -> Dictionary:
	for task in tasks.values():
		if int(task.team)==team and task.task==kind: return task
	return {}

func update_output_target(id: int, point: Vector3) -> void:
	if tasks.has(id): tasks[id].target = point

func debug_snapshot() -> Dictionary:
	return {"clock":clock,"tasks":tasks.duplicate(true),"events":events.duplicate(true),"blocked_until":blocked_until.duplicate(true)}

func _anchor(p: Dictionary, snapshot: Dictionary) -> Vector3:
	var anchor:Vector3=snapshot.get("role_targets",{}).get(int(p.id),Vector3(p.position.x,0,p.position.z))
	if not snapshot.get("eleven_duties",false):return anchor
	var ball:Vector3=snapshot.ball_position
	var weak:bool=anchor.x*ball.x<0 and absf(ball.x)>3.0
	anchor.x=anchor.x*(.58 if weak else .82)+ball.x*.16
	return _clip(anchor,snapshot)

func _goal(team: int, snapshot: Dictionary) -> Vector3:
	# The host already rotates snapshots into its initial frame after half-time.
	return Vector3(0,0,float(snapshot.get("field_half_length",52.5))*(1.0 if team==0 else -1.0))

func _press_point(target: Dictionary, snapshot: Dictionary) -> Vector3:
	return _clip(Vector3(target.position.x,0,target.position.z)+Vector3(target.get("velocity",Vector3.ZERO).x,0,target.get("velocity",Vector3.ZERO).z)*.30,snapshot) if not target.is_empty() else snapshot.get("defense_meet",Vector3(snapshot.ball_position.x,0,snapshot.ball_position.z))

func _cover_point(ball: Vector3, goal: Vector3, snapshot: Dictionary) -> Vector3:
	if int(snapshot.get("carrier_id",-1))<0:ball=snapshot.get("defense_meet",ball)
	for owner in snapshot.get("players",[]):
		if int(owner.id)==int(snapshot.get("carrier_id",-1)):
			var advance:Vector3=owner.get("velocity",Vector3.ZERO);advance.y=0
			ball+=advance*.25
			break
	if snapshot.get("eleven_duties",false):return _eleven_cover_point(ball,goal,snapshot)
	var lane:Vector3=_eleven_cover_point(ball,goal,snapshot) if snapshot.get("eleven_duties",false) else ball+Vector3(goal.x-ball.x,0,goal.z-ball.z).normalized()*5.0*_tactical_scale(snapshot)
	var carrier_team:=-1
	for actor in snapshot.get("players",[]):
		if int(actor.id)==int(snapshot.get("carrier_id",-1)):carrier_team=int(actor.team)
	var lane_risk:=INF
	for receiver in snapshot.get("players",[]):
		if int(receiver.team)!=carrier_team or int(receiver.id)==int(snapshot.get("carrier_id",-1)) or roster[int(receiver.id)].role=="goalkeeper":continue
		var distance:float=_distance(ball,receiver.position)
		if distance<3.0 or distance>22.0*_tactical_scale(snapshot):continue
		var candidate:Vector3=ball.lerp(receiver.position,.45);candidate.y=0
		var cost:float=_distance(receiver.position,goal)+_distance(candidate,lane)*1.5
		if cost<lane_risk and _distance(candidate,lane)<6.0*_tactical_scale(snapshot):lane_risk=cost;lane=candidate
	if lane_risk<INF or snapshot.get("eleven_duties",false):return _clip(lane,snapshot)
	var toward_goal := Vector3(goal.x-ball.x,0,goal.z-ball.z).normalized()
	var scale := _tactical_scale(snapshot)
	var point := ball+toward_goal*5.0*scale
	var owner_id := int(snapshot.get("carrier_id",-1))
	var owner_team := -1
	for p in snapshot.get("players",[]):
		if int(p.id)==owner_id: owner_team = int(p.team)
	var danger := INF
	for p in snapshot.get("players",[]):
		if int(p.id)==owner_id or int(p.team)!=owner_team or not p.get("active",true) or roster[int(p.id)].role=="goalkeeper": continue
		var offset := Vector3(p.position.x-ball.x,0,p.position.z-ball.z)
		if offset.length()>16.0 or offset.dot(toward_goal)<1.5: continue
		var risk := _distance(p.position,goal)
		if risk<danger:
			danger = risk
			point = ball+toward_goal*4.8*scale+Vector3(clampf(offset.x*.35,-2.0*scale,2.0*scale),0,0)
	return _clip(point,snapshot)

func _eleven_cover_point(ball: Vector3, goal: Vector3, snapshot: Dictionary) -> Vector3:
	var point := Vector3(ball.x*.55,0,ball.z+signf(goal.z)*5.5)
	if snapshot.get("eleven_duties",false):
		var team := 0 if goal.z>0 else 1
		var pressure: Dictionary = _find(team,PRESS)
		for p in snapshot.get("players",[]):
			if int(p.id)!=int(pressure.get("owner",-1)): continue
			var position: Vector3 = p.position
			var toward_goal := Vector3(goal.x-ball.x,0,goal.z-ball.z).normalized()
			var depth := clampf(float(snapshot.field_half_length)*0.067,2.8,4.2)
			var strategy:int=int(snapshot.get("learning_actions",{}).get(team,0))
			depth*=.85 if strategy==5 else 1.2 if strategy==6 else 1.0
			var outward := Vector3(signf(ball.x),0,0)*minf(absf(ball.x)/float(snapshot.field_half_width),1.0)*float(snapshot.field_half_width)*0.035
			# Do not follow a presser behind the carrier; retain goal-side cover.
			var origin:Vector3=ball if _goal_side(position,ball,goal)<0 else ball+(position-ball).limit_length(depth)
			point = origin+toward_goal*depth+outward
			break
	# Cover the dangerous run behind pressure, while markers retain their own opponents.
	var defending_team:int=0 if goal.z>0 else 1
	var best:Vector3=point;var danger:float=INF
	for opponent in snapshot.get("players",[]):
		if int(opponent.team)==defending_team or int(opponent.id)==int(snapshot.get("carrier_id",-1)) or roster[int(opponent.id)].role=="goalkeeper":continue
		var run:Vector3=Vector3(opponent.velocity.x,0,opponent.velocity.z)
		var goalward:Vector3=Vector3(goal.x-opponent.position.x,0,goal.z-opponent.position.z).normalized()
		if run.dot(goalward)<1.0 or _distance(opponent.position,ball)>28:continue

		var projected:Vector3=opponent.position+run.limit_length(5.6)*.5
		if _distance(projected,goal)>_distance(point,goal)-1.0:continue
		var covered:bool=false
		for teammate in snapshot.get("players",[]):
			if int(teammate.team)!=defending_team:continue
			var task:Dictionary=tasks.get(int(teammate.id),{})
			if task.get("task","")==MARK and int(task.get("target_id",-1))==int(opponent.id) and _distance(teammate.position,projected)<2.2:covered=true;break
		if covered:continue
		var risk:float=_distance(projected,goal)+absf(projected.x)*.25
		if risk<danger:danger=risk;best=projected+goalward*1.2
	if danger<INF:point+=(best-point).limit_length(4.0)
	return _clip(point,snapshot)

func _mark_point(opponent: Dictionary, goal: Vector3, snapshot: Dictionary) -> Vector3:
	if opponent.is_empty():return Vector3.ZERO
	var position:Vector3=opponent.position+Vector3(opponent.velocity.x,0,opponent.velocity.z).limit_length(5.6)*.42
	var toward_goal:=Vector3(goal.x-position.x,0,goal.z-position.z).normalized()
	var to_ball:Vector3=snapshot.ball_position-position;to_ball.y=0
	var screen:Vector3=to_ball.normalized()*minf(1.8,to_ball.length()*.22)
	# Stay goal-side as well as ball-side: marking cannot open a free run behind.
	var offset:Vector3=screen+toward_goal*.65
	offset+=toward_goal*maxf(0,.45-offset.dot(toward_goal))
	return _clip(position+offset,snapshot)


func _clip(point: Vector3, snapshot: Dictionary) -> Vector3:
	return Vector3(clampf(point.x,-float(snapshot.get("field_half_width",34))+.8,float(snapshot.get("field_half_width",34))-.8),0,clampf(point.z,-float(snapshot.get("field_half_length",52.5))+1.4,float(snapshot.get("field_half_length",52.5))-1.4))

func _goal_side(position: Vector3, target: Vector3, goal: Vector3) -> float:
	var direction := Vector3(goal.x-target.x,0,goal.z-target.z).normalized()
	return Vector3(position.x-target.x,0,position.z-target.z).dot(direction)

func _distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x,a.z).distance_to(Vector2(b.x,b.z))

func _eta(p: Dictionary, point: Vector3, snapshot: Dictionary) -> float:
	if p.is_empty(): return INF
	var cap: Dictionary = snapshot.get("capabilities",{})
	var speed: float = maxf(1.0,float(p.get("ability_speed",cap.get("jog_speed",5.6))))
	if p.get("sprint_locked",false) or float(p.get("stamina",100))<25:speed=minf(speed,4.0)
	var acceleration: float = maxf(1.0,float(p.get("ability_acceleration",cap.get("run_acceleration",6.8))))
	var offset: Vector3 = Vector3(point.x-p.position.x,0,point.z-p.position.z)
	var distance: float = maxf(0.0,offset.length()-.9)
	var axis := offset.normalized()
	var velocity: Vector3 = p.get("velocity",Vector3.ZERO)
	var initial: float = clampf(velocity.dot(axis),0,speed)
	var ramp: float = (speed-initial)/acceleration
	var ramp_distance: float = (initial+speed)*.5*ramp
	var travel: float = (sqrt(initial*initial+2*acceleration*distance)-initial)/acceleration if distance<=ramp_distance else ramp+(distance-ramp_distance)/speed
	var facing: Vector3 = p.get("facing",axis)
	var turn: float = acos(clampf(Vector3(facing.x,0,facing.z).normalized().dot(axis),-1,1))/maxf(1.0,float(cap.get("turn_speed",5.8))) if offset.length()>.1 else 0.0
	return travel+turn+float(cap.get("reaction_delay",.16))

func _tactical_scale(snapshot: Dictionary) -> float:
	return clampf(float(snapshot.get("tactical_scale",1.0)),.40,1.0)

func _screen_point(opponent:Dictionary,goal:Vector3,snapshot:Dictionary)->Vector3:
	if opponent.is_empty():return _cover_point(snapshot.ball_position,goal,snapshot)
	var ball:Vector3=snapshot.ball_position
	var receiver:Vector3=opponent.position+Vector3(opponent.velocity.x,0,opponent.velocity.z).limit_length(5.6)*.45
	var point:Vector3=ball.lerp(receiver,.62)
	point.y=0
	var toward:Vector3=Vector3(goal.x-ball.x,0,goal.z-ball.z).normalized()
	point+=toward*maxf(0,1.2-(point-ball).dot(toward))
	return _clip(point,snapshot)

# Shared live-ball forecast. No access to attacking plans or unexecuted inputs.
func _incoming_meet(snapshot:Dictionary,by_id:Dictionary)->Vector3:
	var ball:Vector3=Vector3(snapshot.ball_position.x,0,snapshot.ball_position.z)
	if int(snapshot.get("carrier_id",-1))>=0:return ball
	var samples:Array=snapshot.get("roll_samples",[])
	var choice:Vector3=ball
	var best:float=INF
	for i in range(2,samples.size(),3):
		var sample:Vector3=samples[i].point
		if sample.y>.6:continue
		if absf(sample.x)>float(snapshot.field_half_width)-.6 or absf(sample.z)>float(snapshot.field_half_length)-.6:continue
		var horizon:float=float(samples[i].get("time",(i+1)*.1))
		var arrival:float=INF
		for p in by_id.values():
			if int(p.team)==int(snapshot.get("possession_team",-1)) or roster[int(p.id)].role=="goalkeeper":continue
			arrival=minf(arrival,_eta(p,sample,snapshot))
		var cost:float=maxf(arrival,horizon)+maxf(0,arrival-horizon)*2
		if cost<best:best=cost;choice=Vector3(sample.x,0,sample.z)
	return choice
