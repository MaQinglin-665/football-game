class_name FootballTacticalDirector
extends RefCounted
## Pure tactical planning. No Node references and no changes to physics/possession.
## tick is intended for 5-10 Hz. Actors/low-level actions remain authoritative.

const PressureRoute=preload("res://scripts/tactics/pressure_route.gd")
const Roles := preload("res://scripts/tactics/role_catalog.gd")
const DefensiveTasks := preload("res://scripts/tactics/defensive_tasks.gd")
var defensive_tasks = DefensiveTasks.new()
const ReceivePlan := preload("res://scripts/tactics/receive_plan.gd")
var receive_plan = ReceivePlan.new()
const GiveGoPlan := preload("res://scripts/tactics/give_go_plan.gd")
var give_go_plan = GiveGoPlan.new()
const FIXED_SLOTS={
		"CB":[Vector2(0,-.38),Vector2(0,-.44)],
		"GK":[Vector2(0,-.90),Vector2(0,-.94)],
		"LB":[Vector2(-.66,-.18),Vector2(-.50,-.42)],
		"LCB":[Vector2(-.24,-.38),Vector2(-.22,-.44)],
		"RCB":[Vector2(.24,-.38),Vector2(.22,-.44)],
		"RB":[Vector2(.66,-.18),Vector2(.50,-.42)],
		"DM":[Vector2(0,-.18),Vector2(0,-.19)],
		"LCM":[Vector2(-.32,.05),Vector2(-.28,-.02)],
		"RCM":[Vector2(.32,.05),Vector2(.28,-.02)],
		"LW":[Vector2(-.78,.34),Vector2(-.52,.20)],
		"CF":[Vector2(0,.46),Vector2(0,.27)],
		"RW":[Vector2(.78,.34),Vector2(.52,.20)],
		"BACK":[Vector2(0,-.26),Vector2(0,-.28)],
		"LF":[Vector2(-.44,.12),Vector2(-.32,.08)],
		"RF":[Vector2(.44,.12),Vector2(.32,.08)]}
const SHORT_PASS := "short_pass"
const COUNTER := "counter"
var roster: Dictionary = {}
var eleven_duties := false
var styles: Dictionary = {0:SHORT_PASS,1:SHORT_PASS}
var clock := 0.0
var call_windows:Dictionary={}
var previous_team := -1
var observed_owner := -1
var transition_until: Dictionary = {0:0.0,1:0.0}
var loss_until: Dictionary = {0:0.0,1:0.0}
var pressers: Dictionary = {0:-1,1:-1}
var last_targets: Dictionary = {}
var give_go: Dictionary = {}
var pass_history: Array[Dictionary] = []
var territory: Dictionary = {}
var progress_time: Dictionary = {0:0.0,1:0.0}
var observation_clock := 0.0
var observed_ball := Vector3.ZERO
var observed_carrier := -1
var contact_counts := {"passes":0,"shots":0,"tackles":0,"receives":0}
var seen_contacts: Dictionary = {}
var controlled_contacts: Dictionary = {}
var carrier_setup: Dictionary = {}
var carry_routes: Dictionary = {}
var boundary_routes:Dictionary={}
var requested_support: Dictionary = {}
var next_preview: Dictionary = {}
var third_man: Dictionary = {}
var third_man_seen: Dictionary = {}
var third_man_last: Dictionary = {}
var pass_options:Dictionary={}
const TeamAttack:=preload("res://scripts/tactics/team_attack.gd")
var team_attack=TeamAttack.new()
const LearnedPolicy=preload("res://scripts/tactics/learned_team_policy.gd")
var learned_policy=LearnedPolicy.new()
var support_detours:Dictionary={}

func configure(config: Array, team_styles: Dictionary = {}) -> void:
	roster.clear()
	for row in config:
		assert(not roster.has(int(row.id)),"Player ids must be unique")
		roster[int(row.id)] = row.duplicate(true)
	eleven_duties = roster.size() in [12,18,22] # Keeper formations, historical field name
	for team in [0,1]:
		var count := 0
		for row in roster.values():
			if int(row.team)==team: count += 1
		eleven_duties = eleven_duties and count*2==roster.size()
	for team in team_styles:
		assert(team_styles[team] in [SHORT_PASS,COUNTER],"Unknown tactical style")
		styles[int(team)] = team_styles[team]
	reset()

func reset() -> void:
	learned_policy.reset()
	clock = 0.0
	call_windows.clear()
	team_attack.reset()
	previous_team = -1
	observed_owner = -1
	transition_until = {0:0.0,1:0.0}
	loss_until = {0:0.0,1:0.0}
	pressers = {0:-1,1:-1}
	last_targets.clear()
	give_go.clear()
	pass_history.clear()
	territory.clear()
	progress_time = {0:0.0,1:0.0}
	observation_clock = 0.0
	call_windows.clear()
	contact_counts = {"passes":0,"shots":0,"tackles":0,"receives":0}
	seen_contacts.clear()
	controlled_contacts.clear()
	carrier_setup.clear()
	carry_routes.clear()
	boundary_routes.clear()
	support_detours.clear()
	requested_support.clear()
	next_preview.clear()
	third_man.clear()
	third_man_seen.clear()
	third_man_last.clear()
	defensive_tasks.configure(roster)
	receive_plan.configure(roster)
	give_go_plan.configure(roster)

func cancel_defensive_tasks(reason: String) -> void:
	defensive_tasks.cancel_all(reason)

func cancel_tactical_tasks(reason: String) -> void:
	defensive_tasks.cancel_all(reason)
	team_attack.reset()
	receive_plan.cancel(reason,clock)
	give_go_plan.cancel(reason,clock)
	next_preview.clear()
	requested_support.clear()
	_cancel_third_man(reason)

func give_go_debug_snapshot() -> Dictionary:
	return give_go_plan.debug_snapshot()

func give_go_action_failed(actor_id: int, action: String) -> void:
	give_go_plan.fail_action(actor_id,clock,action)
	if action in ["PASS","SHOT"] and roster.has(actor_id):team_attack.finish(int(roster[actor_id].team),"foot_action_failed",clock)

func receive_debug_snapshot() -> Dictionary:
	return receive_plan.debug_snapshot()

func defense_debug_snapshot() -> Dictionary:
	return defensive_tasks.debug_snapshot()

func consume_contact(event: Dictionary) -> bool:
	# The scene boundary converts actor/receiver to the same stable ids used in
	# roster. Successful FOOT_TOUCH events from FootballContactHub are authoritative.
	if event.get("kind","") not in ["FOOT_TOUCH","KEEPER_RELEASE"] or not event.get("success",false):
		return false
	var actor_id := int(event.get("actor_id",-1))
	var action := String(event.get("tactical_action",event.get("action","")))
	if not roster.has(actor_id):
		return false
	var key := String(event.get("event_key","%s:%s:%s" % [event.get("physics_frame",-1),event.get("serial",-1),actor_id]))
	if seen_contacts.has(key):
		return false
	seen_contacts[key] = true
	if seen_contacts.size()>256:
		seen_contacts.erase(seen_contacts.keys()[0])
	var physical_action := String(event.get("action",""))
	if int(event.get("carrier_id",-1))==actor_id and physical_action in ["RECEIVE","STOP","SETTLE","PULL","CONTROL","CLOSE","TURN","CARRY","SHIELD"]:
		controlled_contacts[actor_id] = clock
	if physical_action=="TURN" and not String(event.get("cut_style","")).is_empty() and carry_routes.has(actor_id):carry_routes[actor_id].cut_attempted=true
	var handled: bool = receive_plan.consume_contact(event,clock)
	team_attack.control_contact(event,roster,clock)
	if event.has("space_target"):
		give_go_plan.cancel("space_delivery_owns_runners",clock)
		_cancel_third_man("space_delivery_owns_runners")
	else:give_go_plan.cancel("fixed_roles",clock)
	_cancel_third_man("fixed_roles")
	if action not in ["PASS","SHOT","CROSS","CUTBACK","CLEARANCE","TACKLE","RECEIVE"]: return handled
	record_contact(action,actor_id,int(event.get("receiver_id",-1)))
	return true

func record_contact(kind: String, actor_id: int, receiver_id := -1) -> void:
	# Call only after the engine confirms contact, not when a request is queued.
	if kind in ["PASS","CROSS","CUTBACK","CLEARANCE"]:
		team_attack.confirm_pass(int(roster[actor_id].team),actor_id,receiver_id,clock)
		contact_counts.passes += 1
		if receiver_id >= 0:
			pass_history.append({"from":actor_id,"to":receiver_id,"time":clock,"pass_id":receive_plan.active.get("pass_id","")})
			give_go[actor_id] = {"until":clock+3.2,"receiver":receiver_id,"pass_id":receive_plan.active.get("pass_id","")}
	elif kind=="SHOT":
		team_attack.finish(int(roster[actor_id].team),"actual_shot",clock)
		contact_counts.shots += 1
	elif kind=="TACKLE":
		contact_counts.tackles += 1
	elif kind=="RECEIVE":
		contact_counts.receives += 1

func tick(snapshot: Dictionary, delta: float) -> Dictionary:
	clock += clampf(delta,0.0,0.5)
	snapshot.learning_actions=learned_policy.tick(snapshot,delta)
	pass_options.clear()
	var active: Array[Dictionary] = []
	var by_id: Dictionary = {}
	for raw in snapshot.get("players",[]):
		var p: Dictionary = raw
		if p.get("active",true) and roster.has(int(p.id)):
			active.append(p)
			by_id[int(p.id)] = p
	if active.is_empty():
		cancel_tactical_tasks("no_active_players")
		return {"intents":{},"teams":{},"clock":clock}
	var owner_id: int = int(snapshot.get("carrier_id",-1))
	snapshot.tactical_clock=clock
	var owner: Dictionary = by_id.get(owner_id,{})
	var owner_team: int = int(owner.get("team",-1))
	var hand_owner:Dictionary=by_id.get(int(snapshot.get("hand_owner_id",-1)),{})
	# Short, physically observed free roll preserves only planning memory.
	# It does not grant ownership, reach or permission to kick.
	var memory_owner:int=owner_id if owner_id>=0 else int(snapshot.get("control_hint_id",-1))
	for id in controlled_contacts.keys():
		if int(id)!=memory_owner: controlled_contacts.erase(id)
	if int(carrier_setup.get("owner_id",-1))!=memory_owner: carrier_setup.clear()
	for id in carry_routes.keys():
		if int(id)!=memory_owner: carry_routes.erase(id)
	for id in boundary_routes.keys():
		if int(id)!=memory_owner:boundary_routes.erase(id)
	requested_support.clear()
	var reception: Dictionary = receive_plan.tick(snapshot,clock,delta)
	snapshot.live_reception=reception
	# Fixed-role short passing: reception remains live, scripted rotating combinations stay disabled.
	if not reception.is_empty():
		_plan_receive_continuation(reception,by_id,snapshot)
	var combination: Dictionary = {}
	var receiver_id: int = int(reception.get("receiver_id",-1))
	var receiver: Dictionary = by_id.get(receiver_id,{})
	var in_flight: bool = not reception.is_empty() and not receiver.is_empty() and (owner_team<0 or reception.get("unsettled_contact",false) and owner_id==receiver_id)
	var hint_id:int=int(snapshot.get("control_hint_id",-1))
	var possession_team: int = int(hand_owner.team) if not hand_owner.is_empty() else int(receiver.team) if in_flight else owner_team if owner_team>=0 else int(by_id.get(hint_id,{}).get("team",-1))
	_update_possession(possession_team,owner_id,snapshot)
	observation_clock -= delta
	if observation_clock<=0:
		observed_ball = snapshot.ball_position
		observed_carrier = owner_id
		observation_clock = float(snapshot.get("capabilities",{}).get("reaction_delay",0.16))
	while not pass_history.is_empty() and clock-float(pass_history[0].time)>12.0:
		pass_history.pop_front()
	# Compute the fixed receiving line once per team at the existing 5 Hz cadence.
	snapshot.fixed_offside={}
	for team in [0,1]:
		var depths:Array[float]=[]
		for other in active:
			if int(other.team)!=team:depths.append(_local(other.position,team).y)
		depths.sort()
		snapshot.fixed_offside[team]=maxf(0,maxf(_local(snapshot.ball_position,team).y,depths[depths.size()-2])-.8) if depths.size()>=2 else float(snapshot.field_half_length)
	var defense_snapshot := snapshot.duplicate(false)
	var role_targets: Dictionary = {}
	for p in active:
		var role: Dictionary = roster[int(p.id)]
		var anchor := _anchor(p,role,_phase(int(p.team),possession_team),_local(snapshot.ball_position,int(p.team)),owner,snapshot)
		role_targets[int(p.id)] = _world(_clip_role(anchor,role,snapshot),int(p.team))
	snapshot.role_targets=role_targets
	defense_snapshot.eleven_duties = eleven_duties
	defense_snapshot.role_targets = role_targets
	defense_snapshot.possession_team = possession_team
	defense_snapshot.loss_until=loss_until
	defense_snapshot.tactical_clock=clock
	var defense := defensive_tasks.tick(defense_snapshot,delta)
	var intents: Dictionary = {}
	var teams: Dictionary = {}
	for team in [0,1]:
		var phase := _phase(team,possession_team)
		var members: Array[Dictionary] = []
		var opponents: Array[Dictionary] = []
		for p in active:
			if int(p.team)==team:
				members.append(p)
			else:
				opponents.append(p)
		var presser: int = int(defense.teams.get(team,{}).get("presser_id",-1)) if possession_team!=team else _pick_presser(team,members,owner,possession_team,receiver_id,in_flight,snapshot)
		if hint_id>=0 and possession_team==team and not in_flight:presser=hint_id
		if owner_id<0 and not in_flight and hint_id<0:
			for candidate:Dictionary in members:
				if roster[int(candidate.id)].role!=Roles.GOALKEEPER or candidate.get("human",false):continue
				var local_ball:Vector2=_local(snapshot.ball_position,team)
				if local_ball.y < -float(snapshot.field_half_length)+6.5 and absf(local_ball.x)<6.0 and _keeper_claim_window(candidate,snapshot).safe:
					presser=int(candidate.id)
					break
		if snapshot.get("ball_held",false):presser=-1
		pressers[team] = presser
		teams[team] = {"phase":phase,"style":styles.get(team,SHORT_PASS),"presser_id":presser,"transition_remaining":maxf(0,float(transition_until.get(team,0))-clock)}
		snapshot.run_reservations={}
		if not third_man.is_empty() and third_man.state!="SECOND_IN_FLIGHT" and by_id.get(int(third_man.runner_id),{}).get("team",-1)==team:
			snapshot.run_reservations[int(third_man.runner_id)]=third_man.runner_target
		if not combination.is_empty() and combination.state!="RETURN_IN_FLIGHT" and by_id.get(int(combination.runner_id),{}).get("team",-1)==team:
			snapshot.run_reservations[int(combination.runner_id)]=combination.runner_goal
		if in_flight and int(receiver.team)==team:snapshot.run_reservations[receiver_id]=reception.approach_point
		var attack_plan:Dictionary=team_attack.choose(team,hand_owner if not hand_owner.is_empty() else owner,members,opponents,snapshot,roster,clock,phase)
		teams[team].attack_mode=attack_plan.get("mode","")
		teams[team].shared_plan=attack_plan.duplicate(true)
		var support_points:Dictionary={}
		for support_id in attack_plan.get("assignments",{}):
			support_points[int(support_id)]=attack_plan.assignments[support_id].point
		for support_id in support_points:
			var offer: Dictionary = by_id.get(int(support_id),{})
			if not offer.is_empty() and _distance(offer.position,support_points[support_id])<2.0 and _lane_clear(snapshot.ball_position,offer.position,opponents,1.2) and _onside_receiver(offer,opponents,snapshot):
				requested_support[int(support_id)] = true
		teams[team].support_ids = []
		for p in members:
			var role: Dictionary = roster[int(p.id)]
			var intent := _intent(p,role,phase,snapshot)
			var target: Vector2
			var ball_local := _local(snapshot.ball_position,team)
			if in_flight and int(p.id)==receiver_id:
				_apply_receive_plan(p,intent,reception)
			elif int(p.id)==presser and owner_id<0 and role.role!=Roles.GOALKEEPER:
				_press(p,intent,owner,snapshot)
			elif not third_man.is_empty() and third_man.state!="SECOND_IN_FLIGHT" and int(p.id)==int(third_man.runner_id):
				intent.third_man_plan = third_man.duplicate(false)
				intent.move_target = third_man.runner_target
				intent.face_direction = _flat(snapshot.ball_position-p.position).normalized()
				var run_gap: float = _distance(p.position,third_man.runner_target)
				var brake: float = maxf(1.0,float(snapshot.get("capabilities",{}).get("brake_deceleration",5.5)))
				intent.pace = minf(6.2,sqrt(2.0*brake*maxf(0.0,run_gap-.18)))
				intent.support_offer = true
				intent.reason = "third_man_recover_position" if third_man.get("recovering",false) else "third_man_forward_run"
			elif not combination.is_empty() and int(p.id)==int(combination.runner_id) and combination.state!="RETURN_IN_FLIGHT":
				_apply_give_go_run(intent,combination)
			elif role.role==Roles.GOALKEEPER and owner_id!=int(p.id):
				_keeper(p,intent,ball_local,snapshot,opponents)
			elif owner_id==int(p.id):
				_carrier(p,intent,snapshot,members,opponents)
				if not combination.is_empty() and int(p.id)==int(combination.wall_id): _consider_give_go_return(intent,combination,snapshot)
				_consider_third_man_pass(p,intent,by_id,snapshot)
				if intent.action=="NONE" and intent.reason in ["carry_open_channel","duty_carry_space"]:
					intent.move_target = _stable_carry_route(p,intent.move_target,opponents,snapshot)
					intent.face_direction = _flat(intent.move_target-p.position).normalized()
			elif int(p.id)==presser:
				_press(p,intent,owner,snapshot)
			else:
				target = _anchor(p,role,phase,ball_local,owner,snapshot)
				if possession_team==team and attack_plan.is_empty():
					target = _open_support(target,p,ball_local,opponents,snapshot)
					# Planned combinations replace the old unconditional timed forward run.
				if in_flight and int(receiver.get("team",-1))==team:
					target = _clear_pass_lane(target,p,receiver,snapshot)
				intent.move_target = _world(_clip_role(target,role,snapshot),team)
				if support_points.has(int(p.id)):
					intent.move_target = support_points[int(p.id)]
					intent.support_offer = true
					intent.request_ball = requested_support.has(int(p.id))
				intent.reason = "striker_offer_forward" if intent.get("support_offer",false) and role.role==Roles.STRIKER else "open_short_support" if intent.get("support_offer",false) else "cover_lane" if possession_team!=team else "counter_run" if phase=="transition_attack" and styles.get(team)==COUNTER else "short_support" if styles.get(team)==SHORT_PASS else "attack_support"
				intent.pace = 6.2 if intent.reason=="counter_run" or phase=="transition_defend" else 5.4
			var task: Dictionary = defense.tasks.get(int(p.id),{})
			if not task.is_empty() and not (task.task==DefensiveTasks.PRESS and int(p.id)!=presser) and not intent.has("receive_plan") and not intent.has("third_man_plan") and not intent.has("give_go_plan") and role.role!=Roles.GOALKEEPER and not p.get("human",false):
				_apply_defensive_task(p,intent,task,snapshot)
			if possession_team==team and not attack_plan.is_empty() and not p.get("human",false):
				_apply_team_attack(p,intent,attack_plan,by_id,opponents,snapshot)
			intents[int(p.id)] = intent
		_resolve_ball_jobs(team,members,intents,presser,receiver_id,in_flight,snapshot)
		_compact_defense(team,members,intents,snapshot,possession_team)
		teams[team].support_ids = members.filter(func(p): return intents[int(p.id)].get("support_offer",false)).map(func(p): return int(p.id))
	for id in intents:
		var intent: Dictionary = intents[id]
		var role: Dictionary = roster[id]
		var urgent_recovery: bool = intent.phase=="transition_defend" and float(loss_until.get(int(role.team),0))-clock>2.35
		if intent.action=="NONE" and not intent.press and not intent.receive and not intent.has("give_go_plan") and not intent.get("support_offer",false) and role.role!=Roles.GOALKEEPER and id!=owner_id and not urgent_recovery and intent.get("defensive_task",{}).get("task","") not in [DefensiveTasks.RECOVER,DefensiveTasks.COVER,DefensiveTasks.MARK,DefensiveTasks.SCREEN]:
			if last_targets.has(id):
				var response := 0.20 if eleven_duties and intent.get("defensive_task",{}).get("task","")==DefensiveTasks.COVER else 0.45
				var alpha := clampf(delta/response,0.20,1.0)
				intent.move_target = (last_targets[id] as Vector3).lerp(intent.move_target,alpha)
		intent.intent_owner="reception" if intent.has("receive_plan") else "carrier" if int(id)==owner_id else "defense" if intent.has("defensive_task") else "team_plan" if intent.has("shared_plan_id") else "formation"
		_route_support(by_id[int(id)],intent,snapshot,active)
		if int(id)==owner_id and not by_id[int(id)].get("human",false):
			_guard_carry_boundary(by_id[int(id)],intent,snapshot)
		_set_primary_action(intent)
	# One final spatial allocation after semantic jobs and route proposals.
	for team in [0,1]:
		var spatial_members:Array[Dictionary]=[]
		for p in active:
			if int(p.team)==team:spatial_members.append(p)
		_separate_targets(spatial_members,intents,snapshot)
	for id in intents:
		last_targets[id]=intents[id].move_target
		if intents[id].has("defensive_task"):
			intents[id].defensive_task.target=intents[id].move_target
			defensive_tasks.update_output_target(int(id),intents[id].move_target)
	_signal_open_support(intents,by_id,snapshot)
	return {"intents":intents,"teams":teams,"clock":clock,"pass_plan":reception,"give_go_plan":combination,"third_man_plan":third_man.duplicate(false),"third_man_last":third_man_last.duplicate(false)}

