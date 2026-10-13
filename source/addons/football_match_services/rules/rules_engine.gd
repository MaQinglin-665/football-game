class_name FBMatchRulesEngine
extends RefCounted

const ConfigScript = preload("rules_config.gd")
enum State { IDLE, LIVE, STOPPAGE, RESTART_SETUP, RESTART_READY,
	RESTART_IN_FLIGHT, GOAL_CELEBRATION, HALF_TIME, FULL_TIME }
signal rules_event(event: Dictionary)
signal ball_command(command: Dictionary)
signal restart_plan(plan: Dictionary)

var config: FBMatchRulesConfig
var state: int = State.IDLE
var restart: Dictionary = {}
var scores: Array[int] = [0, 0]
var half: int = 1
var half_elapsed: float = 0.0
var first_kickoff_team: int = 0
var last_touch: Dictionary = {}
var attack_signs: Array[int] = [-1, 1]
var period_extension: bool = false
var diagnostics: Dictionary = {"duplicate_contacts": 0, "ignored_challenges": 0}
var _roster: Array[Dictionary] = []
var _ball: Dictionary = {}
var _seen: Dictionary = {}
var _seen_order: Array[String] = []
var _match_id: int = 0
var _serial: int = 0
var _event_serial: int = 0
var _state_age: float = 0.0
var _retry_age: float = 0.0
var _restart_origin: Dictionary = {}
var _second_touch_actor: int = -1
var _penalty_active: bool = false
var _penalty_keeper: int = -1
var _drop_touchers: Array[int] = []
var _plan_age: float = 0.0
var _plan_revision: int = 0

func _init(configuration: FBMatchRulesConfig = null) -> void:
	config = configuration if configuration != null else ConfigScript.new()

func set_roster(roster: Array[Dictionary]) -> void:
	_roster = roster.duplicate(true)

func start(kickoff_team: int = 0) -> void:
	_match_id += 1
	_event_serial = 0
	_serial = 0
	_seen.clear()
	_seen_order.clear()
	scores.assign([0, 0])
	half = 1
	half_elapsed = 0.0
	attack_signs.assign([-1, 1])
	first_kickoff_team = clampi(kickoff_team, 0, 1)
	last_touch.clear()
	period_extension = false
	_penalty_active = false
	_restart_origin.clear()
	_second_touch_actor = -1
	_drop_touchers.clear()
	_queue_restart("kickoff", first_kickoff_team, Vector3.ZERO, "match_start", true)

func attack_direction(team: int) -> Vector3:
	return Vector3(0.0, 0.0, attack_signs[clampi(team, 0, 1)])

func defending_team(goal_side: int) -> int:
	return 0 if attack_signs[0] == -goal_side else 1

func is_ball_live() -> bool:
	return state == State.LIVE

func can_touch_ball(actor_id: int) -> bool:
	# Restart contacts use request_restart; ordinary pickup is never allowed in dead-ball states.
	return state == State.LIVE and actor_id >= 0

func can_take_restart(actor_id: int) -> bool:
	return state == State.RESTART_READY and actor_id == int(restart.get("taker_id", -1))

func state_name() -> String:
	return State.keys()[state]

func snapshot() -> Dictionary:
	return {"state": state_name(), "scores": scores.duplicate(), "half": half,
		"half_elapsed": half_elapsed, "time_remaining": maxf(0.0, config.half_seconds - half_elapsed),
		"restart": restart.duplicate(true), "attack_signs": attack_signs.duplicate(),
		"ball_live": is_ball_live(), "allow_player_motion": true, "allow_camera_look": true,
		"period_extension": period_extension, "restart_progress": restart_progress()}

