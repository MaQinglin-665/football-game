class_name FootballReceivePlan
extends RefCounted
## Original planning code. It reads live ball samples; never moves a ball/body.
## A confirmed foot pass starts one shared plan; real control contact completes it.
const Motion=preload("res://scripts/tactics/receive_motion.gd")
const MAX_LIFE := 6.0
## R004 intercept lock: once a reachable meet point is close in time, keep it so
## the receiver stops re-adjusting every refresh. Unlock on real divergence.
const LOCK_HORIZON_S := 0.70
const LOCK_TOLERANCE_M := 0.60
const LOCK_ENABLED := true
var roster: Dictionary = {}
var active: Dictionary = {}
var last_plan: Dictionary = {}
var events: Array[Dictionary] = []
var seen: Dictionary = {}
var sequence := 0
var clock := 0.0

func configure(rows: Dictionary) -> void:
	roster = rows.duplicate(true)
	active.clear()
	last_plan.clear()
	events.clear()
	seen.clear()
	sequence = 0
	clock = 0

func consume_contact(event: Dictionary, now: float) -> bool:
	clock = now
	if event.get("kind","") not in ["FOOT_TOUCH","KEEPER_RELEASE"] or not event.get("success",false): return false
	var actor_id: int = int(event.get("actor_id",-1))
	if not roster.has(actor_id): return false
	var key := String(event.get("event_key","%s:%s:%s" % [event.get("physics_frame",-1),event.get("serial",-1),actor_id]))
	if seen.has(key): return false
	seen[key] = true
	if seen.size()>256: seen.erase(seen.keys()[0])
	var action := String(event.get("tactical_action",event.get("action","")))
	var physical_action := String(event.get("action",""))
	if action in ["PASS","CROSS","CUTBACK","CLEARANCE"]:
		cancel("superseded_by_confirmed_pass",now)
		var receiver_id: int = int(event.get("receiver_id",-1))
		if receiver_id==actor_id or not roster.has(receiver_id) or int(roster[receiver_id].team)!=int(roster[actor_id].team): return false
		sequence += 1
		var point: Vector3 = event.get("ball_position",event.get("point",Vector3.ZERO))
		var velocity: Vector3 = event.get("after_velocity",Vector3.ZERO)
		active = {"pass_id":"%d:%s" % [sequence,key],"passer_id":actor_id,"receiver_id":receiver_id,"team":int(roster[actor_id].team),"state":"IN_FLIGHT","started_at":now,"deadline":now+MAX_LIFE,"receive_point":point,"approach_point":point,"arrival_time":now,"arrival_speed":Vector2(velocity.x,velocity.z).length(),"turn_time":0.0,"opponent_margin":null,"source":"confirmed_keeper_release" if event.get("kind","")=="KEEPER_RELEASE" else "confirmed_foot_pass","first_pass_action":action,"completion_contact":null,"cancel_reason":"","live_ball_position":point,"live_ball_velocity":velocity,"unreachable_since":-1.0,"revision":0,"phase":"APPROACH"}
		if event.has("space_target"):active.planned_target=event.space_target
		if event.has("delivery_target"):
			active.planned_target=event.delivery_target
			active.delivery_time=event.get("delivery_time",0.0)
		_event("START","confirmed_foot_pass")
		return true
	if active.is_empty(): return false
	var carrier_id: int = int(event.get("carrier_id",-1))
	var receive_touch:bool=physical_action in ["RECEIVE","STOP","SETTLE","PULL","CONTROL"] or active.get("unsettled_contact",false) and physical_action in ["CLOSE","TURN","SHIELD","CARRY"]
	if actor_id==int(active.receiver_id) and receive_touch and carrier_id==actor_id:
		if not controlled_result(event):
			active.unsettled_contact=true
			return true
		active.state = "COMPLETED"
		active.completed_at=now
		active.completion_contact = {"actor_id":actor_id,"action":physical_action,"physics_frame":event.get("physics_frame",-1),"serial":event.get("serial",-1),"event_key":key}
		_event("COMPLETE","actual_receiver_control_contact")
		last_plan = active.duplicate(true)
		active.clear()
		return true
	if carrier_id>=0 and carrier_id!=int(active.receiver_id):
		cancel("opponent_control_contact" if int(roster.get(carrier_id,{}).get("team",-1))!=int(active.team) else "other_teammate_control_contact",now)
		return true
	if physical_action=="SHOT":
		cancel("other_confirmed_kick",now)
		return true
	return false