func _apply_give_go_run(intent: Dictionary, plan: Dictionary) -> void:
	intent.give_go_plan = plan.duplicate(true)
	intent.give_go_plan.command = "RUN"
	intent.move_target = plan.runner_goal
	intent.pace = 6.2
	intent.action = "NONE"
	intent.receive = false
	intent.press = false
	intent.shield = false
	intent.reason = "give_go_available_space"

func _consider_give_go_return(intent: Dictionary, plan: Dictionary, snapshot: Dictionary) -> void:
	if intent.reason=="confirm_control_then_turn": return
	# A better shot or materially better forward pass stays a free decision.
	if not plan.return_requested and not plan.get("return_preparing",false): return
	var team := int(plan.team)
	if intent.action=="SHOT":
		give_go_plan.cancel("better_shot",clock)
		return
	if intent.action!="NONE" and int(intent.receiver_id)!=int(plan.runner_id):
		var other_progress := _local(intent.aim_point,team).y-_local(snapshot.ball_position,team).y
		if other_progress>float(plan.progress_gain)+4.0:
			give_go_plan.cancel("better_forward_option",clock)
			return
	if not plan.return_requested:
		intent.give_go_plan = plan.duplicate(true)
		intent.give_go_plan.command = "PREPARE"
		intent.move_target = plan.wall_setup_target
		intent.face_direction = plan.return_direction
		intent.pace = 2.8
		intent.action = "NONE"
		intent.receive = false
		intent.press = false
		intent.shield = false
		intent.reason = "give_go_prepare_controlled_ball"
		return
	var distance: float = _distance(snapshot.ball_position,plan.return_target)
	_set_kick(intent,"PASS",plan.return_target,int(plan.runner_id),distance,snapshot,0.0)
	intent.give_go_plan = plan.duplicate(true)
	intent.give_go_plan.command = "RETURN"
	intent.reason = "give_go_control_then_return"

func _apply_receive_plan(_p: Dictionary, intent: Dictionary, plan: Dictionary) -> void:
	# A successful foot pass owns the receiver's primary intent until a real
	# control contact completes it or the plan reports a specific cancellation.
	intent.receive_plan = plan.duplicate(true)
	intent.move_target = plan.approach_point
	intent.face_direction = plan.face_direction
	intent.pace = plan.pace
	intent.receive = true
	intent.press = false
	intent.shield = false
	intent.action = "NONE"
	intent.receiver_id = plan.receiver_id
	intent.primary_action = "RECEIVE"
	intent.reason = "receive_plan_"+String(plan.phase).to_lower()

func _set_primary_action(intent: Dictionary) -> void:
	if intent.has("receive_plan"):
		intent.primary_action = "RECEIVE"
		intent.action = "NONE"
		intent.receive = true
		intent.press = false
		intent.shield = false
	elif intent.get("give_go_plan",{}).get("command","")=="RUN":
		intent.primary_action = "GIVE_GO_RUN"
	elif intent.action!="NONE":
		intent.primary_action = intent.action
		intent.receive = false
		intent.press = false
		intent.shield = false
	elif intent.receive:
		intent.primary_action = "RECEIVE_LOOSE"
		intent.press = false
		intent.shield = false
	elif intent.press: intent.primary_action = "PRESS"
	elif intent.shield: intent.primary_action = "SHIELD"
	else: intent.primary_action = intent.get("defensive_task",{}).get("task","KEEPER" if intent.is_goalkeeper else "MOVE")

func _apply_defensive_task(p: Dictionary, intent: Dictionary, task: Dictionary, snapshot: Dictionary) -> void:
	# One planner slot per actor. Low-level motor, shoe contact and rule gates
	# remain authoritative; defensive planning cannot queue a pass or receive.
	intent.defensive_task = task.duplicate(true)
	if task.task==DefensiveTasks.PRESS:
		if int(snapshot.get("carrier_id",-1))<0:
			intent.move_target=task.target
			intent.face_direction=_flat(task.target-p.position).normalized()
			intent.reason="defend_actual_ball_landing"
		return # _press has already applied the existing physical tackle gates.
	intent.move_target = task.target
	var travel:Vector3=_flat(task.target-p.position)
	intent.face_direction = _flat(snapshot.ball_position-p.position).normalized()
	intent.observe_ball=true
	intent.marked_opponent=int(task.target_id)
	intent.action = "NONE"
	intent.press = false
	intent.receive = false
	intent.pace = 5.8 if task.task==DefensiveTasks.RECOVER or (eleven_duties and intent.duty in ["overlap","width"] and intent.phase=="transition_defend") else 5.4
	var brake:float=maxf(1.0,float(snapshot.get("capabilities",{}).get("brake_deceleration",5.5)))
	intent.pace=minf(intent.pace,sqrt(2.0*brake*maxf(0,travel.length()-.20)))
	intent.reason = "defense_"+String(task.task).to_lower()

func _update_possession(team: int, owner_id: int, snapshot: Dictionary) -> void:
	if team>=0:
		if previous_team>=0 and team!=previous_team:
			transition_until[team] = clock+5.5
			loss_until[previous_team] = clock+3.0
			territory[team] = _local(snapshot.ball_position,team).y
			progress_time[team] = clock
		if not territory.has(team):
			territory[team] = _local(snapshot.ball_position,team).y
			progress_time[team] = clock
		var progress := _local(snapshot.ball_position,team).y
		if progress>float(territory[team])+2.0:
			territory[team] = progress
			progress_time[team] = clock
		previous_team = team
	observed_owner = owner_id

func _phase(team: int, possession_team: int) -> String:
	if possession_team==team:
		return "transition_attack" if clock<float(transition_until.get(team,0)) else "attack"
	if possession_team>=0:
		return "transition_defend" if clock<float(loss_until.get(team,0)) else "defend"
	return "loose"

func _intent(p: Dictionary, role: Dictionary, phase: String, snapshot: Dictionary) -> Dictionary:
	return {"id":int(p.id),"role":role.role,"duty":role.get("duty",""),"is_goalkeeper":role.role==Roles.GOALKEEPER,"lane":role.get("lane",0.0),"phase":phase,"human_advisory":p.get("human",false),"move_target":Vector3(p.position.x,0,p.position.z),"face_direction":_flat(snapshot.ball_position-p.position).normalized(),"pace":5.4,"press":false,"receive":false,"shield":false,"action":"NONE","receiver_id":-1,"receive_offset":Vector3.ZERO,"aim_point":snapshot.ball_position,"power01":0.0,"loft_deg":0.0,"spin":Vector3.ZERO,"power":0.0,"lift":0.0,"reason":"hold_shape"}

func _pick_presser(team: int, members: Array[Dictionary], owner: Dictionary, possession_team: int, receiver_id: int, in_flight: bool, snapshot: Dictionary) -> int:
	if possession_team==team:
		if in_flight:return receiver_id
		if int(snapshot.get("carrier_id",-1))>=0 or snapshot.get("ball_held",false):return -1
		# Keep a dribbler's brief free-roll continuation, including the human.
		var hinted:int=int(snapshot.get("control_hint_id",-1))
		if hinted>=0:
			for member in members:
				if int(member.id)==hinted and _distance(member.position,snapshot.ball_position)<1.6:return hinted
		# Without a real carrier/continuation, an unclaimed ball needs a runner.
	var best := -1
	var cost := INF
	var ball_local := _local(snapshot.ball_position,team)
	var ball_pos: Vector3 = snapshot.ball_position
	for p in members:
		var distance := _distance(p.position,ball_pos)
		var role: Dictionary = roster[int(p.id)]
		if role.role==Roles.GOALKEEPER:
			if ball_local.y>-float(snapshot.field_half_length)+6.5 or absf(ball_local.x)>6.0:
				continue
			if not _keeper_claim_window(p,snapshot).safe:
				continue
		if p.get("human",false) and (distance>2.4 or _flat(p.velocity).length()<0.8):
			continue
		var value := distance-0.85 if int(p.id)==int(pressers.get(team,-1)) else distance
		if role.role==Roles.GOALKEEPER:
			value += 1.2
		if not owner.is_empty() and role.role==Roles.CENTER_BACK and ball_local.y>-2:
			value += 1.0
		if value<cost:
			best = int(p.id)
			cost = value
	return best

func _compact_defense(team: int, members: Array[Dictionary], intents: Dictionary, snapshot: Dictionary, possession_team: int) -> void:
	# Couple covering backs to one line. Pressing remains independent; actors
	# physically accelerate toward these targets, so this does not teleport bodies.
	if possession_team<0 or possession_team==team:
		return
	var ball := _local(snapshot.ball_position,team)
	var length := float(snapshot.field_half_length)
	var line := clampf(-length*.44+clampf(ball.y*.42,-length*.42,length*.12),-length+5.0,-4.0)
	if ball.y< -length+15.0:
		line = maxf(-length+5.0,minf(line,ball.y-4.4))
	var backs := 0
	for p in members:
		if roster[int(p.id)].role in [Roles.CENTER_BACK,Roles.FULL_BACK] and not intents[int(p.id)].press:
			backs += 1
	# A five-a-side lone CB retains the stable layout. Full back-four coordination
	# only activates when there is a multi-player defensive line to coordinate.
	if backs<2:
		return
	for p in members:
		var id := int(p.id)
		var role: Dictionary = roster[id]
		var intent: Dictionary = intents[id]
		if intent.press or intent.receive or intent.get("defensive_task",{}).get("task","") in [DefensiveTasks.COVER,DefensiveTasks.MARK,DefensiveTasks.SCREEN,DefensiveTasks.RECOVER] or role.role not in [Roles.CENTER_BACK,Roles.FULL_BACK]:
			continue
		var target := _local(intent.move_target,team)
		var near_side: bool = float(role.get("lane",0.0))*ball.x>0.0
		target.x=lerpf(target.x,ball.x*.38+float(role.get("lane",0))*float(snapshot.field_half_width)*.55,.65)
		target.y = line+(2.2 if near_side else 1.0) if role.role==Roles.FULL_BACK else line
		intent.move_target = _world(_clip_pitch(target,snapshot,1.4),team)
		intent.reason = "recover_backline" if intent.phase=="transition_defend" else "compact_backline"

func _arrival_time(p: Dictionary, point: Vector3, snapshot: Dictionary, speed := 6.2) -> float:
	var cap: Dictionary = snapshot.get("capabilities",{})
	var reach := float(cap.get("receive_reach",1.16))
	var gap := maxf(0.0,_distance(p.position,point)-reach)
	var toward := _flat(point-p.position).normalized()
	var initial := clampf(_flat(p.velocity).dot(toward),0,speed)
	var acceleration := maxf(1.0,float(cap.get("run_acceleration",10.0)))
	var acceleration_time := (speed-initial)/acceleration
	var acceleration_distance := (initial+speed)*0.5*acceleration_time
	var travel := (sqrt(initial*initial+2.0*acceleration*gap)-initial)/acceleration if gap<=acceleration_distance else acceleration_time+(gap-acceleration_distance)/speed
	return travel+float(cap.get("reaction_delay",0.16))

func _keeper_claim_window(p: Dictionary, snapshot: Dictionary) -> Dictionary:
	var cap: Dictionary = snapshot.get("capabilities",{})
	var ball: Vector3 = snapshot.ball_position
	var velocity := _flat(snapshot.ball_velocity)
	var team := int(p.team)
	var length := float(snapshot.field_half_length)
	var result := {"safe":false,"point":ball,"keeper_eta":INF,"opponent_eta":INF,"teammate_eta":INF}
	if ball.y>float(cap.get("ground_receive_height",0.4)) or velocity.length()>float(cap.get("safe_receive_speed",14.0)):
		return result
	var owner := int(snapshot.get("carrier_id",-1))
	if owner>=0:
		# Already-controlled balls have no safe loose-ball claim. A reachable
		# standing poke is allowed by the unchanged low-level action gates.
		if _distance(p.position,ball)<=float(cap.get("tackle_reach",1.18)) and p.get("can_reach",true):
			result.safe = true
		return result
	var keeper_speed := maxf(1.0,float(cap.get("keeper_speed",6.2)))
	var margin := maxf(0.0,float(cap.get("keeper_claim_margin",0.20)))
	for i in range(1,9):
		var horizon := float(i)*0.15
		var point := ball+velocity*horizon
		var local := _local(point,team)
		if local.y< -length+0.6 or local.y> -length+5.7 or absf(local.x)>5.7:
			continue
		var eta := _arrival_time(p,point,snapshot,keeper_speed)
		if eta>horizon+0.03:
			continue
		var opponent_eta := INF
		var teammate_eta := INF
		for other in snapshot.get("players",[]):
			if not other.get("active",true) or int(other.id)==int(p.id) or not roster.has(int(other.id)):
				continue
			var other_eta := _arrival_time(other,point,snapshot)
			if int(other.team)==team:
				teammate_eta = minf(teammate_eta,other_eta)
			else:
				opponent_eta = minf(opponent_eta,other_eta)
		if eta+margin<opponent_eta and eta+0.05<teammate_eta:
			result = {"safe":true,"point":point,"keeper_eta":eta,"opponent_eta":opponent_eta,"teammate_eta":teammate_eta}
			return result
	return result

