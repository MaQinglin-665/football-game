extends RefCounted
# Team-level reservations at the existing tactical cadence. No actors or physics writes.
const LearnedPolicy=preload("res://scripts/tactics/learned_team_policy.gd")
var plans:Dictionary={}
var forward_runs:Dictionary={}
var recent_passes:Dictionary={}
var events:Array[Dictionary]=[]
var serial:int=0
var box_reservations:Dictionary={}
func reset()->void:
	plans.clear();recent_passes.clear();forward_runs.clear();box_reservations.clear()
func confirm_pass(team:int,actor:int,receiver:int,now:float)->void:
	recent_passes[actor]={"team":team,"until":now+2.2}
	var plan:Dictionary=plans.get(team,{})
	if plan.is_empty():return
	# An actual first-time wall return has no intermediate ownership/control
	# event. Recognize that same plan's second real kick, without inventing one.
	if plan.get("mode","")=="ONE_TWO" and plan.get("stage","")=="FLIGHT" and actor==int(plan.delivery.receiver) and receiver==int(plan.runner):
		plan.owner=actor;plan.delivery=plan.delivery.duplicate();plan.delivery.receiver=receiver
		plan.stage="RETURN";log_event(plan,"WALL_REDIRECT",now)
	if actor!=int(plan.owner) or receiver!=int(plan.get("delivery",{}).get("receiver",-1)):
		finish(team,"different_actual_pass",now);return
	plan.stage="RETURN_FLIGHT" if plan.stage in ["RETURN","RELAY"] else "FLIGHT"
	plan.kicked_at=now;plan.until=now+5.0
	if plan.mode=="ONE_TWO" and plan.stage=="FLIGHT":
		plan.assignments[int(plan.runner)]={"point":plan.runner_goal,"role":"RETURN_RUN","pace":5.6}
	log_event(plan,"KICK",now)

func log_event(plan:Dictionary,reason:String,now:float)->void:
	events.append({"id":plan.get("id",0),"mode":plan.get("mode",""),"stage":plan.get("stage",""),"owner":plan.get("owner",-1),"receiver":plan.get("delivery",{}).get("receiver",-1),"time":now,"event":reason})
	if events.size()>160:events.pop_front()

func finish(team:int,reason:String,now:float)->void:
	if plans.has(team):log_event(plans[team],reason,now)
	plans.erase(team)

func control_contact(event:Dictionary,roster:Dictionary,now:float)->void:
	var id:int=int(event.get("actor_id",-1))
	if not roster.has(id) or int(event.get("carrier_id",-1))!=id:return
	var action:String=event.get("action","")
	if action not in ["RECEIVE","STOP","SETTLE","PULL","CONTROL","CLOSE","TURN","SHIELD","CARRY"]:return
	for team in plans.keys():
		var plan:Dictionary=plans[team]
		if int(roster[id].team)!=int(team):finish(team,"opponent_control",now);continue
		if plan.stage not in ["FLIGHT","RETURN_FLIGHT"]:continue
		if id!=int(plan.delivery.receiver):finish(team,"other_receiver",now);continue
		if not preload("res://scripts/tactics/receive_plan.gd").controlled_result(event):return
		log_event(plan,"CONTROL",now)
		if plan.mode in ["ONE_TWO","SWITCH_RELAY"] and plan.stage=="FLIGHT":
			plan.owner=id;plan.stage="RETURN" if plan.mode=="ONE_TWO" else "RELAY";plan.until=now+1.5;plan.controlled_at=now
		else:finish(team,"COMPLETE",now)

func point(local:Vector2,team:int)->Vector3:return Vector3(local.x if team==0 else -local.x,0,-local.y if team==0 else local.y)
func flat(v:Vector3)->Vector3:return Vector3(v.x,0,v.z)
func distance(a:Vector3,b:Vector3)->float:return flat(a-b).length()
func openness(p:Vector3,opponents:Array[Dictionary])->float:
	var gap:float=30.0
	for other in opponents:gap=minf(gap,distance(p,other.position))
	return gap
func lane(a:Vector3,b:Vector3,opponents:Array[Dictionary],radius:float)->bool:
	for other in opponents:
		var nearest:Vector3=Geometry3D.get_closest_point_to_segment(flat(other.position),flat(a),flat(b))
		if distance(nearest,other.position)<radius:return false
	return true
func inside(p:Vector3,snapshot:Dictionary)->bool:
	return absf(p.x)<float(snapshot.field_half_width)-1.5 and absf(p.z)<float(snapshot.field_half_length)-2.0
func ground(distance_m:float,snapshot:Dictionary)->Dictionary:
	var table:Array=snapshot.get("ground_delivery",[])
	if table.is_empty():return {"time":distance_m/10.0,"power":.5}
	var i:int=clampi(int(distance_m/2.0)-1,0,table.size()-1)
	var a:Dictionary=table[i];var b:Dictionary=table[mini(i+1,table.size()-1)]
	var t:float=clampf((distance_m-float(a.distance))/maxf(.01,float(b.distance)-float(a.distance)),0,1)
	return {"time":lerpf(a.time,b.time,t),"power":lerpf(a.power,b.power,t)}