static func controlled_result(event:Dictionary)->bool:
	# A shoe collision can claim ownership while the ball is still dropping or
	# rebounding. Keep reception reserved until a later controllable contact.
	var position:Vector3=event.get("ball_position",Vector3.ZERO)
	var velocity:Vector3=event.get("after_velocity",Vector3.ZERO)
	return position.y<=.45 and absf(velocity.y)<=2.8

func cancel(reason: String, now: float) -> void:
	clock = now
	if active.is_empty(): return
	active.state = "CANCELED"
	active.cancel_reason = reason
	_event("CANCEL",reason)
	last_plan = active.duplicate(true)
	active.clear()

func tick(snapshot: Dictionary, now: float, _delta: float) -> Dictionary:
	clock = now
	if active.is_empty(): return {}
	var by_id: Dictionary = {}
	for p in snapshot.get("players",[]):
		if p.get("active",true): by_id[int(p.id)] = p
	var receiver: Dictionary = by_id.get(int(active.receiver_id),{})
	if receiver.is_empty():
		cancel("receiver_unavailable",now)
		return {}
	if now>=float(active.deadline):
		cancel("timeout",now)
		return {}
	var carrier_id: int = int(snapshot.get("carrier_id",-1))
	if carrier_id>=0 and not (carrier_id==int(active.receiver_id) and active.get("unsettled_contact",false)):
		# Ownership or proximity alone is not a successful reception assertion.
		cancel("receiver_control_without_completion_contact" if carrier_id==int(active.receiver_id) else "opponent_controls_ball" if int(by_id.get(carrier_id,{}).get("team",-1))!=int(active.team) else "other_teammate_controls_ball",now)
		return {}
	var ball: Vector3 = snapshot.ball_position
	var velocity: Vector3 = snapshot.ball_velocity
	if not ball.is_finite() or not velocity.is_finite():
		cancel("invalid_ball_sample",now)
		return {}
	if absf(ball.x)>float(snapshot.field_half_width)+.25 or absf(ball.z)>float(snapshot.field_half_length)+.25:
		cancel("ball_outside_pitch",now)
		return {}
	var prediction: Dictionary = _intercept(receiver,snapshot)
	if not prediction.reachable and float(prediction.late_by)>1.0:
		if float(active.unreachable_since)<0: active.unreachable_since = now
		elif now-float(active.unreachable_since)>.8:
			cancel("receiver_cannot_reach_ball",now)
			return {}
	else: active.unreachable_since = -1.0
	active.sample_frame=int(snapshot.get("physics_frame",0))
	active.sample_time=now
	active.live_ball_position = ball
	active.live_ball_velocity = velocity
	if LOCK_ENABLED:
		prediction = _apply_lock(prediction)
	active.receive_point = prediction.ball_point
	active.approach_point = prediction.body_point
	active.arrival_time = now+float(prediction.horizon)
	active.arrival_speed = prediction.speed
	active.turn_time = prediction.turn_time
	active.reachable = prediction.reachable
	active.face_direction = prediction.face_direction
	active.pace = prediction.pace
	active.phase = prediction.phase
	active.revision = int(active.revision)+1
	var opponent_eta := INF
	for p in by_id.values():
		if int(p.team)==int(active.team): continue
		opponent_eta = minf(opponent_eta,float(_eta(p,prediction.body_point,prediction.face_direction,snapshot).ready_time))
	active.opponent_margin = opponent_eta-float(prediction.receiver_eta) if is_finite(opponent_eta) else null
	return active.duplicate(true)