func _anchor(p:Dictionary,role:Dictionary,phase:String,ball:Vector2,_owner:Dictionary,snapshot:Dictionary)->Vector2:
	var attack:bool=phase in ["attack","transition_attack"]
	var slot:String=String(role.get("slot",""))
	var w:float=float(snapshot.field_half_width)
	var length:float=float(snapshot.field_half_length)

	var nominal:Vector2=FIXED_SLOTS.get(slot,[Vector2(0,0),Vector2(0,-.2)])[0 if attack else 1]
	var center:float=clampf(ball.y*(.58 if attack else .42),-length*.42,length*(.38 if attack else .12))
	var anchor:=Vector2(nominal.x*w+ball.x*(.12 if attack else .20),nominal.y*length+center)
	if slot=="GK":return Vector2(ball.x*.10,-length*.93)
	if attack:
		# Keep assigned flanks and a legal, moving receiving line.
		if eleven_duties:anchor.y=minf(anchor.y,float(snapshot.fixed_offside.get(int(p.team),length)))
	if absf(nominal.x)>.1:anchor.x=signf(nominal.x)*maxf(absf(anchor.x),w*.12)
	return _clip_pitch(anchor,snapshot,1.8)

func _duty_anchor(anchor: Vector2, p: Dictionary, role: Dictionary, attacking: bool, ball: Vector2, snapshot: Dictionary) -> Vector2:
	var length := float(snapshot.field_half_length)
	var w := float(snapshot.field_half_width)
	var lane := float(role.get("lane",0.0))
	match String(role.get("duty","")):
		"hold":
			anchor.y = minf(anchor.y,ball.y-length*(0.17 if attacking else 0.20))
		"cover":
			if attacking: anchor.y = minf(anchor.y,ball.y-length*0.19)
		"overlap":
			if attacking and _overlap_available(p,role,ball,snapshot):
				anchor = Vector2(lane*w*0.80,minf(length*0.50,ball.y+length*0.12))
			elif attacking: anchor.y = minf(anchor.y,ball.y-length*0.14)
		"support":
			if attacking: anchor = Vector2(ball.x-lane*w*0.22,ball.y-length*0.045)
		"link":
			anchor.y = minf(anchor.y,ball.y+length*0.035) if attacking else minf(anchor.y,ball.y-length*0.10)
		"width":
			anchor.x = lane*w*(0.78 if attacking else 0.58)
			if attacking: anchor.y = maxf(anchor.y,ball.y+length*0.10)
		"finish":
			anchor.y = maxf(anchor.y,ball.y+length*0.17) if attacking else maxf(anchor.y,ball.y-length*0.10)
	return anchor

func _overlap_available(p: Dictionary, role: Dictionary, ball: Vector2, snapshot: Dictionary) -> bool:
	var lane := float(role.get("lane",0.0))
	var w := float(snapshot.field_half_width)
	if lane*ball.x<w*0.35: return false
	var destination := Vector2(lane*w*0.80,minf(float(snapshot.field_half_length)*0.50,ball.y+float(snapshot.field_half_length)*0.12))
	var protected := false
	var opponents: Array[Dictionary] = []
	for other in snapshot.get("players",[]):
		if not other.get("active",true) or not roster.has(int(other.id)): continue
		var local := _local(other.position,int(p.team))
		if int(other.team)!=int(p.team):
			opponents.append(other)
			if local.distance_to(destination)<w*0.12: return false
		elif int(other.id)!=int(p.id) and roster[int(other.id)].get("duty","") in ["hold","cover"]:
			if local.y<ball.y-float(snapshot.field_half_length)*0.08 and absf(local.x-ball.x)<w*0.55: protected = true
	return protected and _lane_clear(p.position,_world(destination,int(p.team)),opponents,1.7)

func _open_support(anchor: Vector2, p: Dictionary, ball: Vector2, opponents: Array[Dictionary], snapshot: Dictionary) -> Vector2:
	if eleven_duties: return _duty_support(anchor,p,ball,opponents,snapshot)
	var target := anchor
	var side := signf(target.x) if absf(target.x)>0.5 else (1.0 if int(p.id)%2==0 else -1.0)
	for other in opponents:
		var opp := _local(other.position,int(p.team))
		if opp.distance_to(target)<3.1:
			target.x += side*1.7
		var line := target-ball
		if line.length()>4.0:
			var t := clampf((opp-ball).dot(line)/line.length_squared(),0,1)
			if t>0.10 and t<0.88 and opp.distance_to(ball+line*t)<1.45:
				target.y += 2.4
				target.x += side*1.1
	return _clip_pitch(target,snapshot,2.0)

func _duty_support(anchor: Vector2, p: Dictionary, ball: Vector2, opponents: Array[Dictionary], snapshot: Dictionary) -> Vector2:
	var role: Dictionary = roster[int(p.id)]
	var duty := String(role.get("duty",""))
	var step := float(snapshot.field_half_width)*0.09
	var best := anchor
	var score := -INF
	for offset in [Vector2.ZERO,Vector2(step,0),Vector2(-step,0),Vector2(step,step),Vector2(-step,step),Vector2(0,-step)]:
		var point := _clip_role(anchor+offset,role,snapshot)
		var world := _world(point,int(p.team))
		var value := _openness(world,opponents)-point.distance_to(anchor)*0.30
		value += clampf(point.y-ball.y,-step*2,step*2)*(0.08 if duty in ["hold","cover","link"] else 0.25)
		if not _lane_clear(snapshot.ball_position,world,opponents,1.20): value -= 6.0
		if duty=="width": value += absf(point.x)*0.18
		if duty=="support": value -= absf(point.distance_to(ball)-float(snapshot.field_half_width)*0.30)*0.35
		if value>score:
			score = value
			best = point
	return best

func _give_and_go(anchor: Vector2, p: Dictionary, by_id: Dictionary, snapshot: Dictionary) -> Vector2:
	if not give_go.has(int(p.id)) or roster[int(p.id)].role in [Roles.GOALKEEPER,Roles.CENTER_BACK]:
		return anchor
	var memory: Dictionary = give_go[int(p.id)]
	if clock>float(memory.until) or not by_id.has(int(memory.receiver)):
		return anchor
	var receiver: Dictionary = by_id[int(memory.receiver)]
	var current := _local(p.position,int(p.team))
	var received := _local(receiver.position,int(p.team))
	var run := Vector2(current.x, maxf(current.y+6.0,received.y+3.8))
	if absf(run.x-received.x)<3.5:
		run.x += -3.8 if current.x<=received.x else 3.8
	return _clip_pitch(run,snapshot,3.0)

func _clear_pass_lane(anchor: Vector2, p: Dictionary, receiver: Dictionary, snapshot: Dictionary) -> Vector2:
	var ball := _local(snapshot.ball_position,int(p.team))
	var end := _local(receiver.position,int(p.team))
	var current := _local(p.position,int(p.team))
	var line := end-ball
	if line.length_squared()<0.1:
		return anchor
	var fraction := clampf((current-ball).dot(line)/line.length_squared(),0,1)
	var away := current-(ball+line*fraction)
	if fraction>0.05 and fraction<0.96 and away.length()<1.7:
		if away.length()<0.05:
			away = Vector2(-line.y,line.x).normalized()*(1.0 if int(p.id)%2 else -1.0)
		return current+away.normalized()*2.7
	return anchor

func _separate_targets(members:Array[Dictionary],intents:Dictionary,snapshot:Dictionary)->void:
	var ranked:Array[Dictionary]=[]
	for p in members:
		var intent:Dictionary=intents[int(p.id)]
		var fixed:bool=p.get("human",false) or int(p.id)==int(snapshot.carrier_id) or intent.receive or intent.press or intent.role==Roles.GOALKEEPER or intent.get("plan_endpoint",false) or intent.get("support_route",false)
		var task:String=String(intent.get("defensive_task",{}).get("task",""))
		var priority:int=0 if fixed else 1 if task==DefensiveTasks.COVER else 2 if task in [DefensiveTasks.MARK,DefensiveTasks.SCREEN] else 3
		ranked.append({"actor":p,"fixed":fixed,"priority":priority})
	ranked.sort_custom(func(a,b):return int(a.actor.id)<int(b.actor.id) if a.priority==b.priority else a.priority<b.priority)
	var reserved:Array[Dictionary]=[]
	var spacing:float=2.0 if snapshot.get("small_sided",false) else 3.1
	for row in ranked:
		var p:Dictionary=row.actor
		var intent:Dictionary=intents[int(p.id)]
		var nominal:Vector3=intent.move_target
		var chosen:Vector3=nominal
		var best:float=INF
		intent.space_nominal=nominal
		if not row.fixed:
			var step:float=1.45 if snapshot.get("small_sided",false) else 2.3
			for shift in [Vector2.ZERO,Vector2(-1,0),Vector2(1,0),Vector2(0,-1),Vector2(0,1),Vector2(-.7,-.7),Vector2(.7,-.7)]:
				var local:Vector2=_local(nominal,int(p.team))+shift*step
				var candidate:Vector3=_world(_clip_pitch(local,snapshot,1.0),int(p.team))
				var cost:float=_distance(candidate,nominal)*.8+_distance(p.position,candidate)*.08
				for slot in reserved:
					cost+=pow(maxf(0,spacing-_distance(candidate,slot.point)),2)*5.0
					cost+=pow(maxf(0,1.25-_distance(candidate,slot.body)),2)*3.0
				# Don't turn a marked player's goal-side cover into a run behind them.
				var task:Dictionary=intent.get("defensive_task",{})
				if task.get("task","") in [DefensiveTasks.MARK,DefensiveTasks.SCREEN] and _local(candidate,int(p.team)).y>_local(nominal,int(p.team)).y+.8:cost+=3.0
				if cost<best:best=cost;chosen=candidate
			intent.move_target=chosen
			if intent.get("observe_ball",false):intent.face_direction=_flat(snapshot.ball_position-p.position).normalized()
		# Reserve the live human/carrier position, not a stale advisory target.
		var reserved_point:Vector3=p.position if p.get("human",false) or int(p.id)==int(snapshot.carrier_id) else chosen
		reserved.append({"point":reserved_point,"body":p.position+_flat(p.velocity)*.25})


func _press(p: Dictionary, intent: Dictionary, owner: Dictionary, snapshot: Dictionary) -> void:
	var ball: Vector3 = snapshot.ball_position
	var team := int(p.team)
	var cap: Dictionary = snapshot.get("capabilities",{})
	intent.press = true
	intent.pace = 6.2
	intent.face_direction = _flat(ball-p.position).normalized()
	if owner.is_empty():
		intent.move_target = _receiving_point(p,snapshot)
		intent.receive = true
		intent.reason = "recover_loose_ball"
		return
	if _distance(p.position,owner.position)<3.0:
		var goalward:Vector3=_flat(_world(Vector2(0,-float(snapshot.field_half_length)),team)-owner.position).normalized()
		intent.move_target=preload("res://scripts/body_pressure.gd").target(p.position,owner.position,owner.get("velocity",Vector3.ZERO),ball,goalward)
		intent.pace=minf(6.2,maxf(.7,_flat(owner.get("velocity",Vector3.ZERO)).length()+_distance(p.position,intent.move_target)*2.5))
		intent.reason="body_pressure_shoulder"
		var shoe_lane:Vector3=_flat(ball-p.position)
		var carrier_screen:Vector3=Geometry3D.get_closest_point_to_segment(_flat(owner.position),_flat(p.position),_flat(ball))
		var exposed:bool=_distance(carrier_screen,owner.position)>.34 or _distance(p.position,ball)<_distance(p.position,owner.position)-.12
		if shoe_lane.length()<float(cap.get("tackle_reach",1.18)) and ball.y<.40 and exposed and _flat(p.facing).normalized().dot(shoe_lane.normalized())>.72 and observed_carrier==int(owner.id) and p.get("can_reach",false) and p.get("tackle_ready",true) and p.get("foot_idle",true):
			intent.action="TACKLE"
			intent.aim_point=ball
		return
	if _flat(owner.get("velocity",Vector3.ZERO)).length()>1.8:
		_press_running_lane(p,intent,owner,snapshot)
		return
	var attacker := _local(owner.position,team)
	var current := _local(p.position,team)
	var small: bool = not eleven_duties and snapshot.get("small_sided",false)
	var toward_defender := _flat(p.position-owner.position).normalized()
	var seen_offset := _flat(observed_ball-owner.position)
	var live_offset := _flat(ball-owner.position)
	var visible: bool = seen_offset.length()>=.30 and live_offset.length()>=.30 and seen_offset.normalized().dot(toward_defender)>.60 and live_offset.normalized().dot(toward_defender)>.60 and not owner.get("shielding",false) and owner.get("foot_action","")!="SHIELD"
	var standoff := (.95 if visible else 1.20) if small else float(cap.get("standoff",1.4))
	if eleven_duties:
		standoff = 1.10 if intent.duty in ["hold","cover"] else 0.95
	var target := attacker+Vector2(clampf((_local(ball,team)-attacker).x*0.25,-0.4,0.4),-standoff)
	if current.y>attacker.y+0.5:
		target.y -= 1.0
		intent.reason = "recover_goal_side"
	else:
		intent.pace = 4.1 if current.distance_to(attacker)<3.5 else 5.8
		intent.reason = "press_ball"
		if small:
			var near: bool = current.distance_to(attacker)<2.3
			intent.pace = clampf(current.distance_to(target)*2.2,.65,2.0) if near else 5.8
			intent.reason = "contain_carrier" if near else "approach_carrier"
	if eleven_duties and current.y<=attacker.y+0.5:
		intent.pace = 3.2 if current.distance_to(attacker)<2.0 else 5.8
		intent.reason = "duty_jockey" if current.distance_to(attacker)<2.0 else "duty_close_pressure"
	var distance := _distance(p.position,observed_ball)
	var exposed: bool = _distance(owner.position,observed_ball)>float(cap.get("exposed_gap",0.90)) or distance<0.70
	var reach := float(cap.get("tackle_reach",1.18))
	if eleven_duties:
		var live_distance := _distance(p.position,ball)
		var facing_ball := _flat(p.get("facing",Vector3.FORWARD)).normalized().dot(_flat(ball-p.position).normalized())>0.87
		var slow_owner := _flat(owner.get("velocity",Vector3.ZERO)).length()<1.5
		exposed = exposed or (slow_owner and live_distance<minf(1.2,reach) and facing_ball)
	elif small: exposed = exposed or (visible and distance<=reach)
	if observed_carrier==int(snapshot.get("carrier_id",-1)) and exposed and distance<=reach and _distance(p.position,ball)<=reach and float(ball.y)<=float(cap.get("ground_receive_height",0.40)) and p.get("tackle_ready",true) and p.get("foot_idle",true) and p.get("can_reach",true):
		intent.action = "TACKLE"
		intent.reason = "poke_exposed_ball"
		intent.aim_point = ball
	var predicted:Vector3=ball+_flat(snapshot.ball_velocity)*.14
	var approach:Vector3=_flat(p.position-predicted).normalized()
	if _flat(owner.get("velocity",Vector3.ZERO)).length()>1.2 and _distance(p.position,ball)>1.4:
		var goal_side:Vector3=_flat(_world(Vector2(0,-float(snapshot.field_half_length)),team)-predicted).normalized()
		approach=(approach*.65+goal_side*.35).normalized()
	var ball_side:Vector3=predicted+approach*.62
	# Approach the ball-facing side of a stationary shield instead of pressing
	# forever into the carrier's torso. Waypoint stays outside the body radius.
	if _flat(owner.get("velocity",Vector3.ZERO)).length()<1.2 and _distance(p.position,ball)<3.0:
		var exposed_side:Vector3=_flat(ball-owner.position).normalized()
		if exposed_side.length_squared()<.01:exposed_side=_flat(owner.get("facing",Vector3.FORWARD)).normalized()
		var from_owner:Vector3=_flat(p.position-owner.position).normalized()
		if from_owner.dot(exposed_side)<.35:
			var flank:Vector3=Vector3(-exposed_side.z,0,exposed_side.x)
			if flank.dot(from_owner)<0:flank=-flank
			ball_side=owner.position+flank*.78+exposed_side*.32
		else:ball_side=ball+exposed_side*.60
		target=_local(ball_side,team)
		intent.pace=clampf(_distance(p.position,ball_side)*2.7+.25,.65,3.2)
		intent.reason="approach_open_shoe_lane"
	elif _distance(p.position,ball)<3.0 and p.get("can_reach",true):
		target=_local(ball_side,team)
		intent.pace=clampf(_distance(p.position,ball_side)*3.0+.65,1.1,4.2)
		intent.reason="track_touch_window"
	intent.move_target = _world(_clip_pitch(target,snapshot,0.6),team)

