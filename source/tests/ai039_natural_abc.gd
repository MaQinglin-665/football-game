extends SceneTree
## One spatial fixture, then real World/director/input/contact/rules only.
## No consume_contact, _set_kick, take, request_actor_kick or foot.begin calls.
var game: Node
var frame := 0
var seconds := 8.0
var scenario := "open_lane"
var output := ""
var contacts: Array[Dictionary] = []
var samples: Array[Dictionary] = []
var gates: Array[Dictionary] = []
var plans: Array[Dictionary] = []
var checks: Array[Dictionary] = []
var completed: Array[Dictionary] = []
const A_ID := 4 # Existing yellow CB/hold: both other yellow actors are eligible C.

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		if arg.begins_with("--seconds="): seconds = clampf(float(arg.trim_prefix("--seconds=")),6.0,12.0)
		if arg.begins_with("--scenario="): scenario = arg.trim_prefix("--scenario=")
	call_deferred("run")

func v(value: Vector3) -> Array: return [value.x,value.y,value.z]

func contact_record(e: Dictionary) -> void:
	var actor: Variant = e.get("actor",null)
	if not is_instance_valid(actor): return
	var id: int = game.players.find(actor)
	var recipient: Variant = e.get("receiver",null)
	var recipient_id: int = game.players.find(recipient) if is_instance_valid(recipient) else -1
	var key := "%s:%s:%s" % [e.get("physics_frame",-1),e.get("serial",-1),id]
	contacts.append({"frame":frame,"physics_frame":e.get("physics_frame",-1),"key":key,"kind":e.get("kind",""),"actor":id,"receiver":recipient_id,"action":e.get("action",""),"success":e.get("success",false),"owner":game.players.find(game.ball.carrier),"point":v(e.get("point",Vector3.ZERO)),"before":v(e.get("before_velocity",Vector3.ZERO)),"after":v(e.get("after_velocity",Vector3.ZERO)),"shoe":actor.foot.actual_contact.duplicate(true),"failure":actor.foot.contact_failure,"one_touch":actor.foot.kick_intent.get("one_touch_pass",false)})

func snapshot() -> Dictionary:
	var rows: Array[Dictionary] = []
	for id in game.players.size():
		var p: Node3D = game.players[id]
		rows.append({"id":id,"team":p.team,"position":game.tactics_bridge.canonical(p.position),"velocity":game.tactics_bridge.canonical(p.velocity),"facing":game.tactics_bridge.canonical(p.facing),"human":p.is_human,"active":p.visible,"can_kick":game.ball.can_kick(p),"kick_ready":p.action_cooldown<=0,"foot_idle":p.foot.idle(),"foot_action":p.foot.kind,"can_reach":game.can_reach_ball(p)})
	return {"players":rows,"ball_position":game.tactics_bridge.canonical(game.ball.position),"ball_velocity":game.tactics_bridge.canonical(game.ball.velocity),"carrier_id":game.players.find(game.ball.carrier),"possession_age":game.ball.possession_age,"call_id":-1,"small_sided":true,"tactical_scale":clampf(game.field_half_length/52.5,.40,1.0),"field_half_width":game.field_half_width,"field_half_length":game.field_half_length,"goal_half_width":game.goal_width*.5,"capabilities":{"tackle_reach":game.tuning.tackle_reach,"receive_speed":6.2,"run_acceleration":game.physics_profile.start_acceleration_mps2,"brake_deceleration":game.physics_profile.brake_deceleration_mps2,"turn_speed":5.8,"reaction_delay":.16}}