func eta(p:Dictionary,target:Vector3)->float:
	if p.is_empty():return INF
	var offset:Vector3=flat(target-p.position)
	var gap:float=maxf(0,offset.length()-.65)
	var speed:float=4.0 if p.get("sprint_locked",false) or float(p.get("stamina",100))<25 else float(p.get("ability_speed",5.6))
	# A transient foot cap is charged as preparation time, not a permanent running limit.
	var along:float=flat(p.get("velocity",Vector3.ZERO)).dot(offset.normalized())
	var initial:float=clampf(along,0,speed)
	var acceleration:float=float(p.get("ability_acceleration",5.5))
	var ramp:float=(speed-initial)/acceleration
	var ramp_distance:float=(initial+speed)*.5*ramp
	var travel:float=(sqrt(initial*initial+2*acceleration*gap)-initial)/acceleration if gap<ramp_distance else ramp+(gap-ramp_distance)/speed
	var turn:float=acos(clampf(flat(p.get("facing",offset)).normalized().dot(offset.normalized()),-1,1))/5.8 if gap>.5 else 0.0
	var braking:float=maxf(0,-along)/maxf(1,float(p.get("brake_deceleration",5.5)))
	return travel+maxf(turn*.6,braking)+.10+(.12 if float(p.get("foot_cap",100))<3 else 0.0)

# One plan per team, evaluated at the director cadence. Only real contacts advance stages.
func choose(team:int,owner:Dictionary,members:Array[Dictionary],opponents:Array[Dictionary],snapshot:Dictionary,roster:Dictionary,now:float,phase:String)->Dictionary:
	for id in recent_passes.keys():
		if now>=float(recent_passes[id].until):recent_passes.erase(id)
	var old:Dictionary=plans.get(team,{})
	var by_id:Dictionary={}
	for p in members:by_id[int(p.id)]=p
	if not old.is_empty():
		if now>=float(old.until):finish(team,"window_expired",now);old={}
		elif not owner.is_empty() and int(owner.team)!=team:finish(team,"possession_changed",now);old={}
	if not old.is_empty() and old.stage in ["FLIGHT","RETURN_FLIGHT"]:
		var reception:Dictionary=snapshot.get("live_reception",{})
		if int(reception.get("receiver_id",-1))!=int(old.delivery.receiver) and now-float(old.kicked_at)>.25:
			finish(team,"actual_ball_unreachable_or_deflected",now)
		else:
			# The designated receiver is controlled exclusively by ReceivePlan.
			var landing:Vector3=reception.get("receive_point",old.delivery.point)
			for id in old.assignments:
				if old.assignments[id].role=="SECOND_BALL":old.assignments[id].point=flat(landing)-point(Vector2(0,1),team)*4.0
			return old
		old={}
	if owner.is_empty() or int(owner.team)!=team:
		# Brief free-roll loss must not create a second chaser or teleport ownership.
		if not old.is_empty() and int(snapshot.get("control_hint_id",-1))==int(old.owner):return old
		finish(team,"no_team_carrier",now);return {}
	if not old.is_empty() and old.stage=="RETURN":
		return _return_plan(old,owner,by_id,opponents,snapshot,now)
	if not old.is_empty() and old.stage=="RELAY":
		var weak:Dictionary=by_id.get(int(old.weak_receiver),{})
		if weak.is_empty():finish(team,"relay_receiver_lost",now);return {}
		var target:Vector3=flat(weak.position)+flat(weak.velocity)*.5
		var d:Dictionary=_delivery(snapshot.ball_position,target,snapshot,distance(snapshot.ball_position,target)>24);d.receiver=int(weak.id)
		if not _feasible(owner,weak,d,opponents,snapshot,false):finish(team,"weak_side_closed",now);return {}
		old.delivery=d;old.score=6.0
		return old
	if not old.is_empty() and int(old.owner)==int(owner.id) and distance(snapshot.ball_position,old.origin)<3.0:
		var d:Dictionary=old.delivery
		if d.is_empty() or _feasible(owner,by_id.get(int(d.receiver),{}),d,opponents,snapshot,false):return old
		finish(team,"key_lane_closed",now)
	var assignments:Dictionary=_support_assignments(team,owner,members,opponents,snapshot,roster,{},"SHORT")
	_advance_run(team,owner,members,opponents,snapshot,roster,now,assignments)
	var choices:Array[Dictionary]=_candidates(team,owner,members,opponents,snapshot,roster,assignments,phase)
	var selected:Dictionary={}
	for choice in choices:
		choice.score+=LearnedPolicy.bias(int(snapshot.get("learning_actions",{}).get(team,0)),String(choice.get("mode","")))
		if selected.is_empty() or float(choice.score)>float(selected.score):selected=choice
	serial+=1
	var plan:Dictionary={"id":serial,"team":team,"mode":"SHORT","stage":"PREPARE","owner":int(owner.id),"origin":snapshot.ball_position,"until":now+.75,"started":now,"assignments":assignments,"delivery":{},"score":-100.0,"candidate_count":choices.size()}
	if not selected.is_empty():
		plan.merge(selected,true)
		plan.until=now+clampf(float(plan.get("wait",0))+.9,.9,2.4)
		if plan.mode=="ONE_TWO":plan.runner=int(owner.id);plan.runner_start=owner.position
		if plan.has("box_assignments"):
			for id in plan.box_assignments:plan.assignments[id]=plan.box_assignments[id]
		if not plan.delivery.is_empty() and not by_id[int(plan.delivery.receiver)].get("human",false):
			plan.assignments[int(plan.delivery.receiver)]={"point":plan.delivery.point,"role":"LANDING" if float(plan.delivery.loft)>1 else "FORWARD_RUN","pace":5.6}
		if plan.mode in ["LONG","SWITCH"]:
			var nearest:int=-1;var cost:float=INF
			for id in plan.assignments:
				if int(id)==int(plan.delivery.receiver) or plan.assignments[id].role in ["SAFE","REST_DEFENSE","REAR_WIDTH"]:continue
				var gap:float=distance(by_id[id].position,plan.delivery.point)
				if gap<cost:cost=gap;nearest=int(id)
			if nearest>=0:plan.assignments[nearest]={"point":plan.delivery.point-point(Vector2(0,1),team)*4.0,"role":"SECOND_BALL","pace":5.6}
	plans[team]=plan
	if plan.mode!="SHORT":log_event(plan,"SELECT",now)
	return plan