func _receiving_point(p: Dictionary, snapshot: Dictionary) -> Vector3:
	var ball: Vector3 = snapshot.ball_position
	var vel := _flat(snapshot.ball_velocity)
	var samples:Array=snapshot.get("roll_samples",[])
	if not samples.is_empty():
		var best:Vector3=ball
		var best_late:float=INF
		for sample in samples:
			var point:Vector3=sample.point
			if point.y>.42 or absf(point.x)>float(snapshot.field_half_width)-.6 or absf(point.z)>float(snapshot.field_half_length)-.6:continue
			var face:Vector3=_flat(point-p.position).normalized()
			var meet:Vector3=_flat(point)-face*.38
			var late:float=team_attack.eta(p,meet)-float(sample.time)
			if late<best_late:best_late=late;best=meet
			if late<=0:break
		if is_finite(best_late):return best
	var distance := _distance(p.position,ball)
	var seconds := clampf(distance/10.0,0.02,0.65)
	var projected := ball+vel*seconds
	# A moving receiver attacks the flight path instead of chasing its own lead.
	if vel.length()>0.8:
		var local_p := Vector2(p.position.x,p.position.z)
		var a := Vector2(ball.x,ball.z)
		var b := Vector2(projected.x,projected.z)
		var segment := b-a
		var t := clampf((local_p-a).dot(segment)/maxf(segment.length_squared(),0.001),0,1)
		projected.x = lerpf(a.x,b.x,t)
		projected.z = lerpf(a.y,b.y,t)
	# Stop on the near side, so the boot sees the ball in front at reception.
	var approach := _flat(ball-p.position).normalized()
	projected -= approach*0.36
	return _world(_clip_pitch(_local(projected,int(p.team)),snapshot,0.6),int(p.team))

func _keeper(p: Dictionary, intent: Dictionary, ball: Vector2, snapshot: Dictionary, opponents: Array[Dictionary]) -> void:
	var team := int(p.team)
	var length := float(snapshot.field_half_length)
	var goal_half := float(snapshot.get("goal_half_width",3.66))
	var cap: Dictionary = snapshot.get("capabilities",{})
	var current := _local(p.position,team)
	var depth := clampf((ball.y+length)*0.055,1.20,3.40)
	var target := Vector2(clampf(ball.x*depth/maxf(ball.y+length,3.5),-goal_half+0.45,goal_half-0.45),-length+depth)
	var velocity := _local_velocity(snapshot.ball_velocity,team)
	intent.reason = "keeper_angle"
	intent.pace = 5.4
	if velocity.y < -2.0 and ball.y>current.y:
		var seconds := (target.y-ball.y)/velocity.y
		var height := float(snapshot.ball_position.y)+float(snapshot.ball_velocity.y)*seconds-4.9*seconds*seconds
		var crossing_x := ball.x+velocity.x*seconds
		if seconds>0 and seconds<1.8 and absf(crossing_x)<goal_half+0.25 and height<1.85:
			target.x = clampf(crossing_x,-goal_half+0.28,goal_half-0.28)
			intent.reason = "keeper_block_line"
			intent.pace = 6.2
	var distance := _distance(p.position,snapshot.ball_position)
	var carrier_id := int(snapshot.get("carrier_id",-1))
	var owns_enemy := false
	for opponent in opponents:
		if int(opponent.id)==carrier_id:
			owns_enemy = true
	var own_box := ball.y<-length+6.5 and absf(ball.x)<6.0
	if own_box and (carrier_id<0 or owns_enemy):
		var window := _keeper_claim_window(p,snapshot)
		# A receiver hint can select the keeper without running the loose-ball
		# race gate. Fast/airborne intended passes still need blocking/angle cover.
		if window.safe:
			target = _local(window.point,team)
			target.y = clampf(target.y,-length+0.6,-length+5.7)
			target.x = clampf(target.x,-5.7,5.7)
			intent.receive = not owns_enemy
			intent.press = owns_enemy
			intent.reason = "keeper_claim_ground" if not owns_enemy else "keeper_close_angle"
			intent.pace = 6.2
	var grounded: bool = float(snapshot.ball_position.y)<=float(cap.get("ground_receive_height",0.40))
	if distance<=float(cap.get("receive_reach",1.16)) and grounded and p.get("foot_idle",true) and p.get("can_reach",true):
		if carrier_id<0 and _flat(snapshot.ball_velocity).length()<=float(cap.get("safe_receive_speed",14.0)):
			intent.action = "RECEIVE"
			intent.reason = "keeper_safe_receive"
		elif owns_enemy and distance<=float(cap.get("tackle_reach",1.18)) and p.get("tackle_ready",true):
			intent.action = "TACKLE"
			intent.reason = "keeper_ground_block"
	intent.move_target = _world(target,team)
	intent.face_direction = _flat(snapshot.ball_position-p.position).normalized()
	intent.aim_point = snapshot.ball_position

func _carrier(p: Dictionary, intent: Dictionary, snapshot: Dictionary, members: Array[Dictionary], opponents: Array[Dictionary]) -> void:
	var team := int(p.team)
	if _resume_receive(p,intent,snapshot,members,opponents):return
	if _wait_for_control(p,intent,snapshot,members,opponents): return
	if p.get("kick_ready",false) and p.get("can_kick",false) and not p.get("kick_setup_blocked",false):
		var shot:Dictionary=_shot_option(p,opponents,snapshot)
		if not shot.is_empty():
			intent.action="SHOT"
			intent.aim_point=shot.point
			intent.face_direction=_flat(shot.point-snapshot.ball_position).normalized()
			intent.power01=shot.power
			intent.power=lerpf(9.0,30.0,shot.power)
			intent.lift=.9
			intent.loft_deg=2.2
			intent.reason="shoot_observed_open_goal"
			return
	var current := _local(p.position,team)
	var length := float(snapshot.field_half_length)
	var w := float(snapshot.field_half_width)
	var pressure := _openness(p.position,opponents)
	var style: String = styles.get(team,SHORT_PASS)
	var age := float(snapshot.get("possession_age",0.0))
	var stalled := clock-float(progress_time.get(team,clock))>6.5
	var scale := _tactical_scale(snapshot)
	var carry:Dictionary=_open_carry_option(p,opponents,snapshot)
	intent.move_target=carry.point if not carry.is_empty() else _carry_space_target(p,opponents,snapshot,null)
	intent.face_direction=_flat(intent.move_target-p.position).normalized()
	intent.reason="carry_"+String(carry.get("style","SHIELD_EXIT")).to_lower()
	var pressure_state:Dictionary=PressureRoute.inspect(p,intent.move_target,opponents)
	intent.pressure_read=pressure_state
	intent.shield=pressure_state.contact_time<.40 and pressure_state.frontal and (carry.is_empty() or carry.get("style","")=="SHIELD_EXIT")
	intent.close_control=intent.shield or not carry.is_empty() and float(carry.get("immediate",carry.clearance))<1.05
	intent.pace=2.4 if intent.close_control else 4.8
	_apply_carry_gear(p,intent,carry,opponents,snapshot)
	intent["carry_choice"]=carry
	if p.get("kick_setup_blocked",false) or not p.get("kick_ready",true) or not p.get("can_pass",p.get("can_kick",true)):
		return
	var best := _best_pass(p,members,opponents,snapshot,style)
	if intent.role==Roles.GOALKEEPER:
		intent.move_target = Vector3(p.position.x,0,p.position.z)
		intent.reason = "keeper_outlet"
		if not best.is_empty() and age>0.45:
			_set_kick(intent,"PASS",best.point,int(best.id),float(best.distance),snapshot,0.30)
			var lofts:Array=snapshot.get("loft_delivery",[])
			var selected:Dictionary={}
			for delivery:Dictionary in lofts:
				if selected.is_empty() or absf(float(delivery.distance)-float(best.distance))<absf(float(selected.distance)-float(best.distance)):selected=delivery
			if not selected.is_empty() and float(best.distance)>9.0:
				intent.power01=selected.power
				intent.loft_deg=selected.loft
				intent.space_target=best.point
				intent.space_origin=snapshot.ball_position
				intent.space_valid_until=clock+.6
				intent.reason="keeper_loft_to_teammate"
		elif age>2.0:
			var clear := Vector2(-signf(current.x+0.01)*w*0.63,minf(2.0,current.y+22.0))
			var clear_world := _world(clear,team)
			if _lane_clear(p.position,clear_world,opponents,1.1):
				_set_kick(intent,"CLEARANCE",clear_world,-1,_distance(p.position,clear_world),snapshot,0.9)
		return
	if best.is_empty():
		return
	var called:bool=int(snapshot.get("call_id",-1))==int(best.id)
	var forward:bool=float(best.progress)>maxf(1.4,2.5*scale)
	var risk:float=float(carry.get("risk",1.0))
	var pass_value:float=_pass_value(best,carry,snapshot)
	if style==SHORT_PASS and forward:pass_value+=.45
	var danger:bool=carry.is_empty() or (pressure<.80 and float(carry.get("clearance",0.0))<1.05)
	var valuable:bool=pass_value>float(carry.get("score",-100.0))+(0.65 if carry.get("committed",false) else .25)
	var release:bool=called or danger or valuable or stalled
	if release:
		_set_kick(intent,"PASS",best.point,int(best.id),float(best.distance),snapshot,0.0)
		intent.reason="called_pass" if called else "advance_to_free_teammate" if forward else "pressure_safe_outlet"

func _best_pass(p: Dictionary, members: Array[Dictionary], opponents: Array[Dictionary], snapshot: Dictionary, style: String) -> Dictionary:
	var cache_key:String=str(p.id)+":"+str(snapshot.ball_position)
	if pass_options.has(cache_key):return pass_options[cache_key]
	var best: Dictionary = {}
	var score := -INF
	var current := _local(p.position,int(p.team))
	var keeper: bool = roster[int(p.id)].role==Roles.GOALKEEPER
	for other in members:
		if int(other.id)==int(p.id):
			continue
		var distance := _distance(p.position,other.position)
		var scale := _tactical_scale(snapshot)
		var max_distance: float = (30.0 if keeper else 34.0 if style==COUNTER else 23.0)*scale
		if distance<maxf(2.0,3.2*scale) or distance>max_distance:
			continue
		var local_other := _local(other.position,int(p.team))
		var progress := local_other.y-current.y
		if keeper and (progress<3.0 or roster[int(other.id)].role==Roles.GOALKEEPER):
			continue
		if roster[int(other.id)].role==Roles.GOALKEEPER and progress< -4 and _openness(p.position,opponents)>3.2:
			continue
		var power := clampf(distance*1.05+7.5,10.0,24.0)
		var delivery:Dictionary=_pass_profile(distance,snapshot)
		var point:Vector3=other.position+(_flat(other.velocity).limit_length(7.0)*float(delivery.time)).limit_length(minf(2.0,distance*.20))
		power=float(delivery.speed)
		point = _world(_clip_pitch(_local(point,int(p.team)),snapshot,1.6),int(p.team))
		if not _lane_clear(snapshot.ball_position,point,opponents,1.20):
			continue
		if not _delivery_safe(p,other,point,power,opponents,snapshot):
			continue
		var open := _openness(point,opponents)
		if open<1.6:
			continue
		var called := int(snapshot.get("call_id",-1))==int(other.id)
		var repeated := _return_penalty(int(p.id),int(other.id),progress)
		if _openness(p.position,opponents)<2.8:repeated*=.15 # A safe pressured return is useful, not a forbidden pair.
		if repeated>20 and not called:
			continue
		var proposal:Dictionary={"point":point,"flight":delivery.time}
		var utility:float=team_attack._value(p,other,proposal,opponents,snapshot)+LearnedPolicy.bias(int(snapshot.get("learning_actions",{}).get(int(p.team),0)),"PASS")
		var value:float=utility-minf(repeated,8.0)*.20
		if requested_support.has(int(other.id)):value+=.35
		if called:
			value += 30.0
		if progress< -2.0:
			value -= .5 if _openness(p.position,opponents)<3.6 else 3.0
		if value>score:
			score = value
			best = {"id":int(other.id),"point":point,"distance":distance,"progress":progress,"score":value,"open":open,"utility":utility}
	pass_options[cache_key]=best
	return best

func _delivery_safe(p: Dictionary, receiver: Dictionary, point: Vector3, power: float, opponents: Array[Dictionary], snapshot: Dictionary) -> bool:
	if eleven_duties and not _onside_receiver(receiver,opponents,snapshot): return false
	# Predict the same soft boot-side delivery that _set_kick will request for
	# a stationary human. A nominal 24m/s check cannot validate an 18m/s pass.
	var actual_point := point
	var actual_power := power
	if receiver.get("human",false) and _flat(receiver.velocity).length()<0.8:
		actual_power = minf(actual_power,18.0)
		actual_point += _flat(receiver.get("facing",Vector3.FORWARD)).normalized()*0.45
	return _pass_preparation_safe(p,actual_point,opponents,snapshot) and _pass_window_safe(snapshot.ball_position,actual_point,opponents,actual_power,snapshot)

func _onside_receiver(receiver: Dictionary, opponents: Array[Dictionary], snapshot: Dictionary) -> bool:
	# Planning filter only. Rules still judge actual positions at real kick contact.
	# The receiver's current position, not a future aim point, defines eligibility.
	var team := int(receiver.team)
	var y := _local(receiver.position,team).y
	var ball_y := _local(snapshot.ball_position,team).y
	if y<=0.0 or y<=ball_y: return true
	var line: Array[float] = []
	for other in opponents: line.append(_local(other.position,team).y)
	line.sort()
	if line.size()<2: return false
	return y<=maxf(ball_y,line[line.size()-2])-0.35

func _pass_preparation_safe(p: Dictionary, point: Vector3, opponents: Array[Dictionary], snapshot: Dictionary) -> bool:
	var prepare_seconds:float=team_attack._setup(p,point)
	for opponent in opponents:
		if team_attack.eta(opponent,snapshot.ball_position)<prepare_seconds+.08:return false
	return true

func _pass_window_safe(start: Vector3, point: Vector3, opponents: Array[Dictionary], power: float, snapshot: Dictionary) -> bool:
	# Predict only from observed velocity. No future inputs, force application,
	# ownership changes or remote catches. Short horizons limit extrapolation.
	var cap: Dictionary = snapshot.get("capabilities",{})
	var speed := clampf(power*float(cap.get("pass_speed_scale",1.0)),6.0,32.0)
	var line := _flat(point-start)
	var flight:float=float(_pass_profile(line.length(),snapshot).time)
	var positions:=PackedVector3Array()
	var velocities:=PackedVector3Array()
	for opponent in opponents:
		positions.append(opponent.position)
		velocities.append(_flat(opponent.velocity).limit_length(9.5))
	for i in range(1,10):
		var fraction := float(i)/10.0
		var seconds := flight*fraction
		var ball_point := start+line*fraction
		var clearance := 1.10+minf(0.30,seconds*0.30)
		for j in positions.size():
			var future: Vector3 = positions[j]+velocities[j]*minf(seconds,0.75)
			if _distance(ball_point,future)<clearance:
				return false
	return true

func _return_penalty(from_id: int, to_id: int, progress: float) -> float:
	var penalty := 0.0
	var pair_count := 0
	for previous in pass_history:
		var age := clock-float(previous.time)
		if int(previous.from)==to_id and int(previous.to)==from_id:
			if age<2.4 and progress<3.0:
				return 30.0
			if age<6.0:
				penalty += 8.0 if progress<2 else 1.0
		if age<8.0 and ((int(previous.from)==from_id and int(previous.to)==to_id) or (int(previous.from)==to_id and int(previous.to)==from_id)):
			pair_count += 1
	if pair_count>=2:
		penalty += 24.0 if progress<3.0 else 4.0
	return penalty

func _wide_delivery(p: Dictionary, members: Array[Dictionary], opponents: Array[Dictionary], snapshot: Dictionary) -> Dictionary:
	var current := _local(p.position,int(p.team))
	var length := float(snapshot.field_half_length)
	var best: Dictionary = {}
	var score := -INF
	for other in members:
		if int(other.id)==int(p.id) or roster[int(other.id)].role in [Roles.GOALKEEPER,Roles.CENTER_BACK]:
			continue
		var receiver := _local(other.position,int(p.team))
		if absf(receiver.x)>8.0 or receiver.y<length-18.0 or receiver.y>length-1.8:
			continue
		var progress := receiver.y-current.y
		if progress< -11.0 or progress>8.0:
			continue
		var distance := _distance(p.position,other.position)
		var point: Vector3 = other.position+_flat(other.velocity)*0.25
		if not _lane_clear(snapshot.ball_position,point,opponents,1.15) or _openness(point,opponents)<2.0:
			continue
		var power := clampf(distance*1.05+7.5,10.0,24.0)
		if not _delivery_safe(p,other,point,power,opponents,snapshot):
			continue
		var kind := "CUTBACK" if progress< -1.5 else "CROSS"
		var value := _openness(point,opponents)-absf(progress)*0.12+(2.0 if kind=="CUTBACK" else 0.0)
		if value>score:
			score = value
			best = {"id":int(other.id),"point":point,"distance":distance,"kind":kind,"lift":0.30 if kind=="CUTBACK" else 0.95}
	return best