func decision_record() -> void:
	var snap := snapshot()
	var owner_id := int(snap.carrier_id)
	var director: FootballTacticalDirector = game.tactical_director
	var row := {"frame":frame,"clock":director.clock,"owner":owner_id,"possession_age":snap.possession_age,"snapshot":snap.duplicate(true),"carrier_setup":director.carrier_setup.duplicate(true),"requested_support":director.requested_support.duplicate(),"styles":director.styles.duplicate(),"best":{},"candidates":[]}
	if owner_id>=0:
		var owner: Dictionary = snap.players[owner_id]
		var members: Array[Dictionary] = []
		var opponents: Array[Dictionary] = []
		for p in snap.players:
			if int(p.team)==int(owner.team): members.append(p)
			else: opponents.append(p)
		# Queries only: these methods return scores/geometry and cannot kick or claim.
		row.best = director._best_pass(owner,members,opponents,snap,director.styles[int(owner.team)])
		for recipient in members:
			if int(recipient.id)==owner_id: continue
			var distance: float = director._distance(owner.position,recipient.position)
			var power: float = clampf(distance*1.05+7.5,10.0,24.0)
			var point: Vector3 = recipient.position+director._flat(recipient.velocity)*minf(distance/power,.55)
			point = director._world(director._clip_pitch(director._local(point,int(owner.team)),snap,1.6),int(owner.team))
			row.candidates.append({"id":recipient.id,"role":director.roster[int(recipient.id)].role,"distance":distance,"point":point,"lane":director._lane_clear(snap.ball_position,point,opponents,1.2),"prepare":director._pass_preparation_safe(owner,point,opponents,snap),"flight":director._pass_window_safe(snap.ball_position,point,opponents,power,snap),"onside":director._onside_receiver(recipient,opponents,snap),"openness":director._openness(point,opponents)})
	var combination: Dictionary = director.third_man if not director.third_man.is_empty() else director.third_man_last
	var c_id := int(combination.get("runner_id",-1))
	if c_id>=0 and c_id<snap.players.size():
		var runner: Dictionary = snap.players[c_id]
		var opposition: Array[Dictionary] = []
		for p in snap.players:
			if int(p.team)!=int(runner.team): opposition.append(p)
		var middle: Dictionary = snap.players[int(combination.middle_id)]
		row.second_leg_prediction = director._third_man_preparation(middle,runner,snap)
		row.outlet_committed = combination.get("outlet_committed",false)
		row.preparation_origin = combination.get("preparation_origin",Vector3.ZERO)
		var target: Vector3 = combination.runner_target
		var origin: Vector3 = director.receive_plan.active.get("receive_point",snap.ball_position)
		var eta: Dictionary = director.receive_plan._eta(runner,target,director._flat(origin-target).normalized(),snap)
		row.third_man_validity = {"state":combination.get("state",""),"cancel_reason":combination.get("cancel_reason",""),"runner_onside":director._onside_receiver(runner,opposition,snap),"target_onside":director._support_onside(target,int(runner.team),opposition,snap),"run_route_clear":director._third_man_run_route_clear(runner.position,target,opposition),"legacy_lane_clear":director._lane_clear(runner.position,target,opposition,.8),"short_run_segment":director._flat(target-runner.position).length_squared()<.1,"pass_lane_clear":director._lane_clear(origin,runner.position,opposition,1.2),"target_openness":director._openness(target,opposition),"origin_to_target":director._distance(origin,target),"origin_to_C":director._distance(origin,runner.position),"C_to_target":director._distance(runner.position,target),"C_ready_time":eta.ready_time,"target":target,"origin":origin}
	gates.append(row)

func chain_proof(plan: Dictionary) -> Dictionary:
	if plan.get("state","")!="COMPLETED": return {}
	var a_id := int(plan.get("passer_id",-1))
	var b_id := int(plan.get("middle_id",-1))
	var c_id := int(plan.get("runner_id",-1))
	if a_id!=A_ID or a_id==b_id or a_id==c_id or b_id==c_id: return {}
	var first: Dictionary = {}
	var second: Dictionary = {}
	var final: Dictionary = {}
	for e in contacts:
		if not e.success or e.kind!="FOOT_TOUCH" or not e.shoe.get("valid",false): continue
		if e.action=="PASS" and e.actor==a_id and e.receiver==b_id and String(plan.get("pass_id","")).ends_with(":"+String(e.key)): first = e
		if e.action=="PASS" and e.actor==b_id and e.receiver==c_id and e.key==plan.get("second_contact",""): second = e
		if e.actor==c_id and e.owner==c_id and e.action in ["RECEIVE","STOP","SETTLE","PULL","CONTROL"] and e.key==plan.get("completion_contact",""): final = e
	if first.is_empty() or second.is_empty() or final.is_empty(): return {}
	if not (int(first.physics_frame)<int(second.physics_frame) and int(second.physics_frame)<int(final.physics_frame)): return {}
	return {"A":a_id,"B":b_id,"C":c_id,"pass_id":plan.pass_id,"first":first,"second":second,"completion":final}