func ready(plan:Dictionary,owner:Dictionary,by_id:Dictionary,opponents:Array[Dictionary],snapshot:Dictionary)->bool:
	var d:Dictionary=plan.get("delivery",{})
	if d.is_empty() or owner.is_empty() or int(owner.id)!=int(plan.owner) or plan.stage not in ["PREPARE","RETURN","RELAY"]:return false
	return _feasible(owner,by_id.get(int(d.receiver),{}),d,opponents,snapshot,true)

func _return_plan(plan:Dictionary,owner:Dictionary,by_id:Dictionary,opponents:Array[Dictionary],snapshot:Dictionary,now:float)->Dictionary:
	var runner:Dictionary=by_id.get(int(plan.runner),{})
	if runner.is_empty() or int(owner.id)!=int(plan.owner):finish(int(plan.team),"return_participant_lost",now);return {}
	var attack:Vector3=point(Vector2(0,1),int(plan.team))
	var advanced:float=flat(runner.position-plan.runner_start).dot(attack)
	if runner.get("human",false) and (advanced<.7 or flat(runner.velocity).dot(attack)<.4):
		finish(int(plan.team),"human_did_not_offer_return",now);return {}
	var target:Vector3=flat(runner.position)+flat(runner.velocity).limit_length(5.6)*.55
	if not runner.get("human",false):target=target.move_toward(plan.runner_goal,minf(2.0,distance(target,plan.runner_goal)))
	var d:Dictionary=_delivery(snapshot.ball_position,target,snapshot,false)
	d.receiver=int(runner.id)
	if not _feasible(owner,runner,d,opponents,snapshot,false):finish(int(plan.team),"return_lane_lost",now);return {}
	plan.delivery=d;plan.score=_value(owner,runner,d,opponents,snapshot)
	if not runner.get("human",false):plan.assignments[int(runner.id)]={"point":plan.runner_goal,"role":"RETURN_RUN","pace":5.6}
	return plan

func _delivery(origin:Vector3,target:Vector3,snapshot:Dictionary,loft:bool)->Dictionary:
	var gap:float=distance(origin,target)
	var profile:Dictionary=ground(gap,snapshot)
	var result:Dictionary={"point":target,"flight":profile.time,"power":profile.power,"loft":0.0,"receiver":-1,"valid":gap<=36.0}
	if not loft:return result
	var table:Array=snapshot.get("aerial_delivery",snapshot.get("loft_delivery",[]))
	result.valid=false
	for i in range(table.size()-1):
		var a:Dictionary=table[i];var b:Dictionary=table[i+1]
		var near_range:float=float(a.get("receive_distance",a.distance));var far_range:float=float(b.get("receive_distance",b.distance))
		if not is_finite(far_range) or gap<near_range-.5 or gap>far_range+.5:continue
		var t:float=clampf((gap-near_range)/maxf(.01,far_range-near_range),0,1)
		result.flight=lerpf(float(a.get("receive_time",a.time)),float(b.get("receive_time",b.time)),t);result.power=lerpf(a.power,b.power,t);result.loft=float(a.loft);result.valid=true;result.air_time=lerpf(a.time,b.time,t)
		if b.has("launch_speed"):result.launch_speed=lerpf(float(a.get("launch_speed",17.0)),float(b.launch_speed),t)
		break
	return result