func _apply_lock(prediction: Dictionary) -> Dictionary:
	var locked: bool = active.get("intercept_locked",false)
	var point: Vector3 = prediction.ball_point
	if locked:
		var held: Vector3 = active.locked_ball_point
		var drift := Vector2(point.x-held.x,point.z-held.z).length()
		if not prediction.reachable or drift>LOCK_TOLERANCE_M:
			active.intercept_locked=false
			active.lock_releases=int(active.get("lock_releases",0))+1
			return prediction
		var kept := prediction.duplicate()
		kept.ball_point = held
		kept.body_point = active.locked_body_point
		kept.face_direction = active.locked_face
		return kept
	if prediction.reachable and float(prediction.horizon)<=LOCK_HORIZON_S and not prediction.get("await_settle",false):
		active.intercept_locked=true
		active.locked_ball_point=point
		active.locked_body_point=prediction.body_point
		active.locked_face=prediction.face_direction
	return prediction

func _intercept(receiver: Dictionary, snapshot: Dictionary) -> Dictionary:
	var cap: Dictionary = snapshot.get("capabilities",{})
	var ball: Vector3 = snapshot.ball_position
	var velocity: Vector3 = snapshot.ball_velocity
	var flat_velocity := Vector3(velocity.x,0,velocity.z)
	var speed := flat_velocity.length()
	var axis := flat_velocity.normalized()
	var decel := maxf(0.0,float(cap.get("roll_deceleration",.75)))
	var gravity := float(cap.get("gravity",9.81))
	var approach := Vector3(ball.x-receiver.position.x,0,ball.z-receiver.position.z).normalized()
	if approach.length()<.1: approach = -axis
	if approach.length()<.1: approach = receiver.get("facing",Vector3.FORWARD)
	var best: Dictionary = {}
	var bounce_meet:Dictionary={}
	var smallest_lateness := INF
	var live_samples:Array=snapshot.get("roll_samples",[])
	for i in range(1,maxi(30,live_samples.size())+1):
		var horizon := float(i)*.10
		var moving_time := minf(horizon,speed/decel) if decel>.001 else horizon
		var point := ball+axis*maxf(0,speed*moving_time-.5*decel*moving_time*moving_time)
		point.y = maxf(.11,ball.y+velocity.y*horizon-.5*gravity*horizon*horizon)
		var predicted_speed:float=maxf(0,speed-decel*moving_time)
		var unsettled:bool=false
		var samples:Array=live_samples # R004: hoisted lookup, same array
		if samples.size()>=i:
			point=samples[i-1].point
			horizon=float(samples[i-1].get("time",horizon))
			predicted_speed=float(samples[i-1].speed)
			# A fast descending first bounce is a contact opportunity, not yet a
			# controllable foot reception. Meet its actual reachable continuation.
			unsettled=absf((samples[i-1].get("velocity",Vector3.ZERO) as Vector3).y)>3.0
		if point.y>float(cap.get("ground_receive_height",.42)) or predicted_speed>float(cap.get("safe_receive_speed",14)): continue
		if absf(point.x)>float(snapshot.field_half_width)-.6 or absf(point.z)>float(snapshot.field_half_length)-.6: continue

		# Meet the future ball from our travel side. Facing only the ball's old
		# position makes a lead receiver backpedal away from the intersection.
		var toward_meet:Vector3=Vector3(point.x-receiver.position.x,0,point.z-receiver.position.z).normalized()
		var contact_face:Vector3=(toward_meet*.80+approach*.20).normalized()
		if contact_face.length_squared()<.01:contact_face=approach
		var body_point := Vector3(point.x,0,point.z)-contact_face*.38
		var eta: Dictionary = _eta(receiver,body_point,contact_face,snapshot)
		var lateness: float = float(eta.ready_time)-horizon
		if snapshot.has("motor_profile"):
			var motion:Dictionary=Motion.predict(receiver,body_point,contact_face,horizon,snapshot)
			lateness=(float(motion.gap)-.46)/maxf(1.0,float(cap.get("receive_speed",5.6)))
			eta.ready_time=horizon+lateness
		if unsettled:
			if bounce_meet.is_empty() or lateness<float(bounce_meet.late_by):
				bounce_meet={"ball_point":point,"body_point":body_point,"horizon":horizon,"speed":predicted_speed,"turn_time":eta.turn_time,"receiver_eta":eta.ready_time,"late_by":lateness,"reachable":lateness<=0.0,"face_direction":contact_face,"await_settle":true}
			continue
		if lateness<smallest_lateness:
			smallest_lateness = lateness
			best = {"ball_point":point,"body_point":body_point,"horizon":horizon,"speed":predicted_speed,"turn_time":eta.turn_time,"receiver_eta":eta.ready_time,"late_by":lateness,"reachable":lateness<=0.0,"face_direction":contact_face}
		if lateness<=0.0: break
	# Preserve a reachable bounce destination if no settled sample is visible
	# yet. Returning the ball's current airborne position sends receivers away
	# from their landing area and falsely cancels a perfectly viable reception.
	if not bounce_meet.is_empty() and (best.is_empty() or not best.reachable and bounce_meet.reachable):best=bounce_meet
	if best.is_empty():
		var body_point := Vector3(ball.x,0,ball.z)-approach*.38
		var eta: Dictionary = _eta(receiver,body_point,approach,snapshot)
		best = {"ball_point":ball,"body_point":body_point,"horizon":.1,"speed":speed,"turn_time":eta.turn_time,"receiver_eta":eta.ready_time,"late_by":float(eta.ready_time),"reachable":false,"face_direction":approach}
	var gap: float = Vector2(best.body_point.x-receiver.position.x,best.body_point.z-receiver.position.z).length()
	var running := Vector2(receiver.get("velocity",Vector3.ZERO).x,receiver.get("velocity",Vector3.ZERO).z).length()
	var brake := maxf(1.0,float(cap.get("brake_deceleration",5.5)))
	var braking_distance := running*running/(2*brake)
	best.phase = "BRAKE" if gap<braking_distance+.50 else "TURN_READY" if float(best.turn_time)>.20 else "APPROACH"
	best.pace = Motion.pace(receiver.position,best.body_point,receiver.get("velocity",Vector3.ZERO),cap)
	return best