func restart_progress() -> Dictionary:
	if state not in [State.STOPPAGE, State.RESTART_SETUP, State.RESTART_READY, State.RESTART_IN_FLIGHT] or not restart.has("kind"):
		return {}
	var taker := _actor(int(restart.get("taker_id", -1)))
	var distance := -1.0
	if not taker.is_empty() and restart.has("taker_target"):
		distance = _flat_distance(taker["position"], restart["taker_target"])
	var reasons: Dictionary = {}
	if restart.has("taker_target"):
		for violation in restart_violations():
			var reason: String = str(violation["reason"])
			reasons[reason] = int(reasons.get(reason, 0)) + 1
	return {"taker_id": restart.get("taker_id", -1), "taker_jersey": taker.get("jersey", -1),
		"taker_name": taker.get("display_name", "指定球员"), "taker_distance": distance,
		"ready": state == State.RESTART_READY, "blocking_reasons": reasons,
		"clearance_metres": restart.get("clearance", 0.0), "plan_revision": _plan_revision,
		"awaiting_field_entry": state == State.RESTART_IN_FLIGHT and restart["kind"] == "throw_in"}

func report_ball_contact(contact: Dictionary) -> bool:
	if not _accept_id(contact, "contact"):
		diagnostics.duplicate_contacts += 1
		return false
	if state != State.LIVE:
		return false
	var actor_id: int = int(contact.get("actor_id", -1))
	var team: int = int(contact.get("team", -1))
	if actor_id < 0 or team not in [0, 1]:
		return false
	if actor_id == _second_touch_actor and bool(contact.get("restart_contact", false)):
		# The host may publish the same launching foot contact after executing the release.
		# It is not a second touch, and restart_taken already played its sound once.
		return false
	if not _restart_origin.is_empty() and str(_restart_origin.get("kind", "")) == "dropped_ball":
		if actor_id not in _drop_touchers:
			_drop_touchers.append(actor_id)
		if _drop_touchers.size() >= 2:
			_restart_origin.clear()
	# A frame/post/ground contact has no team; only actual player contacts come here.
	if actor_id == _second_touch_actor:
		_second_touch_actor = -1
		_queue_restart("indirect_free_kick", 1 - team, contact.get("position", Vector3.ZERO), "restart_double_touch")
		return false
	if _second_touch_actor >= 0:
		_second_touch_actor = -1
	if not _restart_origin.is_empty() and str(_restart_origin.get("kind", "")) != "dropped_ball" and actor_id != int(_restart_origin.get("taker_id", -1)):
		_restart_origin.clear()
	last_touch = contact.duplicate(true)
	_emit("ball_contact", {"contact": contact.duplicate(true)})
	if period_extension and _penalty_active and actor_id != _penalty_keeper:
		_end_half()
	elif not period_extension and _penalty_active and actor_id != _penalty_keeper and actor_id != int(restart.get("taker_id", -1)):
		_penalty_active = false
	return true

func report_challenge(challenge: Dictionary) -> bool:
	if not _accept_id(challenge, "challenge") or state != State.LIVE or not bool(challenge.get("ball_in_play_at_contact", true)):
		return false
	var offender_team: int = int(challenge.get("offender_team", -1))
	var victim_team: int = int(challenge.get("victim_team", -1))
	if offender_team not in [0, 1] or victim_team != 1 - offender_team:
		return false
	var offence: String = str(challenge.get("offence", "collision"))
	var severity: String = str(challenge.get("severity", "legal"))
	var contact: bool = bool(challenge.get("contact", false))
	var dangerous: bool = bool(challenge.get("dangerous", false))
	var confirmed: bool = bool(challenge.get("confirmed", false))
	var direct := offence in ["trip", "push", "hold", "kick", "strike", "charge", "tackle", "impede_contact"]
	var indirect := offence == "dangerous_play" and not contact and dangerous
	# ball_first/timestamps are retained evidence, NEVER a blanket foul or safety exemption.
	if not confirmed or not (direct or indirect) or (direct and severity not in ["careless", "reckless", "excessive"]):
		diagnostics.ignored_challenges += 1
		return false
	if offence in ["collision", "shoulder_contact"]:
		return false
	if offence in ["trip","tackle","kick"] and challenge.has("disruptive"):
		if not bool(challenge.disruptive) and severity not in ["reckless","excessive"]:
			diagnostics.ignored_challenges += 1
			return false
		if bool(challenge.get("ball_first",false)) and severity=="careless" and not dangerous:
			diagnostics.ignored_challenges += 1
			return false
	var at: Vector3 = challenge.get("position", Vector3.ZERO)
	if not in_field(at):
		# Off-field misconduct/restart nuances are outside this version.
		return false
	var kind := "indirect_free_kick" if indirect else "direct_free_kick"
	var goal_side: int = -attack_signs[offender_team]
	if direct and in_penalty_area(at, goal_side):
		kind = "penalty"
	print("RULE_FOUL id=",challenge.get("event_id","")," source=",challenge.get("source","")," offence=",offence," severity=",severity," separation=",challenge.get("shin_separation",-1)," normal_fraction=",challenge.get("normal_fraction",-1)," restart=",kind)
	_emit("foul", {"challenge": challenge.duplicate(true), "restart_kind": kind,
		"discipline_pending": severity in ["reckless", "excessive"]})
	_queue_restart(kind, victim_team, at, offence)
	return true

