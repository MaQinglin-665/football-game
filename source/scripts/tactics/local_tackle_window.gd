extends RefCounted
## Standing tackle only. Tactical permission is 5 Hz; at most one slot per team
## checks nearby ball geometry at 13.3 Hz. FootAction owns contact/physics.
const LOCAL_PERIOD_S := .075
const TACTICAL_PERIOD_S := .20
const PERMISSION_LIFETIME_S := .30
const MAX_SAMPLE_AGE_S := .35
var simulation_time := 0.0
var next_check_time := 0.0
var sample: Dictionary = {}
var slots: Dictionary = {}
var previous_slots: Dictionary = {}
var next_observation_time := 0.0
var next_permission_time := 0.0
var allow_new_permissions := false
var starts := 0
var checks := 0
var last_decision: Dictionary = {}

func clear() -> void:
	sample.clear()
	slots.clear()
	previous_slots.clear()
	allow_new_permissions = false
	last_decision.clear()
	next_check_time = simulation_time

func elapse(delta: float) -> void:
	# Never clamp elapsed time to make an old observation look younger.
	if not is_finite(delta) or delta<0:
		clear()
		return
	simulation_time += delta

func begin_observation(known: Dictionary) -> void:
	# Adapter calls once per normal tactical refresh, after the planner tick.
	# This is a recorded snapshot, not a new local-perception/physics query.
	previous_slots = slots.duplicate()
	slots.clear()
	allow_new_permissions = simulation_time>=next_permission_time
	if allow_new_permissions: next_permission_time = simulation_time+TACTICAL_PERIOD_S
	# Contact-triggered RECEIVE replans may run between normal 5 Hz ticks.
	# They can revoke permission promptly, but cannot mint faster perception.
	if not sample.is_empty() and (int(sample.owner_id)!=int(known.owner_id) or int(sample.generation)!=int(known.generation) or int(sample.ball_id)!=int(known.ball_id)):
		sample.clear()
	if simulation_time<next_observation_time: return
	next_observation_time = simulation_time+TACTICAL_PERIOD_S
	sample = known.duplicate()
	sample["sample_time_s"] = simulation_time

func grant(actor: Node3D, intent: Dictionary, designated_slot: int, actor_slot: int) -> void:
	if sample.is_empty() or actor.is_human or actor.is_goalkeeper or not actor.visible: return
	if int(sample.get("owner_team",-1))<0 or int(sample.owner_team)==actor.team: return
	var primary: String = String(intent.get("primary_action",""))
	var task: Dictionary = intent.get("defensive_task",{})
	var permitted: bool = bool(intent.get("press",false)) or primary in ["PRESS","CONTAIN","TACKLE"] or String(task.get("task","")) in ["PRESS","CONTAIN"]
	if not permitted or bool(intent.get("receive",false)) or intent.has("receive_plan") or intent.has("give_go_plan"): return
	if primary in ["RECEIVE","RECEIVE_LOOSE","GIVE_GO_RUN","PASS","SHOT","CROSS","CUTBACK","CLEARANCE"]: return
	if String(intent.get("action","NONE")) not in ["NONE","TACKLE"]: return
	if String(task.get("task","")) in ["PRESS","CONTAIN"] and int(task.get("target_id",-1))>=0 and int(task.target_id)!=int(sample.owner_slot): return
	var retained: Dictionary = previous_slots.get(actor.team,{})
	if not allow_new_permissions and (retained.is_empty() or retained.actor!=actor or int(retained.owner_id)!=int(sample.owner_id)): return
	var point: Vector3 = sample.position
	var gap: float = Vector2(actor.position.x-point.x,actor.position.z-point.z).length()
	# Activation bound only. This never extends the final boot/socket reach.
	var closing:Vector3=sample.owner_velocity-actor.velocity
	closing.y=0
	var to_actor:Vector3=actor.position-point;to_actor.y=0
	var approach:float=maxf(0.0,closing.dot(to_actor.normalized()))
	if gap>2.0+minf(.8,approach*.15): return
	var until_time: float = simulation_time+PERMISSION_LIFETIME_S if allow_new_permissions else float(retained.until_s)
	var candidate := {"actor":actor,"owner_id":int(sample.owner_id),"until_s":until_time,"designated":actor_slot==designated_slot,"distance":gap,"actor_slot":actor_slot,"primary":primary}
	var previous: Dictionary = slots.get(actor.team,{})
	if previous.is_empty() or (candidate.designated and not previous.designated) or (candidate.designated==previous.designated and (gap<float(previous.distance) or (is_equal_approx(gap,float(previous.distance)) and actor_slot<int(previous.actor_slot)))):
		slots[actor.team] = candidate