func _shot_point(p: Dictionary, opponents: Array[Dictionary], snapshot: Dictionary) -> Vector3:
	var keeper_x := 0.0
	var team := int(p.team)
	for other in opponents:
		if roster.has(int(other.id)) and roster[int(other.id)].role==Roles.GOALKEEPER:
			keeper_x = _local(other.position,team).x
	var side := -signf(keeper_x) if absf(keeper_x)>0.35 else -1.0 if int(p.id)%2 else 1.0
	return _world(Vector2(side*1.85,float(snapshot.field_half_length)+0.6),team)

func _set_kick(intent: Dictionary, kind: String, point: Vector3, receiver_id: int, distance: float, snapshot: Dictionary, lift: float) -> void:
	intent.action = kind
	intent.receiver_id = receiver_id
	intent.aim_point = point
	intent.face_direction = _flat(point-snapshot.ball_position).normalized()
	intent.power = clampf(distance*1.05+7.5,10.0,24.0)
	for receiver in snapshot.get("players",[]):
		if int(receiver.id)==receiver_id and receiver.get("human",false) and _flat(receiver.velocity).length()<0.8:
			# A stationary human cannot automatically sprint into the flight path.
			# Reduce the requested kick, leaving reception to real contact/input.
			intent.power = minf(float(intent.power),18.0)
			intent.receive_offset = _flat(receiver.get("facing",Vector3.FORWARD)).normalized()*0.45
			intent.aim_point = point+intent.receive_offset
			intent.face_direction = _flat(intent.aim_point-snapshot.ball_position).normalized()
	intent.lift = lift
	intent.power01 = clampf((float(intent.power)-8.0)/20.0,0.10,0.85)
	intent.loft_deg = rad_to_deg(atan2(lift,maxf(float(intent.power),0.1)))
	if kind=="PASS":
		var delivery:Dictionary=_pass_profile(_distance(snapshot.ball_position,intent.aim_point),snapshot)
		intent.power01=delivery.power
		intent.power=delivery.speed
		intent.loft_deg=0.0
		intent.lift=0.0
	intent.reason = kind.to_lower() if kind!="PASS" else "safe_outlet"

func _lane_clear(start: Vector3, end: Vector3, opponents: Array[Dictionary], clearance: float) -> bool:
	var a := Vector2(start.x,start.z)
	var line := Vector2(end.x-start.x,end.z-start.z)
	if line.length_squared()<0.1:
		return false
	for other in opponents:
		var p := Vector2(other.position.x,other.position.z)
		var fraction := (p-a).dot(line)/line.length_squared()
		if fraction>0.08 and fraction<0.95 and p.distance_to(a+line*fraction)<clearance:
			return false
	return true

func _openness(point: Vector3, opponents: Array[Dictionary]) -> float:
	var nearest := 8.0
	for other in opponents:
		nearest = minf(nearest,_distance(point,other.position))
	return nearest

func _clip_role(point: Vector2, role: Dictionary, snapshot: Dictionary) -> Vector2:
	var region: Rect2 = Roles.profile(role.role).region
	var w := float(snapshot.field_half_width)
	var length := float(snapshot.field_half_length)
	return _clip_pitch(Vector2(clampf(point.x,region.position.x*w,region.end.x*w),clampf(point.y,region.position.y*length,region.end.y*length)),snapshot,1.4)

func _clip_pitch(point: Vector2, snapshot: Dictionary, margin: float) -> Vector2:
	var w := float(snapshot.field_half_width)
	var length := float(snapshot.field_half_length)
	return Vector2(clampf(point.x,-w+margin,w-margin),clampf(point.y,-length+margin,length-margin))

func _local(point: Vector3, team: int) -> Vector2:
	var direction := -1.0 if team==0 else 1.0
	return Vector2(point.x*-direction,point.z*direction)

func _local_velocity(velocity: Vector3, team: int) -> Vector2:
	return _local(velocity,team)

func _world(point: Vector2, team: int) -> Vector3:
	var direction := -1.0 if team==0 else 1.0
	return Vector3(point.x*-direction,0.0,point.y*direction)

func _flat(vector: Vector3) -> Vector3:
	return Vector3(vector.x,0,vector.z)

func _distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x-b.x,a.z-b.z).length()

func _wait_for_control(p: Dictionary, intent: Dictionary, snapshot: Dictionary, members: Array[Dictionary], opponents: Array[Dictionary]) -> bool:
	# Possession is produced by shoe contact in play, but it is not readiness.
	# Keep one chosen heading until actual control geometry remains stable.
	var id := int(p.id)
	var attack := Vector3.FORWARD if int(p.team)==0 else Vector3.BACK
	if carrier_setup.has("third_source") and (third_man.is_empty() or third_man.state!="CONTROLLED" or int(third_man.middle_id)!=id): carrier_setup.clear()
	if carrier_setup.is_empty():
		var completed: Dictionary = receive_plan.last_plan
		var choice: Dictionary = completed if completed.get("state","")=="COMPLETED" and int(completed.get("receiver_id",-1))==id and clock<float(completed.get("next_valid_until",0.0)) and _continuation_valid(p,completed,members,opponents,snapshot) else _choose_next_intent(p,members,opponents,snapshot)
		carrier_setup = {"owner_id":id,"heading":choice.get("next_direction",attack),"stable_since":-1.0,"released":false}
	if not third_man.is_empty() and third_man.state=="CONTROLLED" and int(third_man.middle_id)==id and carrier_setup.get("third_source","")!=third_man.pass_id:
		for candidate in members:
			if int(candidate.id)!=int(third_man.runner_id): continue
			# A confirmed reception selects C, rather than the expired carry preview.
			var aim: Vector3 = candidate.position+_flat(candidate.velocity)*.20
			carrier_setup.heading = _flat(aim-snapshot.ball_position).normalized()
			carrier_setup.third_source = third_man.pass_id
			carrier_setup.stable_since = -1.0
			carrier_setup.released = false
			break
	var ball: Vector3 = snapshot.ball_position
	var offset := _flat(ball-p.position)
	var facing := _flat(p.get("facing",attack)).normalized()
	var relative := _flat(snapshot.ball_velocity-p.velocity)
	var heading: Vector3 = carrier_setup.heading
	var ready: bool = controlled_contacts.has(id) and p.get("can_reach",false) and p.get("foot_action","") not in ["PASS","SHOT","TACKLE"] and ball.y<.30 and offset.length()>=.18 and offset.length()<1.10 and offset.normalized().dot(facing)>-.15 and relative.length()<5.0
	# A confirmed rolling touch stays released while the ball remains nearby.
	# Crossing the hips during a turn is handled by the existing foot rhythm;
	# it must not restart a planner pose gate. Ownership changes clear this state.
	if carrier_setup.released and controlled_contacts.has(id) and offset.length()<1.4 and ball.y<.45 and relative.length()<7.0 and (p.get("foot_action","")!="RECEIVE" or p.get("foot_hit",false)): return false
	if ready:
		# Readiness is a real touch plus a reachable rolling pocket. Turning and
		# kick alignment belong to the actor, not another planner dwell timer.
		carrier_setup.released=true
		return false
	carrier_setup.released = false
	intent.move_target = _flat(ball)-heading*.44
	intent.face_direction = heading
	intent.pace = clampf(_flat(snapshot.ball_velocity).length()+1.0,2.4,5.6) if ball.y<.45 else 3.4
	intent.close_control = true
	intent.action = "NONE"
	intent.receive = false
	intent.shield = false
	intent.reason = "confirm_control_then_turn"
	return true

func _support_points(owner: Dictionary, members: Array[Dictionary], opponents: Array[Dictionary], snapshot: Dictionary) -> Dictionary:
	var result := {}
	if eleven_duties: return _near_support_points(owner,members,opponents,snapshot)
	if owner.is_empty(): return result
	var team := int(owner.team)
	var ball := _local(snapshot.ball_position,team)
	var scale := _tactical_scale(snapshot)
	var advance:Vector3=_flat(owner.velocity).limit_length(3.2)*.35
	var support_origin:Vector2=_local(snapshot.ball_position+advance,team)
	var candidates: Array[Dictionary] = members.duplicate()
	candidates.sort_custom(func(a,b):
		var forward_a: bool = roster[int(a.id)].role==Roles.STRIKER
		var forward_b: bool = roster[int(b.id)].role==Roles.STRIKER
		return forward_a if forward_a!=forward_b else int(a.id)<int(b.id))
	for p in candidates:
		if result.size()>=2: break
		var id := int(p.id)
		var role: Dictionary = roster[id]
		if id==int(owner.id) or role.role==Roles.GOALKEEPER: continue
		var choices: Array[Vector2] = []
		if p.get("human",false):
			choices.append(_local(p.position,team)) # Advisory never moves the human.
		else:
			if last_targets.has(id): choices.append(_local(last_targets[id],team))
			choices.append(_anchor(p,role,"attack",ball,owner,snapshot))
			for depth in [6.0,3.0,-4.0]:
				for side in [-1.0,1.0]: choices.append(support_origin+Vector2(side*maxf(2.8,5.5*scale),depth*scale))
		var best := Vector3.ZERO
		var score := -INF
		for choice in choices:
			var clipped := choice if p.get("human",false) else _clip_role(choice,role,snapshot)
			var point := _world(clipped,team)
			var distance := _distance(snapshot.ball_position,point)
			if distance<maxf(2.4,4.8*scale) or distance>15.0*scale or _openness(point,opponents)<maxf(1.6,2.4*scale): continue
			if not _lane_clear(snapshot.ball_position,point,opponents,1.2) or not _support_onside(point,team,opponents,snapshot): continue
			var distinct := true
			for other in result.values():
				if _distance(point,other)<maxf(1.8,4.0*scale) or _flat(point-snapshot.ball_position).normalized().dot(_flat(other-snapshot.ball_position).normalized())>.84: distinct = false
			if not distinct: continue
			var gain := clipped.y-ball.y
			var value := minf(_openness(point,opponents),7.0)*.6-_distance(p.position,point)*.16
			if role.role==Roles.STRIKER: value += gain*.45
			else: value -= absf(gain-1.0)*.18
			# When one teammate offers depth, keep the other available beside or
			# behind the carrier instead of putting both ahead in one corridor.
			for chosen in result.values():
				if _local(chosen,team).y-ball.y>1.0:
					value+=1.4 if gain<=1.0 else -1.2
			var lane:Vector3=_flat(point-snapshot.ball_position)
			if advance.length()>.25 and lane.length()>.1 and lane.normalized().dot(advance.normalized())>.9:value-=1.8
			if last_targets.has(id) and _distance(last_targets[id],point)<.3: value += 1.2
			if value>score:
				score = value
				best = point
		if score>-INF: result[id] = best
	return result

func _support_onside(_point:Vector3,_team:int,_opponents:Array[Dictionary],_snapshot:Dictionary)->bool:
	# Support runs are opportunities, not offside adjudication at kick time.
	return true

func _tactical_scale(snapshot: Dictionary) -> float:
	return clampf(float(snapshot.get("tactical_scale",1.0)),.40,1.0)

func _stable_carry_route(p: Dictionary, proposed: Vector3, opponents: Array[Dictionary], snapshot: Dictionary) -> Vector3:
	if not eleven_duties and not snapshot.get("small_sided",false): return proposed
	var id := int(p.id)
	var previous: Dictionary = carry_routes.get(id,{})
	if not previous.is_empty() and clock<float(previous.until) and _distance(p.position,previous.target)>.8 and _lane_clear(p.position,previous.target,opponents,.8):
		return previous.target
	carry_routes[id] = {"target":proposed,"until":clock+.55}
	return proposed

# Planner-only preview for the buffered input owner. No kick reservation/permission.
func _plan_receive_continuation(plan: Dictionary, by_id: Dictionary, snapshot: Dictionary) -> void:
	var receiver: Dictionary = by_id.get(int(plan.receiver_id),{})
	if receiver.is_empty(): return
	var members: Array[Dictionary] = []
	var opponents: Array[Dictionary] = []
	for other in by_id.values():
		if int(other.team)==int(receiver.team): members.append(other)
		else: opponents.append(other)
	var cached: bool = next_preview.get("pass_id","")==plan.pass_id and int(next_preview.get("owner_id",-1))==int(receiver.id) and clock<float(next_preview.get("rescore_at",0.0)) and _distance(plan.receive_point,next_preview.get("receive_origin",plan.receive_point))<.8 and _lane_clear(plan.receive_point,next_preview.get("next_target",plan.receive_point),opponents,1.2)
	if cached and int(next_preview.get("next_receiver_id",-1))>=0:
		var recipient: Dictionary = by_id.get(int(next_preview.next_receiver_id),{})
		cached = not recipient.is_empty() and _onside_receiver(recipient,opponents,snapshot)
	if not cached:
		# Only the active receiver, at most once per .6s while its option stays safe.
		var predicted := receiver.duplicate(false)
		predicted.position = plan.receive_point
		var future := snapshot.duplicate(false)
		future.ball_position = plan.receive_point
		next_preview = _choose_next_intent(predicted,members,opponents,future,plan.get("opponent_margin",null))
		next_preview.owner_id = int(receiver.id)
		next_preview.pass_id = plan.pass_id
		next_preview.rescore_at = clock+.60
		next_preview.receive_origin=plan.receive_point
	var choice := next_preview.duplicate(false)
	# A planned third runner is eligible for B's next pass only after arriving.
	if not third_man.is_empty() and third_man.state=="RUNNING" and third_man.pass_id==plan.pass_id:
		var runner: Dictionary = by_id.get(int(third_man.runner_id),{})
		if _third_man_ready(runner,plan.receive_point,opponents,snapshot):
			for key in ["next_action","next_target","next_receiver_id"]:
				choice[key] = "PASS" if key=="next_action" else runner.position if key=="next_target" else int(runner.id)
	# A reserved two-leg combination prepares the wall's outlet within the same
	# receive intent. It must not queue an unrelated automatic first-time pass.
	var joint:Dictionary=team_attack.plans.get(int(receiver.team),{})
	if joint.get("stage","")=="FLIGHT" and joint.get("mode","") in ["ONE_TWO","SWITCH_RELAY"] and int(joint.get("delivery",{}).get("receiver",-1))==int(receiver.id):
		var next_id:int=int(joint.get("runner",-1)) if joint.mode=="ONE_TWO" else int(joint.get("weak_receiver",-1))
		var next_actor:Dictionary=by_id.get(next_id,{})
		if not next_actor.is_empty():
			var outlet:Vector3=next_actor.position+_flat(next_actor.velocity)*.45
			if _lane_clear(plan.receive_point,outlet,opponents,1.05):
				choice.next_action="CARRY";choice.next_receiver_id=-1
				choice.next_target=outlet
				if joint.mode=="ONE_TWO" and float(plan.arrival_time)-clock<.55:
					var future:Dictionary=snapshot.duplicate(false);future.ball_position=plan.receive_point
					var wall:Dictionary=receiver.duplicate(false);wall.position=plan.receive_point
					var returned:Dictionary=team_attack._delivery(plan.receive_point,outlet,future,false);returned.receiver=next_id
					# Preparation is advisory; actual one-touch reach, foot and phase
					# still belong to the existing input/contact path below.
					if _onside_receiver(next_actor,opponents,snapshot) and team_attack._feasible(wall,next_actor,returned,opponents,future,true):
						choice.next_action="PASS";choice.next_receiver_id=next_id
	var direction := _flat(choice.next_target-plan.receive_point).normalized()
	if direction.length()<.1: direction = choice.next_direction
	for key in ["next_action","next_target","next_receiver_id"]: plan[key] = choice[key]
	plan.next_direction = direction
	plan.next_valid_until = clock+.80
	_prepare_receive_outlet(plan,receiver,opponents,snapshot)
	receive_plan.set_next_intent(int(receiver.id),plan)

func _choose_next_intent(p: Dictionary, members: Array[Dictionary], opponents: Array[Dictionary], snapshot: Dictionary, margin: Variant = null) -> Dictionary:
	var team := int(p.team)
	var shot:Dictionary=_shot_option(p,opponents,snapshot)
	if not shot.is_empty():return {"next_action":"SHOT","next_direction":_flat(shot.point-p.position).normalized(),"next_target":shot.point,"next_receiver_id":-1,"next_valid_until":clock+.8}
	var target := _carry_space_target(p,opponents,snapshot,margin)
	var action := "CARRY"
	var receiver_id := -1
	var best := _best_pass(p,members,opponents,snapshot,styles.get(team,SHORT_PASS))
	var urgent: bool = margin!=null and float(margin)<.35
	var carry:Dictionary=_open_carry_option(p,opponents,snapshot)
	if not carry.is_empty():target=carry.point
	# Receiving uses the same carry/pass comparison as possession, rather than
	# turning a longer pass into an automatic release before the first touch.
	var clear_gain:bool=not best.is_empty() and _pass_value(best,carry,snapshot)>float(carry.get("score",-100.0))+.45
	var called:bool=not best.is_empty() and int(snapshot.get("call_id",-1))==int(best.id)
	var combine:bool=carry.is_empty() or clear_gain or called
	if not best.is_empty() and (urgent or combine and (_openness(p.position,opponents)<4.0 or requested_support.has(int(best.id)) or styles.get(team)==SHORT_PASS or clear_gain or called)):
		target = best.point
		action = "PASS"
		receiver_id = int(best.id)
	var direction := _flat(target-p.position).normalized()
	if direction.length()<.1: direction = Vector3.FORWARD if team==0 else Vector3.BACK
	return {"next_action":action,"next_direction":direction,"next_target":target,"next_receiver_id":receiver_id,"next_valid_until":clock+.80}