func step(delta: float, ball_snapshot: Dictionary, roster: Array[Dictionary]) -> void:
	if delta < 0.0:
		return
	set_roster(roster)
	_ball = ball_snapshot.duplicate(true)
	_state_age += delta
	if state in [State.LIVE, State.RESTART_IN_FLIGHT]:
		half_elapsed = minf(config.half_seconds, half_elapsed + delta)
		if half_elapsed >= config.half_seconds and _penalty_active:
			period_extension = true
	if state == State.LIVE:
		if _check_crossing(ball_snapshot):
			return
		if period_extension and _penalty_active and _ball_velocity().length() < 0.08:
			_end_half()
		elif half_elapsed >= config.half_seconds and not _penalty_active:
			_end_half()
		elif _penalty_active and _ball_velocity().length() < 0.08:
			_penalty_active = false
	elif state == State.STOPPAGE and _state_age >= config.stoppage_seconds:
		_begin_setup()
	elif state in [State.RESTART_SETUP, State.RESTART_READY]:
		_update_setup(delta)
	elif state == State.RESTART_IN_FLIGHT:
		var p: Vector3 = ball_snapshot.get("position", restart.get("ball_position", Vector3.ZERO))
		if restart.get("kind", "") == "throw_in":
			if absf(p.x) < config.half_width and absf(p.z) <= config.half_length:
				_become_live()
			elif p.y <= _radius() + 0.015 or _state_age >= config.restart_flight_timeout:
				_emit("restart_rejected", {"reason": "throw_did_not_enter", "restart": restart.duplicate(true)})
				_begin_setup()
		elif restart.get("kind", "") == "dropped_ball" and p.y <= _radius() + 0.015:
			_become_live()
	elif state == State.GOAL_CELEBRATION and _state_age >= config.celebration_seconds:
		_queue_restart("kickoff", int(restart.get("team", 0)), Vector3.ZERO, "after_goal", true)
	elif state == State.HALF_TIME and _state_age >= config.half_time_seconds:
		half = 2
		half_elapsed = 0.0
		attack_signs[0] *= -1
		attack_signs[1] *= -1
		_emit("ends_changed", {"attack_signs": attack_signs.duplicate()})
		_queue_restart("kickoff", 1 - first_kickoff_team, Vector3.ZERO, "second_half", true)