func try_due(game: Node) -> void:
	if simulation_time<next_check_time: return
	next_check_time = simulation_time+LOCAL_PERIOD_S # No catch-up burst after a slow frame.
	if not is_instance_valid(game.ball.carrier):
		_face_incoming_shot(game) # Ground interceptions have one shared human/AI owner.
		return
	if sample.is_empty() or slots.is_empty(): return
	if game.phase!=game.Phase.PLAY or not game.ai_enabled or game.services.rules.state!=game.Rules.State.LIVE:
		clear()
		return
	if int(sample.generation)!=game.match_generation or int(sample.ball_id)!=game.ball.get_instance_id():
		clear()
		return
	# Revoke stale carrier permission before the bounded local contact forecast.
	if not is_instance_valid(game.ball.carrier) or game.ball.carrier.get_instance_id()!=int(sample.owner_id):
		clear()
		return
	var age: float = simulation_time-float(sample.sample_time_s)
	if not is_finite(age) or age<0 or age>MAX_SAMPLE_AGE_S:
		clear()
		return
	var known := {"position":game.ball.position,"velocity":game.ball.velocity,"age_s":0.0} # Local geometry for the at-most-two authorized challengers.
	for team in slots.keys(): # At most 2, independent of a 22-player roster.
		var permission: Dictionary = slots[team]
		var actor: Node3D = permission.actor
		if not is_instance_valid(actor) or not actor.visible or not actor.active or actor.is_human or actor.is_goalkeeper: continue
		if simulation_time>float(permission.until_s) or int(permission.owner_id)!=int(sample.owner_id): continue
		if not actor.foot.idle() or actor.tackle_cooldown>0 or not actor.pending_kick.is_empty(): continue
		if not game.can_foot_action(actor,"TACKLE"): continue
		# Re-check higher-priority intent, never clear or supersede a receive/carry plan.
		var intent: Dictionary = actor.tactical_intent
		if bool(intent.get("receive",false)) or intent.has("receive_plan") or intent.has("give_go_plan"): continue
		if String(intent.get("action","NONE")) not in ["NONE","TACKLE"]: continue
		checks += 1
		var plan: Dictionary = game.standing_tackle_prediction(actor,known)
		if plan.is_empty(): continue
		var seen_ball: Vector3 = sample.position
		if seen_ball.y>.46: continue
		var owner_position: Vector3 = sample.owner_position
		var owner_gap: float = Vector2(seen_ball.x-owner_position.x,seen_ball.z-owner_position.z).length()
		var shoe_gap: float = float(sample.owner_shoe_gap_m)
		var exposed: bool = shoe_gap>.025 if shoe_gap>=0 else owner_gap>.32
		var relative: Vector3 = sample.velocity-sample.owner_velocity
		relative.y = 0
		var toward: Vector3 = actor.position-seen_ball
		toward.y = 0
		# Known outward roll can open a shoe gap during preparation. No .90 m
		# carrier gap or root-facing cone is the sole permit for a real side poke.
		if not exposed and owner_gap>.24 and relative.length()>.35 and relative.dot(toward.normalized())>.20:
			exposed = true
		# Brake before a covered poke when momentum is carrying the defender
		# across the line. Exposed balls retain the same legal contact window.
		var across:Vector3=actor.velocity;across.y=0
		var to_ball:Vector3=known.position-actor.position;to_ball.y=0
		var rush_miss:bool=across.length()>2.8 and across.normalized().dot(to_ball.normalized())<.55
		if not exposed and rush_miss:
			last_decision={"started":false,"reason":"brake_before_covered_poke","actor_slot":int(permission.actor_slot)}
			continue
		# Exposure is a preference, not a veto. Actual boot/leg ordering decides legality.
		# A tucked ball is contestable from a legal shoe path, including a side poke.
		last_decision = {"actor_slot":int(permission.actor_slot),"sample_time_s":float(sample.sample_time_s),"age_s":age,"known_position":seen_ball,"known_velocity":sample.velocity,"prediction":plan.tackle_center,"owner_shoe_gap_m":shoe_gap,"started":false}
		if game.attempt_tackle(actor,known):
			starts += 1
			last_decision["started"] = true
			last_decision["action_sequence"] = actor.foot.sequence