func _onside(receiver:Dictionary,snapshot:Dictionary)->bool:
	if snapshot.get("small_sided",false):return true
	return flat(receiver.position).dot(point(Vector2(0,1),int(receiver.team)))<=float(snapshot.get("fixed_offside",{}).get(int(receiver.team),100))+.25

func _setup(owner:Dictionary,target:Vector3)->float:
	var aim:Vector3=flat(target-owner.position).normalized()
	var facing:Vector3=flat(owner.facing).normalized()
	var angle:float=acos(clampf(facing.dot(aim),-1,1))
	var offset:Vector3=owner.get("ball_offset",Vector3(0,10,0))
	var depth:float=offset.dot(facing)
	# Mirrors the existing pass-choice envelope, without granting a physical hit.
	# Side-foot passes need no full-body turn. A heel is only a short, near-body return.
	var direct:bool=owner.get("can_pass",false) and angle<2.15 and depth>-.25 and offset.length()<1.06
	var heel:bool=owner.get("can_pass",false) and angle>=2.15 and distance(owner.position,target)<5.0 and depth>=-.42 and depth<=.32 and absf(offset.dot(Vector3(-facing.z,0,facing.x)))<=.48 and offset.length()<=.62 and float(owner.get("ball_relative_speed",99))<5.5
	var turn:float=0.0 if direct or heel else angle/5.8
	return .18+turn+(.12 if not owner.get("foot_idle",true) and not owner.get("foot_hit",false) else 0.0)

func _feasible(owner:Dictionary,receiver:Dictionary,d:Dictionary,opponents:Array[Dictionary],snapshot:Dictionary,ready_now:bool)->bool:
	if receiver.is_empty() or not d.get("valid",true) or not inside(d.point,snapshot) or not _onside(receiver,snapshot):return false
	var setup:float=_setup(owner,d.point)
	var flight:float=float(d.flight)
	var allowed_wait:float=0.0 if ready_now else .9
	if eta(receiver,d.point)>setup+flight+allowed_wait+.18:return false
	if receiver.get("human",false) and distance(receiver.position,d.point)>1.3:
		if distance(receiver.position+flat(receiver.velocity)*(setup+flight),d.point)>1.8:return false
	for other in opponents:
		# Preparation pressure: read positions and velocities, never opponent intentions.
		if eta(other,snapshot.ball_position)<setup-.03:return false
		var opp_eta:float=eta(other,d.point)
		var margin:float=-.20 if d.get("contest",false) else .12
		if opp_eta<maxf(setup+flight,eta(receiver,d.point))+margin:return false
		# Keeper's legal hand radius only matters in the penalty area, and only at landing.
		if other.get("goalkeeper",false) and absf(d.point.x)<20 and absf(d.point.z)>float(snapshot.field_half_length)-16.5 and opp_eta-.3<setup+flight:return false
		for fraction in [.25,.5,.75]:
			# At loft apex, players cannot intercept with a ground tackle.
			var air_time:float=float(d.get("air_time",flight))
			var instant:float=flight*fraction
			var height:float=maxf(.11,float(snapshot.get("capabilities",{}).get("gravity",9.81))*.5*instant*(air_time-instant)) if float(d.loft)>1 else .11
			if height>1.8:continue
			var crossing:Vector3=flat(snapshot.ball_position).lerp(d.point,fraction)
			if eta(other,crossing)<setup+flight*fraction-.05:return false
	return true

# All ordinary and shared-plan choices use the same territory/next-action scale.
# A pass that breaks a line must not be capped to the value of a five-metre carry.
func possession_value(origin:Vector3,destination:Vector3,team:int,opponents:Array[Dictionary],snapshot:Dictionary)->float:
	var attack:Vector3=point(Vector2(0,1),team)
	var progress:float=flat(destination-origin).dot(attack)
	var space:float=minf(openness(destination,opponents),5.0)
	var next_space:float=minf(openness(destination+attack*3.0,opponents),5.0)
	var length:float=float(snapshot.get("field_half_length",52.5))
	var goal:Vector3=attack*length
	var before:float=maxf(0,24.0-distance(origin,goal))*clampf(1.0-absf(origin.x)/25.0,0,1)
	var after:float=maxf(0,24.0-distance(destination,goal))*clampf(1.0-absf(destination.x)/25.0,0,1)
	var bypassed:int=0
	if progress>3.0:
		for enemy in opponents:
			var depth:float=flat(enemy.position-origin).dot(attack)
			if depth>.5 and depth<progress and distance(enemy.position,origin)<18.0:bypassed+=1
	# In the final third, approaching a useful central shooting position matters
	# more than running parallel to the touchline until the byline.
	var final_third:float=clampf((flat(origin).dot(attack)-length*.20)/maxf(1.0,length*.40),0,1)
	var goal_gain:float=distance(origin,goal)-distance(destination,goal)
	var advance:float=lerpf(progress,goal_gain*1.7,final_third)
	return clampf(advance,-10,22)*.48+space*.55+next_space*.20+(after-before)*.24+minf(bypassed,3)*.40