func request_restart(actor_id: int, direction: Vector3, power: float, lift: float = 0.3, contact_event_id: String = "") -> Dictionary:
	if state != State.RESTART_READY:
		return _reject("restart_not_ready")
	if actor_id != int(restart.get("taker_id", -1)):
		return _reject("wrong_taker")
	var violations := restart_violations()
	if not violations.is_empty():
		_set_state(State.RESTART_SETUP)
		return _reject("players_not_ready", {"violations": violations})
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.0001 or power < 0.5:
		return _reject("ball_must_clearly_move")
	flat = flat.normalized()
	var kind: String = str(restart["kind"])
	var team: int = int(restart["team"])
	if kind == "dropped_ball":
		_restart_origin = restart.duplicate(true)
		_second_touch_actor = -1
		_drop_touchers.clear()
		_command("release", {"position": restart["ball_position"], "velocity": Vector3.ZERO,
			"actor_id": -1, "team": team, "kind": kind, "clear_carrier": true})
		_emit("restart_taken", {"restart": restart.duplicate(true), "position": restart["ball_position"], "actor_id": -1})
		_set_state(State.RESTART_IN_FLIGHT)
		return {"ok": true, "reason": "", "kind": kind}
	if kind == "penalty" and flat.dot(attack_direction(team)) <= 0.05:
		return _reject("penalty_must_go_forward")
	if kind == "throw_in" and flat.dot(restart["inward"]) <= 0.05:
		return _reject("throw_must_enter_field")
	if not contact_event_id.is_empty():
		_accept_id({"event_id": contact_event_id}, "contact")
	var speed := clampf(power, 3.0, 32.0)
	var up := clampf(lift, 0.0, 7.0)
	if kind == "throw_in":
		speed = clampf(power, 4.0, 14.0)
		up = clampf(lift, 2.0, 5.0)
	_restart_origin = restart.duplicate(true)
	_second_touch_actor = actor_id
	last_touch = {"actor_id": actor_id, "team": team, "position": restart["point"],
		"kind": "throw" if kind == "throw_in" else "restart_kick", "event_id": "restart:%d" % _serial}
	_penalty_active = kind == "penalty"
	_penalty_keeper = int(restart.get("goalkeeper_id", -1))
	_command("release", {"position": restart["ball_position"], "velocity": flat * speed + Vector3.UP * up,
		"actor_id": actor_id, "team": team, "kind": kind, "clear_carrier": true})
	_emit("restart_taken", {"restart": restart.duplicate(true), "position": restart["ball_position"], "actor_id": actor_id})
	if kind == "throw_in":
		_set_state(State.RESTART_IN_FLIGHT)
	else:
		_become_live()
	return {"ok": true, "reason": "", "kind": kind}

func in_field(p: Vector3) -> bool:
	return absf(p.x) <= config.half_width + 0.00001 and absf(p.z) <= config.half_length + 0.00001

func in_penalty_area(p: Vector3, goal_side: int) -> bool:
	return absf(p.x) <= config.penalty_half_width + 0.00001 and \
		p.z * goal_side >= config.half_length - config.penalty_depth - 0.00001 and \
		p.z * goal_side <= config.half_length + 0.00001

func restart_violations() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if restart.is_empty():
		return result
	var taker := _actor(int(restart.get("taker_id", -1)))
	if taker.is_empty():
		result.append({"actor_id": -1, "reason": "no_taker"})
	elif _flat_distance(taker["position"], restart["taker_target"]) > 1.3:
		result.append({"actor_id": taker["id"], "reason": "taker_not_at_ball"})
	for actor in _roster:
		if not bool(actor.get("active", true)):
			continue
		if int(actor["id"]) == int(restart.get("taker_id", -1)):
			continue
		var p: Vector3 = actor["position"]
		var projected := constrain_restart_position(actor, p)
		if _flat_distance(p, projected) > 0.04:
			result.append({"actor_id": actor["id"], "reason": "restart_position", "target": projected})
	if restart.get("kind", "") == "penalty" and _actor(int(restart.get("goalkeeper_id", -1))).is_empty():
		result.append({"actor_id": -1, "reason": "no_goalkeeper"})
	return result