func _pass_value(best:Dictionary,carry:Dictionary,snapshot:Dictionary)->float:
	var scale:float=_tactical_scale(snapshot)
	return float(best.score)

func _apply_carry_gear(p:Dictionary,intent:Dictionary,carry:Dictionary,opponents:Array[Dictionary],snapshot:Dictionary)->void:
	intent.carry_run=false
	if carry.is_empty():return
	var role:Dictionary=roster[int(p.id)]
	var conservative:bool=role.role==Roles.CENTER_BACK or role.get("duty","")=="hold"
	var direction:Vector3=_flat(carry.point-p.position).normalized()
	var edge:float=minf(float(snapshot.field_half_width)-absf(p.position.x),float(snapshot.field_half_length)-absf(p.position.z))
	var turn:float=_flat(p.facing).normalized().dot(direction)
	var wants_cut:bool=PressureRoute.wants_cut(p,carry.point,opponents)
	var route:Dictionary=PressureRoute.inspect(p,carry.point,opponents,4.5 if conservative else 5.0,wants_cut)
	var memory:Dictionary=carry_routes.get(int(p.id),{})
	var touch_ready:bool=not memory.get("needs_touch",false) or float(controlled_contacts.get(int(p.id),-1))>=float(memory.get("started",clock)) or turn>.96 and _flat(snapshot.ball_velocity).dot(direction)>.8
	var running_touch:bool=_running_touch_reachable(p,direction,4.5 if conservative else 5.0,snapshot)
	touch_ready=touch_ready and running_touch
	var safe:bool=float(route.clearance)>(1.75 if conservative else 1.10) and float(route.immediate)>1.0
	# Only a defender obstructing our front/side warrants a turning gesture.
	# A trailing chaser alone calls for forward acceleration, not repeated cuts.
	var needs_evasion:bool=false
	for enemy in opponents:
		var relative:Vector3=_flat(enemy.position-p.position)
		var projected:Vector3=relative+_flat(enemy.get("velocity",Vector3.ZERO)-p.velocity)*.25
		if relative.length()<3.6 and relative.normalized().dot(_flat(p.facing).normalized())>-.10 and (relative.length()<2.8 or projected.length()<1.6):needs_evasion=true;break
	# The selected route owns the cut; passing and shooting still win upstream.
	intent.carry_cut=wants_cut and needs_evasion and not memory.get("cut_attempted",false) and float(route.clearance)>(1.5 if conservative else 1.0) and float(route.immediate)>1.0 and edge>1.3
	# This is only a proposal. The dispatcher reduces pace after the real foot
	# scheduler accepts it; cooldown / failed reach never become a slow-walk state.
	if intent.close_control or intent.shield:return
	if safe and edge>1.8 and turn>.88 and touch_ready and float(carry.progress)>-.5 and float(p.get("stamina",100))>28 and not p.get("sprint_locked",false):
		intent.carry_run=true
		intent.pace=4.5 if conservative else 5.0
		intent.reason="escape_accelerate" if _openness(p.position,opponents)<3.5 else "carry_run_space"
	else:
		intent.pace=minf(4.2 if safe and turn>.70 else 3.4,lerpf(2.2,4.2,clampf((edge-.8)/1.5,0,1)))
		intent.reason="escape_touch_turn" if safe and not touch_ready else "carry_route_adjust"
		if not running_touch:
			# A cut's successful contact is not a promise that its free rolling
			# ball already supports sprint cadence. Follow the real moving pocket.
			var lead:float=maxf(0,_flat(snapshot.ball_position-p.position).dot(direction)-.35)
			intent.pace=minf(float(intent.pace),maxf(2.2,_flat(snapshot.ball_velocity).dot(direction)+lead*2.0))

func _running_touch_reachable(p:Dictionary,direction:Vector3,pace:float,snapshot:Dictionary)->bool:
	var profile:Resource=p.get("motor_profile",PressureRoute.default_profile)
	var horizon:float=.22
	var predicted:Dictionary=preload("res://scripts/dribble_turn_control.gd").predict_motor(_flat(p.velocity),direction*pace,profile,.65,horizon)
	var ball_velocity:Vector3=_flat(snapshot.ball_velocity)
	var loss:float=FootballBallForces.rolling_deceleration_mps2(ball_velocity.length(),profile)
	var future:Vector3=_flat(snapshot.ball_position-p.position)+ball_velocity*horizon-ball_velocity.normalized()*.5*loss*horizon*horizon-predicted.displacement
	return future.length()<1.08 and future.dot(direction)>-.12 and future.slide(direction).length()<.65
func _near_support_points(owner: Dictionary, members: Array[Dictionary], opponents: Array[Dictionary], snapshot: Dictionary) -> Dictionary:
	var result := {}
	if owner.is_empty(): return result
	var team := int(owner.team)
	var ball := _local(snapshot.ball_position+_flat(owner.velocity).limit_length(3.2)*.35,team)
	var side := -1.0 if ball.x>0 else 1.0
	# Three distinct offers: safe rear link, diagonal, and a forward depth run.
	for slot in [Vector2(side*6.0,-4.0),Vector2(-side*7.0,6.0),Vector2(side*3.0,12.0)]:
		var best_id := -1
		var best_point := Vector3.ZERO
		var score := -INF
		for p in members:
			var id := int(p.id)
			var role: Dictionary = roster[id]
			if id==int(owner.id) or result.has(id) or role.role in [Roles.GOALKEEPER,Roles.CENTER_BACK] or role.get("duty","") not in ["link","support","finish","width"]: continue
			if slot.y>10.0 and role.get("duty","") not in ["finish","width"]: continue
			var point:Vector3 = p.position if p.get("human",false) else _world(_clip_role(ball+slot,role,snapshot),team)
			var distance := _distance(snapshot.ball_position,point)
			var travel := _distance(p.position,point)
			if distance<5.0 or distance>14.0 or travel>18.0: continue
			var open := _openness(point,opponents)
			if open<2.4: continue
			if not _lane_clear(snapshot.ball_position,point,opponents,1.2) or not _support_onside(point,team,opponents,snapshot): continue
			var distinct := true
			for selected in result.values():
				if _distance(point,selected)<5.0 or _flat(point-snapshot.ball_position).normalized().dot(_flat(selected-snapshot.ball_position).normalized())>.84: distinct = false
			if not distinct: continue
			var value := minf(open,7.0)*.6-travel*.25
			if last_targets.has(id) and _distance(last_targets[id],point)<.8: value += 1.2
			if value>score:
				score = value
				best_id = id
				best_point = point
		if best_id>=0: result[best_id] = best_point
	return result

func _continuation_valid(p: Dictionary, choice: Dictionary, members: Array[Dictionary], opponents: Array[Dictionary], snapshot: Dictionary) -> bool:
	if not _lane_clear(p.position,choice.get("next_target",p.position),opponents,1.2): return false
	var receiver_id := int(choice.get("next_receiver_id",-1))
	if receiver_id<0: return true
	for other in members:
		if int(other.id)==receiver_id: return _onside_receiver(other,opponents,snapshot)
	return false

func _carry_space_target(p: Dictionary, opponents: Array[Dictionary], snapshot: Dictionary, margin: Variant) -> Vector3:
	var origin := _local(p.position,int(p.team))
	var best := _world(_clip_pitch(origin+Vector2(0,6.0*_tactical_scale(snapshot)),snapshot,2.0),int(p.team))
	var score := -INF
	var pressure_weight := 1.6 if margin!=null and float(margin)<.35 else 1.0
	for step in [Vector2(0,6),Vector2(-4,4),Vector2(4,4),Vector2(-6,0),Vector2(6,0),Vector2(-4,-3),Vector2(4,-3)]:
		var point := _world(_clip_pitch(origin+step*_tactical_scale(snapshot),snapshot,2.0),int(p.team))
		if not _lane_clear(p.position,point,opponents,.9): continue
		var value:float = minf(_openness(point,opponents),8.0)*pressure_weight+step.y*.14
		if value>score:
			score = value
			best = point
	return best

func _prepare_receive_outlet(plan: Dictionary, receiver: Dictionary, opponents: Array[Dictionary], snapshot: Dictionary) -> void:
	var incoming: Vector3 = _flat(plan.face_direction).normalized()
	var outgoing: Vector3 = _flat(plan.next_direction).normalized()
	var origin: Vector3 = plan.receive_point
	var best_direction := Vector3.ZERO
	var best_point := origin
	var score := -INF
	var margin: Variant = plan.get("opponent_margin",null)
	var pressure_weight := 2.0 if margin!=null and float(margin)<.35 else 1.0
	# Short outlets stay within an actual inside-foot steering cone, not a teleport.
	for degrees in [-60.0,-30.0,0.0,30.0,60.0]:
		var axis := outgoing.rotated(Vector3.UP,deg_to_rad(degrees))
		var pass_face := incoming.rotated(Vector3.UP,clampf(incoming.signed_angle_to(outgoing,Vector3.UP),-PI/4,PI/4))
		if plan.next_action=="PASS" and axis.dot(pass_face)<.5: continue
		var point := _world(_clip_pitch(_local(origin+axis*1.4,int(receiver.team)),snapshot,1.4),int(receiver.team))
		if _distance(origin,point)<.9 or _openness(point,opponents)<1.5 or not _lane_clear(origin,point,opponents,.65): continue
		var future_open := INF
		for opponent in opponents:
			future_open = minf(future_open,_distance(point,opponent.position+_flat(opponent.velocity).limit_length(9.5)*.2))
		if future_open<1.4: continue
		var momentum:Vector3=_flat(receiver.velocity)
		var value := minf(future_open,6.0)*pressure_weight+axis.dot(outgoing)*.75+(axis.dot(momentum.normalized())*.8 if momentum.length()>.8 else 0.0)
		if value>score:
			score = value
			best_direction = axis
			best_point = point
	plan.first_touch_direction = best_direction
	plan.first_touch_target = best_point
	plan.first_touch_valid_until = clock+.40
	# Next touch remains advice until contact; the interception owner retains face/point/pace.

func _cancel_third_man(reason: String) -> void:
	if third_man.is_empty(): return
	third_man.state = "CANCELED"
	third_man.cancel_reason = reason
	third_man_last = third_man.duplicate(true)
	third_man.clear()

func _consume_third_man_contact(event: Dictionary) -> void:
	if third_man.is_empty(): return
	var actor_id := int(event.get("actor_id",-1))
	var action := String(event.get("tactical_action",event.get("action","")))
	var contact_key := String(event.get("event_key","%s:%s:%s" % [event.get("physics_frame",-1),event.get("serial",-1),actor_id]))
	if action in ["PASS","CROSS","CUTBACK","CLEARANCE","SHOT"]:
		if action=="PASS" and actor_id==int(third_man.middle_id) and int(event.get("receiver_id",-1))==int(third_man.runner_id) and third_man.state in ["RUNNING","CONTROLLED"] and not receive_plan.active.is_empty():
			third_man.state = "SECOND_IN_FLIGHT"
			third_man.second_pass_id = receive_plan.active.pass_id
			third_man.second_contact = contact_key
			third_man.deadline = clock+4.0
			# The second pass must not spawn an unrelated B->C->B give-go.
			give_go_plan.cancel("third_man_second_pass",clock)
		else: _cancel_third_man("other_confirmed_kick")
		return
	if int(event.get("carrier_id",-1))!=actor_id: return
	if String(event.get("action","")) not in ["RECEIVE","STOP","SETTLE","PULL","CONTROL"]: return
	if actor_id==int(third_man.middle_id) and third_man.state in ["RUNNING","CONTROLLED"]:
		if third_man.state!="CONTROLLED":third_man.controlled_at=clock
		third_man.state = "CONTROLLED"
		third_man.control_contact = contact_key
		third_man.deadline = minf(float(third_man.deadline),clock+2.2)
	elif actor_id==int(third_man.runner_id) and third_man.state=="SECOND_IN_FLIGHT":
		third_man.state = "COMPLETED"
		third_man.completion_contact = contact_key
		third_man_last = third_man.duplicate(true)
		third_man.clear()
	else: _cancel_third_man("other_player_control_contact")

func _update_third_man(reception: Dictionary, by_id: Dictionary, snapshot: Dictionary) -> void:
	if third_man.is_empty() and reception.has("planned_target"):return # Team delivery owns landing and second-ball runners.
	if not third_man.is_empty():
		var middle: Dictionary = by_id.get(int(third_man.middle_id),{})
		var runner: Dictionary = by_id.get(int(third_man.runner_id),{})
		if middle.is_empty() or runner.is_empty() or clock>=float(third_man.deadline):
			_cancel_third_man("participant_unavailable_or_timeout")
			return
		if third_man.state=="SECOND_IN_FLIGHT":
			if reception.get("pass_id","")!=third_man.second_pass_id: _cancel_third_man("second_receive_plan_ended")
			return
		var opponents: Array[Dictionary] = []
		for other in by_id.values():
			if int(other.team)!=int(third_man.team): opponents.append(other)
		var owner := int(snapshot.get("carrier_id",-1))
		var incoming_valid: bool = owner<0 and reception.get("pass_id","")==third_man.pass_id
		var controlled_valid: bool = owner==int(third_man.middle_id) and third_man.state=="CONTROLLED"
		if not incoming_valid and not controlled_valid:
			_cancel_third_man("initial_receive_or_control_lost")
			return
		# Position is not an offence. Keep the finite plan while C waits/comes back.
		var was_onside: bool = bool(third_man.get("receiver_onside_now",true))
		third_man.receiver_onside_now = _onside_receiver(runner,opponents,snapshot)
		if not third_man.receiver_onside_now and middle.get("foot_action","")!="PASS": third_man.outlet_committed = false
		var origin: Vector3 = reception.receive_point if incoming_valid else snapshot.ball_position
		var committed: bool = bool(third_man.get("outlet_committed",false))
		var preparation: Dictionary = _third_man_preparation(middle,runner,snapshot) if controlled_valid else {}
		var planning_origin: Vector3 = preparation.get("origin",origin)
		var preparation_changed: bool = controlled_valid and not third_man.has("preparation_origin")
		if controlled_valid:
			third_man.preparation_seconds = preparation.seconds
			third_man.preparation_origin = planning_origin
		var old_origin := Vector3(float(third_man.get("origin_x",origin.x)),0,float(third_man.get("origin_z",origin.z)))
		# A receive prediction can move within the existing bounded rescore window.
		# Capture before rescore_at is advanced; a failed due replan still cancels.
		var space_cancel_due: bool = third_man.state!="RUNNING" or clock>=float(third_man.get("rescore_at",0.0))
		var space_distance: float = _distance(origin,third_man.runner_target)
		var space_changed: bool = _distance(origin,old_origin)>1.2 or space_distance<maxf(2.0,4.0*_tactical_scale(snapshot)) or space_distance>18.0*_tactical_scale(snapshot)
		var unsafe_target: bool = not _third_man_run_route_clear(runner.position,third_man.runner_target,opponents) or _openness(third_man.runner_target,opponents)<2.4
		if not third_man.receiver_onside_now and not committed:
			if was_onside or clock>=float(third_man.get("rescore_at",0.0)):
				third_man.rescore_at = clock+.60
				var recovery: Dictionary = _third_man_recovery_point(runner,origin,opponents,snapshot,float(third_man.deadline)-clock)
				third_man.runner_target = recovery.get("point",_flat(runner.position))
			third_man.recovering = true
		else: third_man.recovering = bool(third_man.get("recovering",false)) and _distance(runner.position,third_man.runner_target)>.6
		# Coordinate the SAME C until B reserves an actual outlet; never retarget it then.
		var predicted_tight: bool = controlled_valid and _distance(planning_origin,third_man.runner_target)<maxf(2.0,4.0*_tactical_scale(snapshot))+.8
		if not committed and third_man.receiver_onside_now and not third_man.recovering and (incoming_valid or controlled_valid) and (preparation_changed or space_changed or unsafe_target or predicted_tight) and (preparation_changed or clock>=float(third_man.get("rescore_at",0.0))):
			third_man.rescore_at = clock+(.20 if controlled_valid else .60)
			var budget: float = float(third_man.deadline)-clock if controlled_valid else minf(float(third_man.deadline)-clock,maxf(.3,float(reception.arrival_time)-clock)+1.0)
			var revised: Dictionary = _third_man_run_point(runner,planning_origin,opponents,snapshot,budget)
			if not revised.is_empty():
				third_man.runner_target = revised.point
				third_man.origin_x = planning_origin.x
				third_man.origin_z = planning_origin.z
				space_distance = _distance(origin,third_man.runner_target)
		space_distance = _distance(origin,third_man.runner_target)
		third_man.target_offside_now = not _support_onside(third_man.runner_target,int(runner.team),opponents,snapshot)
		if not _third_man_run_route_clear(runner.position,third_man.runner_target,opponents): _cancel_third_man("runner_route_blocked")
		elif _openness(third_man.runner_target,opponents)<2.4: _cancel_third_man("runner_target_pressured")
		elif space_cancel_due and (space_distance<maxf(2.0,4.0*_tactical_scale(snapshot)) or space_distance>18.0*_tactical_scale(snapshot)): _cancel_third_man("receiver_to_target_space_closed")
		return
	if reception.is_empty() or reception.get("first_pass_action","")!="PASS" or third_man_seen.has(reception.pass_id): return
	third_man_seen[reception.pass_id] = true
	if third_man_seen.size()>128: third_man_seen.erase(third_man_seen.keys()[0])
	var middle: Dictionary = by_id.get(int(reception.receiver_id),{})
	var passer: Dictionary = by_id.get(int(reception.passer_id),{})
	if middle.is_empty() or passer.is_empty() or roster[int(middle.id)].role==Roles.GOALKEEPER: return
	var opponents: Array[Dictionary] = []
	for other in by_id.values():
		if int(other.team)!=int(middle.team): opponents.append(other)
	var best_id := -1
	var best_target := Vector3.ZERO
	var score := -INF
	var origin: Vector3 = reception.receive_point
	var budget: float = maxf(.3,float(reception.arrival_time)-clock)+1.0
	for candidate in by_id.values():
		var id := int(candidate.id)
		if int(candidate.team)!=int(middle.team) or id in [int(middle.id),int(passer.id)] or candidate.get("human",false): continue
		var role: Dictionary = roster[id]
		if role.role in [Roles.GOALKEEPER,Roles.CENTER_BACK] or role.get("duty","") not in ["finish","width","link","support"]: continue
		# Choose a genuinely forward third player, not a second name for A's return run.
		if _local(candidate.position,int(middle.team)).y<_local(passer.position,int(middle.team)).y+2.0: continue
		var run: Dictionary = _third_man_run_point(candidate,origin,opponents,snapshot,budget)
		if not run.is_empty() and float(run.score)>score:
			score = float(run.score)
			best_id = id
			best_target = run.point
	if best_id<0: return
	third_man = {"pass_id":reception.pass_id,"passer_id":int(passer.id),"middle_id":int(middle.id),"runner_id":best_id,"team":int(middle.team),"runner_target":best_target,"origin_x":origin.x,"origin_z":origin.z,"rescore_at":clock+.60,"state":"RUNNING","started_at":clock,"deadline":minf(float(reception.deadline),clock+4.0),"source":"confirmed_A_to_B_pass","first_contact":reception.get("pass_id","")}
	# Competing plans have one winner. Ordinary give-go is unchanged if no C qualifies.
	give_go_plan.cancel("third_man_forward_option",clock)