func run() -> void:
	game = load("res://scenes/training_3v3.tscn").instantiate()
	game.test_mode = true
	root.add_child(game)
	for _i in 5: await process_frame
	game.hud.menu.get_node("StartMatch").pressed.emit()
	for _i in 8: await physics_frame
	assert(game.services.rules.state==game.Rules.State.LIVE)
	game.training_mode.low_pressure = false
	var points := [Vector3(-10,.002,14),Vector3(0,.002,15),Vector3(10,.002,16),Vector3(-4,.002,-1),Vector3(-8,.002,-10),Vector3(2,.002,1.5)]
	assert(scenario in ["original","open_lane","short_diagonal","recycle_pocket"])
	if scenario=="open_lane":
		# A declared opposite-flank defensive opening, not frozen/slow opposition.
		points[1] = Vector3(6,.002,15)
	if scenario=="short_diagonal":
		# A short diagonal first leg and an advanced C, with wide live defenders.
		# Geometry only: all participants remain autonomous after the fixture.
		points = [Vector3(-10,.002,14),Vector3(6,.002,16),Vector3(10,.002,16),Vector3(-3,.002,-2),Vector3(-6,.002,-6),Vector3(-3,.002,2)]
	if scenario=="recycle_pocket":
		# A shorter natural first leg into the striker, with a nearby midfield link.
		# C can come back into a lateral pocket; no pass/role/ownership override.
		points = [Vector3(-10,.002,14),Vector3(6,.002,15),Vector3(10,.002,16),Vector3(-7,.002,-.5),Vector3(-7,.002,-7),Vector3(-4,.002,-1)]
	for id in game.players.size():
		var p: Node3D = game.players[id]
		p.position = points[id]
		p.velocity = Vector3.ZERO
		p.foot.cancel()
		p.action_cooldown = 0.0
		p.set_move_intent(Vector3.ZERO)
		if not p.is_human:
			p.pending_kick.clear()
			p.facing = Vector3.FORWARD if p.team==0 else Vector3.BACK
			p.body_facing = p.facing
			p.face_target = p.facing
			p.target = p.position
	# A must acquire a free front ball through the real shoe, not fixture ownership.
	game.ball.reset(game.players[A_ID].position+Vector3(.27,.11,.52))
	game.ball.velocity = Vector3.ZERO
	game.pass_receiver = null
	game.pass_receiver_timer = 0.0
	game.tactical_director.reset()
	game.tactics_bridge.clock = .20
	game.tactics_bridge.refresh_now()
	for p in game.players:
		p.refresh_pose(0)
		p.get_node("LowerBallContacts").update_from_skeleton(0.0)
	game.contact_hub.contact_resolved.connect(contact_record)
	# SPATIAL FIXTURE ENDS HERE. No subsequent product state/input writes.
	for _i in int(ceil(seconds*Engine.physics_ticks_per_second)):
		await physics_frame
		frame += 1
		var director: FootballTacticalDirector = game.tactical_director
		var active: Dictionary = director.third_man.duplicate(true)
		var last: Dictionary = director.third_man_last.duplicate(true)
		if frame%12==0: plans.append({"frame":frame,"active":active,"last":last,"receive":director.receive_plan.debug_snapshot()})
		if last.get("state","")=="COMPLETED" and not completed.any(func(r):return r.pass_id==last.pass_id):
			var proof := chain_proof(last)
			if not proof.is_empty(): completed.append(proof)
		for id in [3,4,5]:
			var p: Node3D = game.players[id]
			var offset: Vector3 = game.ball.position-p.position
			samples.append({"frame":frame,"id":id,"owner":game.players.find(game.ball.carrier),"actor":v(p.position),"ball":v(game.ball.position),"gap":Vector2(offset.x,offset.z).length(),"facing_dot":offset.normalized().dot(p.facing),"relative_speed":(game.ball.velocity-p.velocity).length(),"reason":p.tactical_intent.get("reason",""),"intent_action":p.tactical_intent.get("action",""),"pending":p.pending_kick.duplicate(true),"pending_age":p.pending_age,"foot":p.foot.kind,"phase":p.foot.phase,"hit":p.foot.hit,"failure":p.foot.contact_failure,"ready":game.ball.reception_ready(p)})
		if frame%24==0: decision_record()
	checks.append({"name":"A actual front-shoe acquisition","ok":contacts.any(func(e):return e.success and e.actor==A_ID and e.owner==A_ID and e.action in ["RECEIVE","STOP","SETTLE","PULL","CONTROL","CLOSE","TURN"] and e.shoe.get("valid",false))})
	checks.append({"name":"natural A real PASS","ok":contacts.any(func(e):return e.success and e.actor==A_ID and e.action=="PASS" and e.shoe.get("valid",false))})
	checks.append({"name":"natural third-person plan","ok":plans.any(func(r):return not r.active.is_empty())})
	checks.append({"name":"ordered real A-B-C contact chain","ok":not completed.is_empty()})
	var failed: int = checks.filter(func(c):return not c.ok).size()
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"scope":"Declared spatial fixture, all six active, unmodified roster/styles, natural planning only; completion requires three ordered real shoe contact identities","seconds":seconds,"scenario":scenario,"physics_ticks_per_second":Engine.physics_ticks_per_second,"initial_points":points,"initial_A":A_ID,"post_fixture_state_writes":false,"checks":checks,"failed":failed,"contacts":contacts,"plans":plans,"completed_chains":completed,"decision_gates":gates,"samples":samples},"\t"))
	game.pause_match()
	game.shutdown_audio()
	game.queue_free()
	game = null
	for _i in 4: await process_frame
	quit(0 if failed==0 else 1)