func _eta(p: Dictionary, point: Vector3, face: Vector3, snapshot: Dictionary) -> Dictionary:
	var cap: Dictionary = snapshot.get("capabilities",{})
	var offset := Vector3(point.x-p.position.x,0,point.z-p.position.z)
	var distance := maxf(0,offset.length()-.55)
	var axis := offset.normalized()
	var speed := maxf(1,float(p.get("ability_speed",cap.get("receive_speed",6.2))))
	var acceleration := maxf(1,float(p.get("ability_acceleration",cap.get("run_acceleration",6.8))))
	var velocity: Vector3 = p.get("velocity",Vector3.ZERO)
	var along := velocity.dot(axis)
	var initial := clampf(along,0,speed)
	var ramp := (speed-initial)/acceleration
	var ramp_distance := (initial+speed)*.5*ramp
	var travel := (sqrt(initial*initial+2*acceleration*distance)-initial)/acceleration if distance<=ramp_distance else ramp+(distance-ramp_distance)/speed
	if along<-.25: travel += -along/maxf(1,float(cap.get("brake_deceleration",5.5)))
	var facing: Vector3 = p.get("facing",face)
	var turn := acos(clampf(Vector3(facing.x,0,facing.z).normalized().dot(face),-1,1))/maxf(1,float(cap.get("turn_speed",5.8)))
	# In this host movement and facing rotate concurrently, rather than RCSS cycles.
	var reaction:float=.045 if not active.is_empty() and int(active.get("receiver_id",-1))==int(p.id) else float(cap.get("reaction_delay",.16))
	return {"ready_time":maxf(travel,minf(turn,.12))+reaction+.035,"turn_time":turn}

func _event(kind: String, reason: String) -> void:
	events.append({"time":clock,"event":kind,"pass_id":active.pass_id,"passer_id":active.passer_id,"receiver_id":active.receiver_id,"team":active.team,"reason":reason})
	if events.size()>128: events.pop_front()

func debug_snapshot() -> Dictionary:
	return {"active":active.duplicate(true),"last_plan":last_plan.duplicate(true),"events":events.duplicate(true),"clock":clock}

# Canonical-frame advisory; buffering/contact belongs to the input/action owner.
func set_next_intent(receiver_id: int, choice: Dictionary) -> void:
	if active.is_empty() or int(active.receiver_id)!=receiver_id: return
	for key in ["next_action","next_direction","next_target","next_receiver_id","next_valid_until","first_touch_direction","first_touch_target","first_touch_valid_until"]:
		if choice.has(key): active[key] = choice[key]