func _third_man_ready(runner: Dictionary, origin: Vector3, opponents: Array[Dictionary], snapshot: Dictionary) -> bool:
	if runner.is_empty() or third_man.is_empty(): return false
	if _distance(runner.position,third_man.runner_target)>2.0: return false
	var distance := _distance(origin,runner.position)
	return distance>=maxf(2.0,4.0*_tactical_scale(snapshot)) and distance<=18.0*_tactical_scale(snapshot) and _onside_receiver(runner,opponents,snapshot) and _openness(runner.position,opponents)>=2.4 and _lane_clear(origin,runner.position,opponents,1.2)

func _consider_third_man_pass(p: Dictionary, intent: Dictionary, by_id: Dictionary, snapshot: Dictionary) -> void:
	if third_man.is_empty() or third_man.state!="CONTROLLED" or int(p.id)!=int(third_man.middle_id): return
	# Keep source identity while real setup/foot permission is still pending.
	intent.third_man_plan = third_man.duplicate(false)
	if intent.reason=="confirm_control_then_turn" or intent.action not in ["NONE","PASS"] or not p.get("kick_ready",false) or not p.get("can_kick",false): return
	var opponents: Array[Dictionary] = []
	for other in by_id.values():
		if int(other.team)!=int(p.team): opponents.append(other)
	var runner: Dictionary = by_id.get(int(third_man.runner_id),{})
	if not _third_man_ready(runner,snapshot.ball_position,opponents,snapshot): return
	var distance: float = _distance(snapshot.ball_position,runner.position)
	var power: float = clampf(distance*1.05+7.5,10.0,24.0)
	var point: Vector3 = runner.position+_flat(runner.velocity)*minf(distance/power,.55)
	point = _world(_clip_pitch(_local(point,int(p.team)),snapshot,1.6),int(p.team))
	if not _lane_clear(snapshot.ball_position,point,opponents,1.2): return
	if not _pass_preparation_safe(p,point,opponents,snapshot) or not _pass_window_safe(snapshot.ball_position,point,opponents,power,snapshot): return
	_set_kick(intent,"PASS",point,int(runner.id),distance,snapshot,0.0)
	third_man.outlet_committed = true
	intent.third_man_plan = third_man.duplicate(false)
	intent.reason = "third_man_control_then_pass"

func _third_man_run_point(candidate: Dictionary, origin: Vector3, opponents: Array[Dictionary], snapshot: Dictionary, budget: float) -> Dictionary:
	var team := int(candidate.team)
	var scale := _tactical_scale(snapshot)
	var local_origin := _local(origin,team)
	var local_runner := _local(candidate.position,team)
	var role: Dictionary = roster[int(candidate.id)]
	var best: Dictionary = {}
	var score := -INF
	for step in [Vector2(-4,7),Vector2(4,7),Vector2(0,10)]:
		var desired: Vector2 = local_origin+step*scale
		# A forward support target must also advance C, not drag an advanced C back to B.
		# Compare positions on the same Vector2 lattice; do not reject float rounding.
		var minimum_forward: float = Vector2(0.0,local_runner.y+maxf(.6,1.5*scale)).y
		desired.y = maxf(desired.y,minimum_forward)
		var clipped := _clip_role(desired,role,snapshot)
		if clipped.y<desired.y-.01: continue
		var point := _world(clipped,team)
		var distance: float = _distance(origin,point)
		if clipped.y<local_origin.y+3.0*scale or distance<maxf(2.0,4.0*scale) or distance>18.0*scale: continue
		var face := _flat(origin-point).normalized()
		var eta: Dictionary = receive_plan._eta(candidate,point,face,snapshot)
		if float(eta.ready_time)>budget: continue
		if not _third_man_run_route_clear(candidate.position,point,opponents) or not _lane_clear(origin,point,opponents,1.2): continue
		var future_open: float = _openness(point,opponents)
		for opponent in opponents:
			future_open = minf(future_open,_distance(point,opponent.position+_flat(opponent.velocity).limit_length(9.5)*minf(float(eta.ready_time),.75)))
		if future_open<2.8: continue
		var value: float = minf(future_open,7.0)-_distance(candidate.position,point)*.35+(clipped.y-local_origin.y)*.12
		if value>score:
			score = value
			best = {"point":point,"score":score,"ready_time":float(eta.ready_time)}
	return best

func _third_man_run_route_clear(start: Vector3, target: Vector3, opponents: Array[Dictionary]) -> bool:
	# Only C's positioning route: a short/no-move segment is not a short pass.
	var a := Vector2(start.x,start.z)
	var line := Vector2(target.x-start.x,target.z-start.z)
	var length_squared: float = line.length_squared()
	if length_squared>=.1: return _lane_clear(start,target,opponents,.8)
	# Near the station, test occupancy on the ENTIRE short segment, including
	# both endpoints. At zero length this is the actual standing point.
	for opponent in opponents:
		var position_2d := Vector2(opponent.position.x,opponent.position.z)
		var fraction: float = clampf((position_2d-a).dot(line)/length_squared,0.0,1.0) if length_squared>0.0 else 0.0
		if position_2d.distance_to(a+line*fraction)<.8: return false
	return true
func _third_man_preparation(middle: Dictionary, runner: Dictionary, snapshot: Dictionary) -> Dictionary:
	# Predict the moving outlet during real body positioning, turning and receive recovery.
	# This is planning only: it neither claims control nor satisfies contact permission.
	var ball: Vector3 = snapshot.ball_position
	var velocity: Vector3 = _flat(snapshot.ball_velocity)
	var heading: Vector3 = _flat(runner.position-ball).normalized()
	var setup: Vector3 = _flat(ball)-heading*.44
	var eta: Dictionary = receive_plan._eta(middle,setup,heading,snapshot)
	var cap: Dictionary = snapshot.get("capabilities",{})
	var brake: float = maxf(1.0,float(cap.get("brake_deceleration",7.5)))
	var relative: float = _flat(velocity-middle.velocity).length()
	var recovery: float = .20 if not middle.get("foot_idle",false) else 0.0
	var seconds: float = clampf(maxf(float(eta.ready_time),maxf(0.0,relative-1.8)/brake+recovery)+.20,.30,1.20)
	# Rolling friction can shorten this displacement; constant speed is the safer space budget.
	return {"seconds":seconds,"origin":_flat(ball)+velocity*seconds}

func _third_man_recovery_point(runner: Dictionary, origin: Vector3, opponents: Array[Dictionary], snapshot: Dictionary, budget: float) -> Dictionary:
	# A temporary recovery destination, not a global restriction on AI movement.
	var team := int(runner.team)
	var depths: Array[float] = []
	for opponent in opponents: depths.append(_local(opponent.position,team).y)
	depths.sort()
	if depths.size()<2: return {}
	var local_runner: Vector2 = _local(runner.position,team)
	var depth: float = minf(local_runner.y-.6,maxf(_local(snapshot.ball_position,team).y,depths[-2])-.65-.01)
	var scale: float = _tactical_scale(snapshot)
	var best: Dictionary = {}
	var score := -INF
	for lateral in [0.0,-4.0*scale,4.0*scale]:
		var local_point: Vector2 = _clip_role(Vector2(local_runner.x+lateral,depth),roster[int(runner.id)],snapshot)
		var point: Vector3 = _world(local_point,team)
		var distance: float = _distance(origin,point)
		if distance<maxf(2.0,4.0*scale) or distance>18.0*scale: continue
		if not _support_onside(point,team,opponents,snapshot) or not _third_man_run_route_clear(runner.position,point,opponents): continue
		if _openness(point,opponents)<2.4 or not _lane_clear(origin,point,opponents,1.2): continue
		var eta: Dictionary = receive_plan._eta(runner,point,_flat(origin-point).normalized(),snapshot)
		if float(eta.ready_time)>budget: continue
		var value: float = minf(_openness(point,opponents),7.0)-_distance(runner.position,point)*.35
		if value>score:
			score = value
			best = {"point":point,"ready_time":float(eta.ready_time)}
	return best

func _open_carry_option(p:Dictionary,opponents:Array[Dictionary],snapshot:Dictionary)->Dictionary:
	if roster[int(p.id)].role==Roles.GOALKEEPER:return {}
	var id:int=int(p.id);var team:int=int(p.team)
	var role:String=roster[id].role
	var risk:float=1.25 if role in [Roles.WINGER,Roles.STRIKER] else .72 if role==Roles.CENTER_BACK or roster[id].get("duty","")=="hold" else 1.0
	var origin:Vector2=_local(p.position,team)
	var scale:float=_tactical_scale(snapshot)
	var pressure:float=_openness(p.position,opponents)
	var previous:Dictionary=carry_routes.get(id,{})
	if not previous.is_empty() and previous.has("choice") and clock<float(previous.until) and _distance(p.position,previous.target)>.7:
		var retained:Dictionary=_evaluate_carry(p,previous.target,opponents,risk,snapshot)
		if not retained.is_empty() and float(retained.clearance)>.9:
			retained.committed=true;return retained
	var best:Dictionary={}
	var options:Array[Vector2]=[Vector2(0,5.2),Vector2(-1.7,4.8),Vector2(1.7,4.8),Vector2(-2.8,3.6),Vector2(2.8,3.6),Vector2(-3.0,.7),Vector2(3.0,.7),Vector2(-2.0,-1.5),Vector2(2.0,-1.5)]
	if origin.y>float(snapshot.field_half_length)*.25 and absf(origin.x)>float(snapshot.field_half_width)*.30:
		options.append(Vector2(-signf(origin.x)*4.4,2.2))
		options.append(Vector2(-signf(origin.x)*5.0,0.0))
	for step in options:
		var point:Vector3=_world(_clip_pitch(origin+step*scale,snapshot,1.1),team)
		var choice:Dictionary=_evaluate_carry(p,point,opponents,risk,snapshot)
		if choice.is_empty():continue
		if not best.is_empty() and float(choice.score)<=float(best.score):continue
		best=choice
	if not best.is_empty():
		# Retain a still-useful exit after the minimum hold, rather than requesting
		# a new turning touch every refresh while the same lane remains available.
		if not previous.is_empty() and _distance(p.position,previous.target)>1.0:
			var retained:Dictionary=_evaluate_carry(p,previous.target,opponents,risk,snapshot)
			if not retained.is_empty() and float(retained.score)>float(best.score)-1.0 and float(retained.clearance)>1.0:
				previous.until=clock+.35;carry_routes[id]=previous;retained.committed=true;return retained
		best.committed=false
		carry_routes[id]={"target":best.point,"until":clock+.65,"started":clock,"needs_touch":_flat(p.facing).normalized().dot(_flat(best.point-p.position).normalized())<.88,"choice":best.duplicate()}
	else:carry_routes.erase(id)
	return best

func _evaluate_carry(p:Dictionary,point:Vector3,opponents:Array[Dictionary],risk:float,snapshot:Dictionary={})->Dictionary:
	var distance:float=_distance(p.position,point)
	if distance<.55:return {}
	var route:Dictionary=PressureRoute.inspect(p,point,opponents,4.5 if risk<.8 else 5.0,PressureRoute.wants_cut(p,point,opponents))
	var clearance:float=route.clearance
	if clearance<.80:return {}
	var progress:float=_local(point,int(p.team)).y-_local(p.position,int(p.team)).y
	var direction:Vector3=_flat(point-p.position).normalized()
	var angle:float=_flat(p.facing).normalized().angle_to(direction)
	var score:float=LearnedPolicy.bias(int(snapshot.get("learning_actions",{}).get(int(p.team),0)),"CARRY")+team_attack.possession_value(p.position,point,int(p.team),opponents,snapshot)+progress*.48*(risk-1.0)-angle*.55-maxf(0,1.5-clearance)*(2.2/risk)-distance/4.5*.30
	var travel:Vector3=_flat(p.get("velocity",Vector3.ZERO))
	if travel.length()>2.8:
		var momentum_angle:float=travel.normalized().angle_to(direction)
		score-=maxf(0,momentum_angle-deg_to_rad(55.0))*2.0
	var style:String="ADVANCE" if progress>2.5 and angle<.45 else "CUT" if progress>1.0 else "SHIELD_EXIT"
	return {"point":point,"progress":progress,"score":score,"clearance":clearance,"immediate":route.immediate,"style":style,"risk":risk}
func _pass_profile(distance:float,snapshot:Dictionary)->Dictionary:
	var table:Array=snapshot.get("ground_delivery",[])
	if table.is_empty():return {"time":distance/12.0,"speed":12.0,"power":.5}
	var index:int=clampi(int(floor(distance/2.0))-1,0,table.size()-1)
	var a:Dictionary=table[index]
	var b:Dictionary=table[mini(index+1,table.size()-1)]
	var fraction:float=clampf((distance-float(a.distance))/maxf(.01,float(b.distance)-float(a.distance)),0,1)
	return {"time":lerpf(a.time,b.time,fraction),"speed":lerpf(a.speed,b.speed,fraction),"power":lerpf(a.power,b.power,fraction)}