func _value(owner:Dictionary,receiver:Dictionary,d:Dictionary,opponents:Array[Dictionary],snapshot:Dictionary)->float:
	var relief:float=maxf(0,minf(openness(d.point,opponents),5.0)-minf(openness(snapshot.ball_position,opponents),5.0))*.30
	return possession_value(snapshot.ball_position,d.point,int(owner.team),opponents,snapshot)+relief-float(d.flight)*.45-_setup(owner,d.point)*.5

func _candidates(team:int,owner:Dictionary,members:Array[Dictionary],opponents:Array[Dictionary],snapshot:Dictionary,roster:Dictionary,assignments:Dictionary,phase:String)->Array[Dictionary]:
	var choices:Array[Dictionary]=[]
	var attack:Vector3=point(Vector2(0,1),team)
	var width:float=float(snapshot.field_half_width);var length:float=float(snapshot.field_half_length)
	var depth:float=length-flat(owner.position).dot(attack)
	var wide:bool=absf(owner.position.x)>width*.48
	var pressure:float=openness(owner.position,opponents)
	var protected_count:int=0
	for mate in members:
		if int(mate.id)!=int(owner.id) and roster[int(mate.id)].role!="goalkeeper" and flat(mate.position-owner.position).dot(attack)<-2:protected_count+=1
	var crowded:int=0
	for other in opponents:
		if other.position.x*owner.position.x>0:crowded+=1
	# At most one lead/long option per teammate, then a small number of combination choices.
	for receiver in members:
		var id:int=int(receiver.id)
		if id==int(owner.id) or roster[id].role=="goalkeeper":continue
		var gap:float=distance(owner.position,receiver.position)
		var target:Vector3=flat(receiver.position)+flat(receiver.velocity).limit_length(5.6)*clampf(gap/13,.2,1.1)
		var progress:float=flat(target-owner.position).dot(attack)
		var switch_side:bool=not snapshot.get("small_sided",false) and wide and target.x*owner.position.x<0 and absf(target.x-owner.position.x)>width*.65 and crowded>=6
		var loft:bool=gap>24 and (progress>8 or switch_side)
		var d:Dictionary=_delivery(snapshot.ball_position,target,snapshot,loft);d.receiver=id
		var mode:String="SWITCH" if switch_side and loft else "LONG" if loft else "THROUGH"
		if not loft and assignments.get(id,{}).get("role","")=="FORWARD_RUN":d=_delivery(snapshot.ball_position,assignments[id].point,snapshot,false);d.receiver=id
		var leads_run:bool=distance(d.point,receiver.position)>1.0 and (flat(receiver.velocity).dot(flat(d.point-receiver.position).normalized())>.6 or assignments.get(id,{}).get("role","")=="FORWARD_RUN")
		var enough_gain:bool=progress>3.0 and (loft or leads_run) or switch_side
		if enough_gain and (not loft or protected_count>=1) and _feasible(owner,receiver,d,opponents,snapshot,false):
			var score:float=_value(owner,receiver,d,opponents,snapshot)+(1.0 if switch_side else .6 if phase=="transition_attack" and progress>6 else 0)
			choices.append({"mode":mode,"delivery":d,"score":score,"wait":maxf(0,eta(receiver,d.point)-float(d.flight))})
		elif loft and progress>10 and gap>27 and protected_count>=2:
			var support:bool=false
			for mate in members:
				if int(mate.id) not in [id,int(owner.id)] and distance(mate.position,target)<8:support=true;break
			d.contest=true
			if support and _feasible(owner,receiver,d,opponents,snapshot,false):choices.append({"mode":"LONG","subtype":"CONTEST_WITH_SECOND_BALL","delivery":d,"score":_value(owner,receiver,d,opponents,snapshot)-.7})
		# A two-touch consequence: a short wall pass opens a return beyond the presser.
		if gap>=3 and gap<=13 and pressure<5.0 and roster[int(owner.id)].role not in ["goalkeeper","center_back"] and roster[id].role!="center_back":
			var wall:Dictionary=_delivery(snapshot.ball_position,flat(receiver.position)+flat(receiver.velocity)*.25,snapshot,false);wall.receiver=id
			if _feasible(owner,receiver,wall,opponents,snapshot,false):
				var side:float=signf(owner.position.x-receiver.position.x)
				if side==0:side=1.0
				var exits:Array[Vector3]=[flat(owner.position)+attack*4.0+Vector3(side*3.2,0,0),flat(owner.position)+attack*3.2+Vector3(side*4.8,0,0),flat(owner.position)+attack*4.8-Vector3(side*2.8,0,0)]
				if owner.get("human",false):exits=[flat(owner.position)+flat(owner.velocity)*1.0]
				for exit in exits:
					var prepare:float=_setup(owner,wall.point)
					var first_ready:float=prepare+float(wall.flight)
					var second_time:float=maxf(first_ready+.28+float(ground(distance(wall.point,exit),snapshot).time),prepare+eta(owner,exit))
					var return_race:bool=second_time<first_ready+1.65
					for defender in opponents:
						if eta(defender,exit)<second_time-.12:return_race=false;break
					if return_race and flat(exit-owner.position).dot(attack)>1.0 and inside(exit,snapshot) and lane(owner.position,exit,opponents,.75) and lane(wall.point,exit,opponents,.8) and openness(exit,opponents)>1.6:
						choices.append({"mode":"ONE_TWO","delivery":wall,"runner_goal":exit,"score":maxf(_value(owner,receiver,wall,opponents,snapshot),possession_value(snapshot.ball_position,exit,team,opponents,snapshot)-second_time*.45)+.8,"wait":0.0})
		# Relay to a holding player can open the weak side with a second pass.
		if crowded>=6 and wide and not loft and gap<20 and roster[id].get("slot","") in ["DM","LCB","RCB"] and _feasible(owner,receiver,d,opponents,snapshot,false):
			for weak in members:
				if weak.position.x*owner.position.x>=0 or absf(weak.position.x)<width*.45:continue
				var second:Dictionary=_delivery(d.point,flat(weak.position),snapshot,distance(d.point,weak.position)>24)
				if second.valid and openness(weak.position,opponents)>4 and lane(d.point,weak.position,opponents,1.1):
					choices.append({"mode":"SWITCH_RELAY","delivery":d,"weak_receiver":int(weak.id),"score":_value(owner,receiver,d,opponents,snapshot)+1.8});break
	if wide and depth<34 and not snapshot.get("small_sided",false):
		var box:Dictionary=_box_roles(team,owner,members,snapshot,roster)
		for id in box:
			var receiver:Dictionary={}
			for mate in members:
				if int(mate.id)==int(id):receiver=mate;break
			var target:Vector3=box[id].point
			var cutback:bool=box[id].role=="LATE_EDGE" and depth<11
			var d:Dictionary=_delivery(snapshot.ball_position,target,snapshot,not cutback and distance(snapshot.ball_position,target)>19);d.receiver=int(id)
			if not _feasible(owner,receiver,d,opponents,snapshot,false):continue
			var score:float=_value(owner,receiver,d,opponents,snapshot)+(2.0 if cutback else 1.0)
			choices.append({"mode":"CUTBACK" if cutback else "CROSS","delivery":d,"box_assignments":box,"score":score,"wait":maxf(0,eta(receiver,target)-float(d.flight))})
		# Carry outside while box arrivals develop; never promise a cross with no runner.
		if not box.is_empty() and depth>9:
			var advance:Vector3=flat(owner.position)+attack*minf(5.0,depth-6)
			if lane(owner.position,advance,opponents,1.05):choices.append({"mode":"WIDE","delivery":{},"carry_target":advance,"box_assignments":box,"score":4.8})
	if wide and depth<26 and depth>7 and roster[int(owner.id)].role in ["winger","midfielder","striker"]:
		var inside_point:Vector3=flat(owner.position)+attack*2.5+Vector3(-signf(owner.position.x)*4,0,0)
		var goal:Vector3=point(Vector2(0,length),team)
		var aperture:bool=false
		for x in [-2.4,0.0,2.4]:
			if lane(inside_point,goal+Vector3(x,0,0),opponents,.60):aperture=true
		var possible:bool=lane(owner.position,inside_point,opponents,1.05) and aperture
		for other in opponents:
			if eta(other,inside_point)<distance(owner.position,inside_point)/4.0+.3:possible=false;break
		if possible:choices.append({"mode":"CUT_IN","delivery":{},"carry_target":inside_point,"score":5.2})
	return choices