func constrain_restart_position(actor: Dictionary, desired: Vector3) -> Vector3:
	if state not in [State.RESTART_SETUP, State.RESTART_READY] or restart.is_empty():
		return desired
	var result := desired
	var id: int = int(actor.get("id", -1))
	if id == int(restart.get("taker_id", -1)):
		return result
	var kind: String = str(restart["kind"])
	var team: int = int(actor.get("team", -1))
	var awarded_team: int = int(restart["team"])
	var goal_side: int = int(restart.get("goal_side", 0))
	var at: Vector3 = restart["point"]
	if kind == "penalty" and id == int(restart.get("goalkeeper_id", -1)):
		result.x = clampf(result.x, -config.goal_half_width + config.actor_margin, config.goal_half_width - config.actor_margin)
		result.z = goal_side * config.half_length
		return result
	if kind == "kickoff":
		var attacking_z: int = attack_signs[clampi(team, 0, 1)]
		if result.z * attacking_z > -config.actor_margin:
			result.z = -attacking_z * config.actor_margin
	if kind == "penalty":
		result.x = clampf(result.x, -config.half_width + config.actor_margin, config.half_width - config.actor_margin)
		result.z = clampf(result.z, -config.half_length + config.actor_margin, config.half_length - config.actor_margin)
		if result.z * goal_side > at.z * goal_side - config.actor_margin:
			result.z = at.z - goal_side * config.actor_margin
		if absf(result.x) < config.penalty_half_width + config.actor_margin and result.z * goal_side > config.half_length - config.penalty_depth - config.actor_margin:
			result.z = goal_side * (config.half_length - config.penalty_depth - config.actor_margin)
	if kind == "goal_kick" and team != awarded_team and in_penalty_area(result, goal_side):
		result.z = goal_side * (config.half_length - config.penalty_depth - config.actor_margin)
	var needs_clearance := team != awarded_team or kind in ["penalty", "dropped_ball"]
	if needs_clearance:
		var distance: float = float(restart.get("clearance", 0.0)) + config.actor_margin
		if kind == "corner":
			# 9.15 m from ARC, not the centre of the corner circle.
			distance += config.corner_radius
		var clearance_origin := at
		if kind == "corner":
			clearance_origin = Vector3(signf(at.x) * config.half_width, at.y, goal_side * config.half_length)
		var away := Vector3(result.x - clearance_origin.x, 0.0, result.z - clearance_origin.z)
		if kind == "corner":
			# Keep clearance projection on the pitch side of the nearest corner.
			away.x = -signf(at.x) * maxf(absf(away.x), 0.2)
			away.z = -goal_side * maxf(absf(away.z), 0.2)
		if away.length() < distance:
			if away.length_squared() < 0.0001:
				away = -attack_direction(team)
			result = Vector3(clearance_origin.x, result.y, clearance_origin.z) + away.normalized() * distance
	# Projection into the legal region must keep kickoff/penalty behind restrictions too.
	if kind == "kickoff" and result.z * attack_signs[clampi(team, 0, 1)] > -config.actor_margin:
		result.z = -attack_signs[clampi(team, 0, 1)] * config.actor_margin
	if kind == "penalty" and result.z * goal_side > at.z * goal_side - config.actor_margin:
		result.z = at.z - goal_side * config.actor_margin
	if kind == "goal_kick" and team != awarded_team and in_penalty_area(result, goal_side):
		result.z = goal_side * (config.half_length - config.penalty_depth - config.actor_margin)
	return result