func debug_snapshot() -> Dictionary:
	return {"simulation_time_s":simulation_time,"sample_time_s":sample.get("sample_time_s",-1.0),"sample_age_s":simulation_time-float(sample.get("sample_time_s",simulation_time)),"slot_count":slots.size(),"next_observation_time_s":next_observation_time,"next_permission_time_s":next_permission_time,"checks":checks,"starts":starts,"last_decision":last_decision.duplicate()}

func _try_intercept(game:Node)->void:
	var ball:Node3D=game.ball
	_face_incoming_shot(game)
	if game.phase!=game.Phase.PLAY or not game.ai_enabled or ball.held or ball.position.y>.46 or ball.velocity.length()<.05:return
	var chosen:Node3D=null
	var best:=INF
	var known:Dictionary={"position":ball.position,"velocity":ball.velocity,"age_s":0.0}
	for actor in game.agents:
		if not actor.active or not actor.visible or actor.is_human or actor.is_goalkeeper or actor.team==ball.last_touch_team or (not actor.foot.idle() and not (actor.foot.kind=="RECEIVE" and not actor.foot.hit)) or actor.tackle_cooldown>0 or not actor.pending_kick.is_empty():continue
		if actor.position.distance_squared_to(ball.position)>12.25:continue
		var plan:Dictionary=game.standing_tackle_prediction(actor,known)
		if plan.is_empty():continue
		var cost:float=actor.position.distance_squared_to(plan.tackle_center)
		if cost<best:best=cost;chosen=actor
	if chosen!=null and game.attempt_tackle(chosen,known):starts+=1

func _face_incoming_shot(game:Node)->void:
	var ball:Node3D=game.ball
	if game.phase!=game.Phase.PLAY or not game.ai_enabled or ball.held or is_instance_valid(ball.carrier) or ball.velocity.length()<6.0:return
	for actor in game.agents:
		if not actor.active or not actor.visible or actor.is_goalkeeper or actor.team==ball.last_touch_team or actor.position.distance_squared_to(ball.position)>9.0:continue
		if not actor.foot.idle() or not actor.pending_kick.is_empty():continue
		var relative:Vector3=ball.velocity-actor.velocity
		var offset:Vector3=ball.position-actor.position
		var planar:Vector3=Vector3(relative.x,0,relative.z)
		var eta:float=clampf(-Vector3(offset.x,0,offset.z).dot(planar)/maxf(planar.length_squared(),.01),0,.22)
		var arrival:Vector3=offset+relative*eta
		if eta>.015 and arrival.y>.46 and arrival.y<1.85 and Vector2(arrival.x,arrival.z).length()<.65:
			actor.face_target=Vector3(offset.x,0,offset.z).normalized()
			# Turn the actual torso toward the locally observed shot; normal motor,
			# skeleton and passive collision decide the block, never a catch flag.