func _box_roles(team:int,owner:Dictionary,members:Array[Dictionary],snapshot:Dictionary,roster:Dictionary)->Dictionary:
	var candidates:Array[Dictionary]=[]
	var attack:Vector3=point(Vector2(0,1),team)
	var length:float=float(snapshot.field_half_length)
	for p in members:
		if int(p.id)==int(owner.id) or p.get("human",false) or roster[int(p.id)].role not in ["striker","winger","midfielder"] or roster[int(p.id)].get("slot","")=="DM":continue
		candidates.append(p)
	candidates.sort_custom(func(a,b):return distance(a.position,snapshot.ball_position)<distance(b.position,snapshot.ball_position))
	var result:Dictionary={}
	var sign_x:float=signf(owner.position.x)
	var targets:Array[Vector3]=[attack*(length-7)+Vector3(sign_x*3,0,0),attack*(length-10),attack*(length-7)+Vector3(-sign_x*5,0,0),attack*(length-17)+Vector3(sign_x*2,0,0)]
	var names:Array[String]=["NEAR_POST","CENTRAL","FAR_POST","LATE_EDGE"]
	var now:float=float(snapshot.get("tactical_clock",0))
	var saved:Dictionary=box_reservations.get(team,{})
	var reserved:Array=[]
	if int(saved.get("owner",-1))==int(owner.id) and now<float(saved.get("until",0)):
		for id in saved.get("ids",[]):
			for p in candidates:
				if int(p.id)==int(id):reserved.append(p);break
	for p in candidates:
		if not reserved.any(func(row):return int(row.id)==int(p.id)):reserved.append(p)
	candidates.assign(reserved)
	if int(saved.get("owner",-1))!=int(owner.id) or now>=float(saved.get("until",0)):
		box_reservations[team]={"owner":int(owner.id),"until":now+2.4,"ids":candidates.slice(0,4).map(func(p):return int(p.id))}
	for i in mini(4,candidates.size()):
		var p:Dictionary=candidates[i]
		var target:Vector3=targets[i]
		# Shape the run early, but don't park four players on the six-yard line
		# while the winger is still thirty metres away from a delivery window.
		var front:float=flat(owner.position).dot(attack)
		target-=attack*maxf(0,target.dot(attack)-front-(1.0 if i==3 else 9.0))
		var limit:float=float(snapshot.get("fixed_offside",{}).get(team,length))
		target-=attack*maxf(0,target.dot(attack)-limit)
		var timing:float=maxf(.7,(length-front-10.0)/maxf(2.8,flat(owner.velocity).length()))
		result[int(p.id)]={"point":target,"role":names[i],"pace":clampf(distance(p.position,target)/maxf(.7,timing+(.6 if i==3 else 0)),2.0,5.6)}
	return result