func _check_crossing(ball_snapshot: Dictionary) -> bool:
	if not ball_snapshot.has("position"):
		return false
	var current: Vector3 = ball_snapshot["position"]
	var previous: Vector3 = ball_snapshot.get("previous_position", current)
	var r := _radius()
	var crossings: Array[Dictionary] = []
	for axis in [0, 2]:
		var limit: float = (config.half_width if axis == 0 else config.half_length) + r
		for side in [-1, 1]:
			if current[axis] * side > limit + 0.00001:
				var change: float = current[axis] - previous[axis]
				var fraction := 0.0
				if absf(change) > 0.000001 and previous[axis] * side <= limit:
					fraction = clampf((side * limit - previous[axis]) / change, 0.0, 1.0)
				crossings.append({"axis": axis, "side": side, "fraction": fraction,
					"position": previous.lerp(current, fraction)})
	if crossings.is_empty():
		return false
	# First crossed boundary wins, not an unconditional goal-line priority.
	crossings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["fraction"] < b["fraction"])
	var crossing: Dictionary = crossings[0]
	var at: Vector3 = crossing["position"]
	var side: int = int(crossing["side"])
	var team: int = int(last_touch.get("team", -1))
	if int(crossing["axis"]) == 0:
		at.x = side * config.half_width
		at.z = clampf(at.z, -config.half_length, config.half_length)
		_queue_restart("throw_in" if team >= 0 else "dropped_ball", 1 - team if team >= 0 else 0, at, "touchline")
		return true
	var defenders := defending_team(side)
	var mouth := absf(at.x) + r <= config.goal_half_width and at.y + r <= config.goal_height and at.y - r >= -0.015
	if mouth:
		var scorer := 1 - defenders
		if not _restart_origin.is_empty():
			var direct_kind: String = str(_restart_origin.get("kind", ""))
			var origin_team: int = int(_restart_origin.get("team", scorer))
			if direct_kind in ["throw_in", "indirect_free_kick", "dropped_ball"] or scorer != origin_team:
				var next_kind := "goal_kick" if scorer == origin_team else "corner"
				_queue_restart(next_kind, defenders if next_kind == "goal_kick" else scorer, at, "no_direct_restart_goal", false, side)
				return true
		scores[scorer] += 1
		_emit("goal", {"team": scorer, "scores": scores.duplicate(), "position": at})
		_command("hold", {"clear_carrier": true, "reason": "goal"})
		_emit("referee_signal", {"gesture": "goal", "point": Vector3.ZERO, "team": scorer})
		if period_extension or half_elapsed >= config.half_seconds:
			_end_half()
		else:
			restart = {"team": defenders}
			_set_state(State.GOAL_CELEBRATION)
		_penalty_active = false
		return true
	var kind := "corner" if team == defenders else "goal_kick"
	var awarded := 1 - defenders if kind == "corner" else defenders
	if period_extension:
		_end_half()
	else:
		_queue_restart(kind if team >= 0 else "dropped_ball", awarded, at, "goal_line", false, side)
	return true

func _queue_restart(kind: String, team: int, at: Vector3, reason: String, immediate: bool = false, side_override: int = 0) -> void:
	if period_extension:
		_end_half()
		return
	_serial += 1
	_plan_revision = 0
	_plan_age = 0.0
	_second_touch_actor = -1
	_restart_origin.clear()
	_penalty_active = kind == "penalty"
	var goal_side := side_override
	if goal_side == 0:
		goal_side = attack_signs[team] if kind == "penalty" else -attack_signs[team]
	var point := at
	point.y = 0.0
	var clearance := config.kick_clearance
	var inward := attack_direction(team)
	if kind == "kickoff":
		point = Vector3.ZERO
	elif kind == "throw_in":
		var side := 1 if point.x >= 0.0 else -1
		point.x = side * config.half_width
		point.z = clampf(point.z, -config.half_length, config.half_length)
		inward = Vector3(-side, 0, 0)
		clearance = config.throw_clearance
	elif kind == "corner":
		var corner_x := 1 if point.x >= 0.0 else -1
		# A point inside the nearest quarter-circle arc, not the out-of-bounds ball position.
		var inset := config.corner_radius * 0.45
		point = Vector3(corner_x * (config.half_width - inset), 0, goal_side * (config.half_length - inset))
		inward = Vector3(-corner_x, 0, -goal_side).normalized()
	elif kind == "goal_kick":
		point = Vector3(clampf(point.x, -config.goal_area_half_width * 0.6, config.goal_area_half_width * 0.6), 0,
			goal_side * (config.half_length - config.goal_area_depth * 0.65))
		inward = Vector3(0, 0, -goal_side)
		clearance = 0.0
	elif kind == "penalty":
		point = Vector3(0, 0, goal_side * (config.half_length - config.penalty_distance))
		inward = Vector3(0, 0, goal_side)
	elif kind == "dropped_ball":
		point.x = clampf(point.x, -config.half_width + 1.0, config.half_width - 1.0)
		point.z = clampf(point.z, -config.half_length + 1.0, config.half_length - 1.0)
		clearance = config.drop_clearance
		if in_penalty_area(point, 1) or in_penalty_area(point, -1):
			goal_side = 1 if point.z >= 0.0 else -1
			team = defending_team(goal_side)
	elif kind == "indirect_free_kick" and in_penalty_area(point, -attack_signs[1 - team]) and absf(point.x) <= config.goal_area_half_width and absf(point.z) >= config.half_length - config.goal_area_depth:
		point.z = signf(point.z) * (config.half_length - config.goal_area_depth)
	restart = {"serial": _serial, "kind": kind, "team": team, "point": point, "goal_side": goal_side,
		"inward": inward, "clearance": clearance, "reason": reason, "taker_id": -1, "goalkeeper_id": -1}
	_retry_age = 0.0
	_emit("restart_awarded", {"restart": restart.duplicate(true)})
	_command("hold", {"clear_carrier": true, "reason": kind, "block_touches": true})
	_emit("referee_signal", {"gesture": kind, "point": point, "team": team})
	_set_state(State.STOPPAGE)
	if immediate:
		_begin_setup()