func _guard_carry_boundary(p:Dictionary,intent:Dictionary,snapshot:Dictionary)->void:
	if intent.action!="NONE" or intent.role==Roles.GOALKEEPER or intent.has("receive_plan"):return
	var ball:Vector3=snapshot.ball_position
	var velocity:Vector3=snapshot.ball_velocity
	var body:Vector3=p.velocity
	var point:Vector3=intent.move_target
	var changed:bool=false
	var memory:Dictionary=boundary_routes.get(int(p.id),{})
	if not memory.is_empty() and clock<float(memory.until):
		point=memory.point;changed=true
	for axis in [0,2]:
		var limit:float=float(snapshot.field_half_width if axis==0 else snapshot.field_half_length)
		var side:float=signf(ball[axis])
		# Budget the requested next touch before it becomes an outgoing ball.
		# A route endpoint inside the line can still demand an unsafe lateral
		# acceleration while the player is sprinting parallel to the touchline.
		var requested:Vector3=_flat(point-p.position).normalized()*float(intent.pace)
		var outward:float=maxf(0,maxf(maxf(velocity[axis]*side,body[axis]*side),requested[axis]*side))
		var brake:float=maxf(1.0,float(snapshot.get("capabilities",{}).get("brake_deceleration",5.5)))
		var reserve:float=1.05+outward*.60+outward*outward/(2.0*brake)
		if limit-absf(ball[axis])>reserve:continue
		# The reserve budgets the freely rolling ball and the body braking, not
		# just the endpoint of a target that the motor may already be overrunning.
		if outward>.4 or point[axis]*side>limit-reserve:
			point[axis]=side*(limit-reserve-1.5)
			if axis==2:point.x=lerpf(p.position.x,0.0,.32)+(2.0 if p.position.x<=0 else -2.0)
			changed=true
	if not changed:return
	if memory.is_empty() or clock>=float(memory.until):boundary_routes[int(p.id)]={"point":point,"until":clock+1.2}
	intent.move_target=_world(_clip_pitch(_local(point,int(p.team)),snapshot,1.6),int(p.team))
	intent.face_direction=_flat(intent.move_target-p.position).normalized()
	intent.carry_run=false;intent.carry_cut=false;intent.close_control=false;intent.shield=false
	var outward_now:float=maxf(absf(body.x) if absf(ball.x)>float(snapshot.field_half_width)-2.0 else 0.0,absf(body.z) if absf(ball.z)>float(snapshot.field_half_length)-2.0 else 0.0)
	intent.pace=minf(float(intent.pace),2.8 if outward_now>1.0 else 3.6)
	intent.reason="keep_ball_inside_before_line"
	if carry_routes.has(int(p.id)):carry_routes[int(p.id)].target=intent.move_target

func _shot_option(p:Dictionary,opponents:Array[Dictionary],snapshot:Dictionary)->Dictionary:
	if roster[int(p.id)].role==Roles.GOALKEEPER:return {}
	var team:int=int(p.team)
	var length:float=float(snapshot.field_half_length)
	var origin:Vector3=snapshot.ball_position
	var local:Vector2=_local(origin,team)
	var depth:float=length-local.y
	var half:float=float(snapshot.get("goal_half_width",3.66))
	if depth<.4 or depth>minf(24.0,length*.65):return {}
	var aperture:float=absf(atan2(half-local.x,depth)-atan2(-half-local.x,depth))
	# A merely unblocked diagonal from thirty metres is not automatically a
	# worthwhile shot. Retain possession / find the extra pass or inward route.
	var goal_distance:float=Vector2(local.x,depth).length()
	if aperture<.24 or goal_distance>minf(22.0,length*.80):return {}
	var fielders:Array[Dictionary]=[]
	var keeper:Dictionary={}
	for other in opponents:
		if roster[int(other.id)].role==Roles.GOALKEEPER:keeper=other
		else:fielders.append(other)
	var best:Dictionary={}
	for fraction in [-.72,0.0,.72]:
		var point:Vector3=_world(Vector2(half*fraction,length+.25),team)
		if not _lane_clear(origin,point,fielders,.60):continue
		var distance:float=_distance(origin,point)
		var keeper_gap:float=4.0
		if not keeper.is_empty():
			var projected:Vector3=Geometry3D.get_closest_point_to_segment(_flat(keeper.position),_flat(origin),point)
			keeper_gap=_distance(keeper.position,projected)
		var quality:float=aperture*3.0+minf(keeper_gap,3.0)*.35-distance*.022
		if depth>12.0 and quality<.35:continue
		if best.is_empty() or quality>float(best.score):best={"point":point,"score":quality,"power":clampf(.42+distance*.013,.46,.82)}
	return best

func _apply_team_attack(p:Dictionary,intent:Dictionary,plan:Dictionary,by_id:Dictionary,opponents:Array[Dictionary],snapshot:Dictionary)->void:
	intent.team_attack_mode=plan.mode
	intent.shared_plan_id=plan.id
	intent.shared_plan_stage=plan.stage
	if int(p.id)!=int(snapshot.carrier_id):
		if intent.press or intent.receive or intent.has("receive_plan"):return
		var assignment:Dictionary=plan.assignments.get(int(p.id),{})
		if assignment.is_empty():return
		intent.move_target=_world(_clip_pitch(_local(assignment.point,int(p.team)),snapshot,1.5),int(p.team))
		if (plan.stage in ["PREPARE","RETURN","RELAY"] or plan.stage=="FLIGHT" and assignment.role=="RETURN_RUN") and not snapshot.get("small_sided",false):
			var local_target:Vector2=_local(intent.move_target,int(p.team))
			local_target.y=minf(local_target.y,float(snapshot.fixed_offside[int(p.team)]))
			intent.move_target=_world(local_target,int(p.team))
		intent.pace=assignment.pace
		intent.support_offer=true
		intent.attack_duty=assignment.role
		intent.plan_endpoint=assignment.role in ["FORWARD_RUN","RETURN_RUN","LANDING","NEAR_POST","CENTRAL","FAR_POST","LATE_EDGE","SECOND_BALL"]
		intent.reason="team_"+String(plan.mode).to_lower()+"_"+String(assignment.role).to_lower()
		return
	if intent.role==Roles.GOALKEEPER or intent.action=="SHOT" or intent.reason=="confirm_control_then_turn":return
	if plan.stage not in ["PREPARE","RETURN","RELAY"]:return
	# Compare the plan's consequence against the current ordinary choice. A plan
	# never takes ownership of a committed shoe action or of the human actor.
	var carry:Dictionary=intent.get("carry_choice",{})
	var alternative:float=float(carry.get("score",-100))
	if intent.action=="PASS":
		var receiver:Dictionary=by_id.get(int(intent.receiver_id),{})
		if not receiver.is_empty():
			var d:Dictionary=team_attack._delivery(snapshot.ball_position,intent.aim_point,snapshot,false)
			alternative=maxf(alternative,team_attack._value(p,receiver,d,opponents,snapshot))
	if float(plan.score)<alternative+.25:return
	if plan.has("carry_target") and intent.action=="NONE":
		var route:Dictionary=_evaluate_carry(p,plan.carry_target,opponents,float(carry.get("risk",1)),snapshot)
		if route.is_empty():return
		intent.move_target=route.point;intent.face_direction=_flat(route.point-p.position).normalized()
		intent.shield=false;intent.close_control=false
		_apply_carry_gear(p,intent,route,opponents,snapshot)
		intent.reason="plan_"+String(plan.mode).to_lower()
		return
	if not p.get("can_pass",p.get("can_kick",false)) or not p.get("kick_ready",false) or p.get("kick_setup_blocked",false):return
	if not team_attack.ready(plan,p,by_id,opponents,snapshot):return
	var delivery:Dictionary=plan.delivery
	var kind:String=String(plan.mode) if plan.mode in ["CROSS","CUTBACK"] else "PASS"
	_set_kick(intent,kind,delivery.point,int(delivery.receiver),_distance(snapshot.ball_position,delivery.point),snapshot,0.0)
	intent.power01=delivery.power;intent.loft_deg=delivery.loft
	if delivery.has("launch_speed"):intent.ai_loft_speed=delivery.launch_speed
	intent.space_target=delivery.point;intent.space_origin=snapshot.ball_position
	intent.space_valid_until=clock+.45
	intent.plan_kick_id=plan.id
	intent.close_control=false;intent.shield=false;intent.carry_run=false
	intent.reason="plan_"+String(plan.mode).to_lower()+"_"+String(plan.stage).to_lower()

func _resolve_ball_jobs(team:int,members:Array[Dictionary],intents:Dictionary,presser:int,receiver_id:int,in_flight:bool,snapshot:Dictionary)->void:
	var claim:int=receiver_id if in_flight and roster.get(receiver_id,{}).get("team",-1)==team else presser
	if not snapshot.get("ball_held",false) and int(snapshot.carrier_id)<0 and not (in_flight and roster.get(receiver_id,{}).get("team",-1)==team):
		for p:Dictionary in members:
			if roster[int(p.id)].role!=Roles.GOALKEEPER or _distance(p.position,snapshot.ball_position)>.9:continue
			var claim_gap:float=INF
			for other:Dictionary in members:
				if int(other.id)==claim:claim_gap=_distance(other.position,snapshot.ball_position)
			if claim_gap>1.6:
				claim=int(p.id)
				intents[claim].receive=true
				break
	for p:Dictionary in members:
		var id:int=int(p.id);var intent:Dictionary=intents[id]
		intent.ball_job_owner=claim
		if snapshot.get("ball_held",false) and id==int(snapshot.get("hand_owner_id",-1)):
			intent.move_target=p.position;intent.action="NONE";intent.receive=false;intent.press=false
			continue
		if id==claim or id==int(snapshot.carrier_id) or p.get("human",false):continue
		# Keeper may block a close shot, but must not independently claim a teammate's pass.
		if intent.receive or intent.press:
			intent.receive=false;intent.press=false
			if intent.action in ["RECEIVE","TACKLE"]:intent.action="NONE"
			if intent.role!=Roles.GOALKEEPER:
				intent.move_target=snapshot.role_targets.get(id,p.position)
				intent.reason="support_primary_ball_job"

func _resume_receive(p:Dictionary,intent:Dictionary,snapshot:Dictionary,members:Array[Dictionary],opponents:Array[Dictionary])->bool:
	var completed:Dictionary=receive_plan.last_plan
	if p.get("kick_setup_blocked",false):return false
	if completed.get("state","")!="COMPLETED" or int(completed.get("receiver_id",-1))!=int(p.id):return false
	if clock-float(completed.get("completed_at",-10))>.35 or not p.get("can_reach",false):return false
	if not _continuation_valid(p,completed,members,opponents,snapshot):return false
	var offset:Vector3=_flat(snapshot.ball_position-p.position)
	if offset.length()>1.15 or float(snapshot.ball_position.y)>.42:return false
	if completed.get("next_action","")=="PASS" and p.get("can_kick",false) and p.get("kick_ready",false):
		_set_kick(intent,"PASS",completed.next_target,int(completed.next_receiver_id),_distance(snapshot.ball_position,completed.next_target),snapshot,0)
		return true
	var direction:Vector3=completed.get("first_touch_direction",completed.get("next_direction",p.facing))
	var outgoing:Vector3=_flat(snapshot.ball_velocity)
	if outgoing.length()>.8:direction=outgoing.normalized()
	if direction.length_squared()<.01:direction=p.facing
	intent.move_target=_flat(snapshot.ball_position)+direction.normalized()*2.5
	intent.face_direction=direction.normalized()
	intent.pace=clampf(_flat(snapshot.ball_velocity).length()+.7,2.4,4.8)
	intent.close_control=false
	intent.reason="receive_follow_through"
	return true

func _route_support(p:Dictionary,intent:Dictionary,snapshot:Dictionary,actors:Array[Dictionary])->void:
	var id:int=int(p.id)
	if p.get("human",false) or id==int(snapshot.carrier_id) or intent.receive or intent.press or intent.role==Roles.GOALKEEPER or intent.action!="NONE" or intent.get("defensive_task",{}).get("task","") in [DefensiveTasks.COVER,DefensiveTasks.MARK,DefensiveTasks.SCREEN,DefensiveTasks.RECOVER]:
		support_detours.erase(id);return
	# Keep the semantic receiver/runner endpoint intact; this owns only off-ball travel.
	var goal:Vector3=intent.move_target
	var start:Vector3=_flat(p.position)
	var route:Vector3=_flat(goal-start)
	if route.length()<.4:support_detours.erase(id);return
	intent.support_destination=goal
	var axis:Vector3=route.normalized()
	if intent.get("support_offer",false) and route.length()>1.5:intent.face_direction=axis
	var blocker:Dictionary={}
	var nearest:float=INF
	for other:Dictionary in actors:
		if int(other.id)==id:continue
		var gap:Vector3=_flat(other.position-start)
		var along:float=gap.dot(axis)
		if along<-.1 or along>minf(route.length(),3.5):continue
		var clearance:float=.88 if int(other.id)!=int(snapshot.carrier_id) else 1.3
		if (gap-axis*along).length()>=clearance:continue
		if along<nearest:nearest=along;blocker=other
	if blocker.is_empty():support_detours.erase(id);return
	var lateral:Vector3=Vector3(-axis.z,0,axis.x)
	var memory:Dictionary=support_detours.get(id,{})
	var side:float=float(memory.get("side",0.0)) if int(memory.get("blocker",-1))==int(blocker.id) and clock<float(memory.get("until",0)) else 0.0
	if side==0:
		var left:Vector3=_flat(blocker.position)+lateral*1.25
		var right:Vector3=_flat(blocker.position)-lateral*1.25
		var left_cost:float=_distance(start,left)+_distance(left,goal)
		var right_cost:float=_distance(start,right)+_distance(right,goal)
		for other in actors:
			if int(other.id)==id or int(other.id)==int(blocker.id) or int(other.team)!=int(p.team):continue
			var predicted:Vector3=other.position+_flat(other.velocity)*.35
			left_cost+=maxf(0,1.6-_distance(left,predicted))*4
			right_cost+=maxf(0,1.6-_distance(right,predicted))*4
		side=1.0 if left_cost<right_cost else -1.0
		support_detours[id]={"side":side,"blocker":int(blocker.id),"until":clock+.8}
	var waypoint:Vector3=_flat(blocker.position)+lateral*side*(1.45 if int(blocker.id)==int(snapshot.carrier_id) else 1.10)+axis*.3
	intent.move_target=_world(_clip_pitch(_local(waypoint,int(p.team)),snapshot,1.0),int(p.team))
	intent.face_direction=_flat(intent.move_target-p.position).normalized()
	intent.support_route=true

func _press_running_lane(p:Dictionary,intent:Dictionary,owner:Dictionary,snapshot:Dictionary)->void:
	var ball:Vector3=snapshot.ball_position
	var run:Vector3=_flat(owner.velocity)
	var goal:Vector3=_world(Vector2(0,-float(snapshot.field_half_length)),int(p.team))
	var inside:Vector3=_flat(goal-ball).normalized()
	var best:Vector3=ball+run*.20
	var best_late:float=INF
	# Predict the carrier route, not each alternating boot's ball acceleration.
	for horizon in [.12,.24,.36,.50,.68,.86]:
		var point:Vector3=_flat(ball)+run*horizon+inside*.35
		var eta:float=_arrival_time(p,point,snapshot,6.2)
		var late:float=eta-horizon
		if late<best_late:best_late=late;best=point
		if late<=.05:break
	var approach:Vector3=_flat(p.position-best).normalized()
	var target:Vector3=best+approach*.50
	intent.move_target=_world(_clip_pitch(_local(target,int(p.team)),snapshot,.7),int(p.team))
	var gap:float=_distance(p.position,ball)
	# Run on the actual interception line; facing the old ball would impose backpedal caps.
	intent.face_direction=_flat(target-p.position).normalized() if gap>1.65 else _flat(ball+run*.08-p.position).normalized()
	intent.pace=minf(6.2,maxf(2.6,run.length()+1.0))
	intent.reason="intercept_running_lane"
	intent.receive=false
	intent.press=true
	intent.aim_point=ball
	if gap<1.9 and ball.y<=.42 and p.get("foot_idle",true) and p.get("tackle_ready",true) and p.get("can_reach",true):
		# Permission only: the local predictor and actual boot sweep still decide the poke.
		intent.action="TACKLE"

func _signal_open_support(intents:Dictionary,by_id:Dictionary,snapshot:Dictionary)->void:
	var owner:Dictionary=by_id.get(int(snapshot.carrier_id),{})
	for id in intents:intents[id].call_weight=0.0
	if owner.is_empty():return
	var team:int=int(owner.team)
	var opponents:Array[Dictionary]=[]
	for p in by_id.values():
		if int(p.team)!=team:opponents.append(p)
	var window:Dictionary=call_windows.get(team,{})
	var chosen:int=-1;var score:float=-INF
	for id in intents:
		var p:Dictionary=by_id[id];var intent:Dictionary=intents[id]
		if int(p.team)!=team or p.get("human",false) or id==snapshot.carrier_id or intent.is_goalkeeper or intent.receive or intent.action!="NONE":continue
		if intent.get("attack_duty","") in ["SAFE","REST_DEFENSE","REAR_WIDTH"]:continue
		var gap:float=_distance(snapshot.ball_position,p.position)
		if gap<3 or gap>26 or _openness(p.position,opponents)<1.8 or not _lane_clear(snapshot.ball_position,p.position,opponents,1.0):continue
		if not window.is_empty() and int(window.id)==int(id) and clock<float(window.until):chosen=int(id);break
		var value:float=_openness(p.position,opponents)*.25+_local(p.position-owner.position,team).y*.1+(2.0 if intent.get("attack_duty","")=="FORWARD_RUN" else 0)
		if value>score:score=value;chosen=int(id)
	if chosen<0:return
	if window.is_empty() or clock>=float(window.get("next",0)):
		window={"id":chosen,"start":clock,"until":clock+1.05,"next":clock+3.2};call_windows[team]=window
	if int(window.get("id",-1))==chosen and clock<float(window.get("until",0)):
		intents[chosen].call_weight=minf(clampf((clock-float(window.start))/.18,0,1),clampf((float(window.until)-clock)/.22,0,1))
		intents[chosen].request_ball=true