func _support_assignments(team:int,owner:Dictionary,members:Array[Dictionary],opponents:Array[Dictionary],snapshot:Dictionary,roster:Dictionary,delivery:Dictionary,mode:String)->Dictionary:
	var assignments:Dictionary={}
	var reserved:Array[Vector3]=[flat(owner.position)]
	var runs:Dictionary=snapshot.get("run_reservations",{})
	for run_point:Vector3 in runs.values():reserved.append(run_point)
	var ball:Vector3=snapshot.ball_position
	var advance:Vector3=flat(owner.velocity).limit_length(5.0)*.65
	var attack:Vector3=point(Vector2(0,1),team)
	var scale:float=clampf(float(snapshot.field_half_length)/52.5,.40,1.0)
	var width:float=float(snapshot.field_half_width)
	var length:float=float(snapshot.field_half_length)
	var safety:int=-1
	var best:float=INF
	for p:Dictionary in members:
		var id:int=int(p.id)
		if p.get("human",false):reserved.append(flat(p.position))
		if id==int(owner.id) or p.get("human",false) or roster[id].role=="goalkeeper" or runs.has(id):continue
		if id==int(delivery.get("receiver",-1)):
			assignments[id]={"point":delivery.point,"role":"LANDING" if mode=="LONG" else "DEPTH","pace":6.2}
			reserved.append(delivery.point)
			continue
		var cost:float=distance(p.position,ball)+flat(p.position-ball).dot(attack)*.5
		if roster[id].get("slot","") in ["DM","BACK"]:cost-=100.0
		elif roster[id].role=="center_back":cost-=25.0
		if cost<best:best=cost;safety=id
	var ordered:Array[Dictionary]=members.duplicate()
	ordered.sort_custom(func(a,b):return false if int(a.id)==int(b.id) else true if int(a.id)==safety else false if int(b.id)==safety else int(a.id)<int(b.id))
	var second_ball_used:bool=false
	for p:Dictionary in ordered:
		var id:int=int(p.id);var role:Dictionary=roster[id]
		if id==int(owner.id) or p.get("human",false) or role.role=="goalkeeper" or assignments.has(id) or runs.has(id):continue
		var side:float=signf(float(role.get("lane",0.0)))
		if side==0:side=-1.0 if id%2 else 1.0
		side*=1.0 if team==0 else -1.0 # roster lanes are team-local; candidate positions are canonical world.
		var target:Vector3=snapshot.get("role_targets",{}).get(id,flat(p.position))
		var job:String="SHAPE"
		if id==safety:job="SAFE"
		elif role.role=="winger":job="WIDTH"
		elif role.role=="striker":job="DEPTH"
		elif role.role=="full_back":job="REAR_WIDTH"
		elif role.role=="center_back" or role.get("duty","")=="hold":job="REST_DEFENSE"
		else:job="DIAGONAL"
		# Move offers ahead of the carrier's current path while retaining a rear
		# outlet and the two centre-backs. Existing reservations still separate them.
		if members.size()<=3:job="SAFE" if id==safety else "DIAGONAL"
		if job=="SAFE":
			target=flat(ball)-attack*maxf(3.2,6.0*scale)+Vector3(side*maxf(2.4,4.5*scale),0,0)
		elif job=="DIAGONAL":
			# A reachable angled triangle, not every midfielder's distant static slot.
			target=flat(ball)+attack*((4.5 if side*ball.x>=0 else 8.0)*scale)+Vector3(side*maxf(4.0,7.5*scale),0,0)
		elif job=="WIDTH":
			target.x=side*width*.80
			target+=attack*clampf(flat(ball-target).dot(attack),-4.0,6.0)
		if job in ["WIDTH","DEPTH","DIAGONAL","PASS_RUN"]:target+=advance
		# A short pass-and-move offer stays within this player's assigned channel.
		if recent_passes.has(id) and job not in ["SAFE","REST_DEFENSE","REAR_WIDTH"]:
			target+=attack*minf(2.4,3.5*scale)
			job="PASS_RUN"

		var chosen:Vector3=target
		var quality:float=-INF
		# Slot alternatives are checked jointly, with a distinct pass angle and depth.
		for shift in [Vector2.ZERO,Vector2(-2,0),Vector2(2,0),Vector2(0,-2),Vector2(-1.5,-1.5),Vector2(1.5,1.5)]:
			var candidate:Vector3=target+Vector3(shift.x,0,0)*maxf(.7,scale)+attack*shift.y*maxf(.7,scale)
			candidate.x=clampf(candidate.x,-width+1.6,width-1.6)
			candidate.z=clampf(candidate.z,-length+2.0,length-2.0)
			if job in ["WIDTH","REAR_WIDTH","REST_DEFENSE"] and absf(float(role.get("lane",0)))>.1:candidate.x=side*maxf(absf(candidate.x),width*.10)
			if members.size()>3:
				var limit:float=float(snapshot.get("fixed_offside",{}).get(team,length))
				candidate-=attack*maxf(0,candidate.dot(attack)-limit)
			var score:float=minf(openness(candidate,opponents),6.0)*.3-distance(candidate,target)*.3-distance(candidate,p.position)*.08
			if job not in ["REST_DEFENSE","REAR_WIDTH"] and not lane(ball,candidate,opponents,1.0):score-=5.0
			for other:Vector3 in reserved:
				var gap:float=distance(candidate,other)
				score-=maxf(0.0,maxf(2.8,5.0*scale)-gap)*4.0
				var a:Vector3=flat(candidate-ball);var b:Vector3=flat(other-ball)
				if a.length()>1.0 and b.length()>1.0 and a.normalized().dot(b.normalized())>.90 and absf(a.length()-b.length())<5.0*maxf(.65,scale):score-=4.0
			if score>quality:quality=score;chosen=candidate
		assignments[id]={"point":chosen,"role":job,"pace":5.4 if job not in ["DEPTH","SECOND_BALL"] else 6.2}
		reserved.append(chosen)
	return assignments