func _begin_setup(exclude_human: bool = false) -> void:
	_set_state(State.RESTART_SETUP)
	var team: int = int(restart["team"])
	var at: Vector3 = restart["point"]
	var candidates: Array[Dictionary] = []
	for actor in _roster:
		if int(actor.get("team", -1)) == team and bool(actor.get("active", true)) and (not exclude_human or not bool(actor.get("human", false))):
			candidates.append(actor)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da := _flat_distance(a["position"], at)
		var db := _flat_distance(b["position"], at)
		if bool(a.get("human", false)) and da < config.human_taker_preference_range:
			da -= config.human_taker_preference_range
		if bool(b.get("human", false)) and db < config.human_taker_preference_range:
			db -= config.human_taker_preference_range
		return da < db)
	if not candidates.is_empty():
		restart["taker_id"] = int(candidates[0]["id"])
	var kind: String = str(restart["kind"])
	var inward: Vector3 = restart["inward"]
	restart["taker_target"] = at - inward * (0.25 if kind == "throw_in" else 0.7)
	restart["ball_position"] = at + Vector3.UP * (1.9 if kind == "throw_in" else config.ball_radius + 0.012)
	if kind == "dropped_ball":
		restart["ball_position"] = at + Vector3.UP * 0.85
	if kind == "penalty":
		restart["goalkeeper_id"] = -1
		var opponents: Array[Dictionary] = []
		for actor in _roster:
			if int(actor.get("team", -1)) != team and bool(actor.get("active", true)):
				opponents.append(actor)
				if bool(actor.get("goalkeeper", false)):
					restart["goalkeeper_id"] = int(actor["id"])
					break
		if int(restart["goalkeeper_id"]) < 0 and config.allow_proxy_goalkeeper and not opponents.is_empty():
			opponents.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var goal := Vector3(0, 0, int(restart["goal_side"]) * config.half_length)
				return _flat_distance(a["position"], goal) < _flat_distance(b["position"], goal))
			restart["goalkeeper_id"] = int(opponents[0]["id"])
			restart["proxy_goalkeeper"] = true
	_command("place", {"position": restart["ball_position"], "clear_carrier": true, "block_touches": true})
	_publish_plan()

func _publish_plan() -> void:
	_plan_age = 0.0
	_plan_revision += 1
	var targets: Dictionary = {}
	for actor in _roster:
		if not bool(actor.get("active", true)):
			continue
		var id: int = int(actor["id"])
		var current: Vector3 = actor["position"]
		var wanted: Vector3 = restart["taker_target"] if id == int(restart.get("taker_id", -1)) else constrain_restart_position(actor, current)
		if _flat_distance(current, wanted) > 0.02:
			targets[id] = wanted
	var plan := restart.duplicate(true)
	plan["targets"] = targets
	plan["allow_player_motion"] = true
	plan["allow_camera_look"] = true
	plan["human_instruction_only"] = true
	plan["revision"] = _plan_revision
	restart_plan.emit(plan)