func _advance_run(team:int,owner:Dictionary,members:Array[Dictionary],opponents:Array[Dictionary],snapshot:Dictionary,roster:Dictionary,now:float,assignments:Dictionary)->void:
	var attack:Vector3=point(Vector2(0,1),team)
	var old:Dictionary=forward_runs.get(team,{})
	if not old.is_empty() and now<float(old.until) and assignments.has(int(old.id)) and lane(snapshot.ball_position,old.point,opponents,1.0) and openness(old.point,opponents)>1.5:
		assignments[int(old.id)]={"point":old.point,"role":"FORWARD_RUN","pace":5.6};return
	if now<float(old.get("next",0)) or int(snapshot.get("carrier_id",-1))!=int(owner.id):return
	if openness(owner.position,opponents)<.9:return
	var best:Dictionary={};var score:float=-INF
	var scale:float=clampf(float(snapshot.field_half_length)/52.5,.4,1)
	for row in members:
		var id:int=int(row.id)
		if not assignments.has(id) or row.get("human",false) or assignments[id].role in ["SAFE","REST_DEFENSE","REAR_WIDTH"]:continue
		if roster[id].get("slot","") not in ["CF","LW","RW","LCM","RCM","LF","RF"]:continue
		var forward:float=flat(row.position-owner.position).dot(attack)
		if forward< -5 or forward>24*maxf(.6,scale):continue
		var target:Vector3=flat(row.position)+attack*(3.0+3.0*scale)
		target.x=lerpf(target.x,float(assignments[id].point.x),.3)
		var limit:float=float(snapshot.get("fixed_offside",{}).get(team,float(snapshot.field_half_length)-2))
		target-=attack*maxf(0,target.dot(attack)-limit+.45)
		if distance(target,row.position)<2 or not inside(target,snapshot) or not lane(row.position,target,opponents,.85) or not lane(snapshot.ball_position,target,opponents,1.05) or openness(target,opponents)<2.0:continue
		var value:float=openness(target,opponents)+forward*.15-distance(row.position,target)*.15-maxf(0,40-float(row.get("stamina",100)))*.08
		for other in assignments:
			if int(other)!=id:value-=maxf(0,2.5-distance(assignments[other].point,target))*3
		if value>score:score=value;best={"id":id,"point":target,"until":now+1.6,"next":now+3.6}
	if not best.is_empty():
		forward_runs[team]=best;assignments[int(best.id)]={"point":best.point,"role":"FORWARD_RUN","pace":5.6}