func _update_setup(delta: float) -> void:
	_retry_age += delta
	_plan_age += delta
	if int(restart.get("taker_id", -1)) < 0 or _actor(int(restart.get("taker_id", -1))).is_empty():
		if _retry_age >= config.restart_retry_seconds:
			_retry_age = 0.0
			_emit("restart_recovery", {"reason": "missing_taker", "restart": restart.duplicate(true)})
			_begin_setup()
		return
	var violations := restart_violations()
	if violations.is_empty() and _state_age >= config.restart_prepare_seconds:
		if state != State.RESTART_READY:
			_set_state(State.RESTART_READY)
			_emit("restart_ready", {"restart": restart.duplicate(true)})
			_emit("referee_signal", {"gesture": "ready", "point": restart["point"], "team": restart["team"]})
	elif not violations.is_empty() and state == State.RESTART_READY:
		_set_state(State.RESTART_SETUP)
	if not violations.is_empty() and _plan_age >= maxf(0.25, config.restart_plan_refresh_seconds):
		_publish_plan()
	if _retry_age >= config.restart_retry_seconds:
		_retry_age = 0.0
		_emit("restart_recovery", {"reason": "walk_to_restart", "violations": violations, "restart": restart.duplicate(true)})
		if restart.get("kind", "") == "penalty" and _actor(int(restart.get("goalkeeper_id", -1))).is_empty():
			_begin_setup()
			return
		var taker := _actor(int(restart.get("taker_id", -1)))
		var has_ai := _roster.any(func(actor: Dictionary) -> bool:
			return int(actor.get("team", -1)) == int(restart["team"]) and not bool(actor.get("human", false)) and bool(actor.get("active", true)))
		if config.reassign_absent_human_taker and not taker.is_empty() and bool(taker.get("human", false)) and has_ai and _flat_distance(taker["position"], restart["taker_target"]) > 1.3:
			_emit("restart_taker_reassigned", {"previous_actor_id": taker["id"], "reason": "human_free_to_observe"})
			_begin_setup(true)
			return
		_publish_plan()

func _become_live() -> void:
	_set_state(State.LIVE)
	_emit("ball_in_play", {"restart_kind": restart.get("kind", "")})

func _end_half() -> void:
	_penalty_active = false
	period_extension = false
	_second_touch_actor = -1
	_restart_origin.clear()
	restart.clear()
	_command("hold", {"clear_carrier": true, "reason": "period_end"})
	if half == 1:
		_set_state(State.HALF_TIME)
		_emit("half_time", {"scores": scores.duplicate()})
	else:
		_set_state(State.FULL_TIME)
		_emit("full_time", {"scores": scores.duplicate()})
	_emit("referee_signal", {"gesture": "period_end", "point": Vector3.ZERO})

func _set_state(next_state: int) -> void:
	state = next_state
	_state_age = 0.0
	_emit("state_changed", snapshot())

func _reject(reason: String, details: Dictionary = {}) -> Dictionary:
	var result := details.duplicate(true)
	result["ok"] = false
	result["reason"] = reason
	_emit("restart_rejected", result)
	return result

func _actor(id: int) -> Dictionary:
	for actor in _roster:
		if int(actor.get("id", -2)) == id and bool(actor.get("active", true)):
			return actor
	return {}

func _radius() -> float:
	return maxf(0.01, float(_ball.get("radius", config.ball_radius)))

func _ball_velocity() -> Vector3:
	return _ball.get("velocity", Vector3.ZERO)

func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))

func _accept_id(data: Dictionary, category: String) -> bool:
	var raw: String = str(data.get("event_id", ""))
	if raw.is_empty():
		return false
	var key := category + ":" + raw
	if _seen.has(key):
		return false
	_seen[key] = true
	_seen_order.append(key)
	if _seen_order.size() > 2048:
		_seen.erase(_seen_order.pop_front())
	return true

func _emit(type: String, data: Dictionary = {}) -> void:
	_event_serial += 1
	var event := data.duplicate(true)
	event["type"] = type
	event["event_id"] = "rules:%d:%d" % [_match_id, _event_serial]
	rules_event.emit(event)

func _command(action: String, data: Dictionary) -> void:
	var command := data.duplicate(true)
	command["action"] = action
	command["restart_serial"] = _serial
	command["allow_player_motion"] = true
	command["allow_camera_look"] = true
	ball_command.emit(command)
