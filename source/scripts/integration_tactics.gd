extends Node
## Data-only planner adaptation. At half-time rotate the snapshot by 180 degrees
## into the frozen planner's initial frame, then rotate its outputs back.
var game: Node
var ground_delivery:Array=[]
var loft_delivery:Array=[]
var aerial_delivery:Array=[]
func _build_delivery_table()->void:
	if not ground_delivery.is_empty():return
	var profile:FootballPhysicsProfile=game.physics_profile
	var delivery=preload("res://addons/football_ground_pass/ground_pass_solution.gd")
	for distance in range(2,37,2):
		var range_m:float=clampf(float(distance),profile.ground_pass_min_distance_m,profile.ground_pass_max_distance_m)
		var speed:float=delivery.launch_speed(range_m,profile)
		var fraction:float=(range_m-profile.ground_pass_min_distance_m)/maxf(.001,profile.ground_pass_max_distance_m-profile.ground_pass_min_distance_m)
		ground_delivery.append({"distance":float(distance),"speed":speed,"time":preload("res://addons/football_ground_pass/ground_pass_solution.gd").roll_time(float(distance),speed,profile),"power":pow(clampf(fraction,0,1),1.0/profile.ground_pass_distance_exponent)})

func _build_loft_table()->void:
	if not loft_delivery.is_empty():return
	var profile:FootballPhysicsProfile=game.physics_profile
	for power in [.45,.65,.82,1.0]:
		var angle:float=deg_to_rad(34.0)
		var speed:float=profile.loft_pass_speed(power)
		var position:Vector3=Vector3(0,game.ball.radius+.01,0)
		var velocity:Vector3=Vector3(0,sin(angle)*speed,-cos(angle)*speed)
		var spin:=Vector3.ZERO
		var time:float=0.0
		for i in range(160):
			var step:Dictionary=FootballBallForces.airborne_step(velocity,spin,.025,Vector3.ZERO,profile)
			position+=step.motion;velocity=step.velocity;spin=step.spin;time+=.025
			if position.y<=game.ball.radius and velocity.y<0:break
		loft_delivery.append({"power":power,"loft":34.0,"distance":absf(position.z),"time":time,"launch_speed":speed})
	aerial_delivery=loft_delivery.duplicate(true)
	# Long passing has a separate AI launch envelope, bounded by the existing
	# maximum deliberate kick speed. Tables use the same air forces as contact.
	for speed in [20.0,23.0,26.0,29.0,profile.loft_pass_max_speed_mps]:
		var angle:float=deg_to_rad(34.0)
		var position:Vector3=Vector3(0,game.ball.radius+.01,0)
		var velocity:Vector3=Vector3(0,sin(angle)*speed,-cos(angle)*speed)
		var spin:Vector3=Vector3.ZERO
		var time:float=0.0
		for i in 200:
			var step:Dictionary=FootballBallForces.airborne_step(velocity,spin,.025,Vector3.ZERO,profile)
			position+=step.motion;velocity=step.velocity;spin=step.spin;time+=.025
			if position.y<=game.ball.radius and velocity.y<0:break
		aerial_delivery.append({"power":1.0,"loft":34.0,"distance":absf(position.z),"time":time,"launch_speed":speed})

	aerial_delivery.sort_custom(func(a,b):return float(a.distance)<float(b.distance))
	# Reserve a controllable post-bounce window rather than the first turf impact.
	# Existing keeper loft table remains unchanged; only team-plan passes use this.
	for entry:Dictionary in aerial_delivery:
		var speed:float=float(entry.get("launch_speed",profile.loft_pass_speed(float(entry.power))))
		var angle:float=deg_to_rad(float(entry.loft))
		var pos:Vector3=Vector3(0,game.ball.radius+.01,0)
		var vel:Vector3=Vector3(0,sin(angle)*speed,-cos(angle)*speed)
		var spin:Vector3=Vector3.ZERO
		var landed:bool=false
		for i in 480:
			var supported:bool=pos.y<=profile.ball_radius_m+.012 and vel.y<=.10
			var step:Dictionary=FootballBallForces.rolling_step(vel,spin,Vector3.UP,.0125,Vector3.ZERO,profile) if supported else FootballBallForces.airborne_step(vel,spin,.0125,Vector3.ZERO,profile)
			pos+=step.motion;vel=step.velocity;spin=step.spin
			if pos.y<profile.ball_radius_m:
				landed=true;pos.y=profile.ball_radius_m
				var bounce:Dictionary=preload("res://addons/football_physics/contact_math.gd").sphere_response(vel,spin,Vector3.ZERO,Vector3.UP,0.0,profile.turf_restitution if -vel.y>profile.low_bounce_cutoff_mps else 0.0,profile.bounce_friction_coefficient,profile,false)
				vel=bounce.velocity;spin=bounce.spin
				if vel.y<=profile.rest_speed_mps:vel.y=0
			if landed and pos.y<=.42 and vel.length()<=11.0:
				entry.receive_distance=absf(pos.z);entry.receive_time=(i+1)*.0125
				break
		if not entry.has("receive_distance"):entry.receive_distance=INF;entry.receive_time=INF
	aerial_delivery.sort_custom(func(a,b):return float(a.receive_distance)<float(b.receive_distance))

# Successful offers only: the same planned pass cannot rebook after expiry.
var receive_continuations_sent: Dictionary = {}
const ReceiveMotion=preload("res://scripts/tactics/receive_motion.gd")
var receive_motion_at:=-1.0
var clock := 0.0
var decision_elapsed := 0.0
var contact_refresh_requested := false
var last_refresh_frame := -1
var refresh_count := 0
var receive_probes:Dictionary={}
var receive_timings:Array[Dictionary]=[]
var coalesced_refreshes := 0
var observation: Dictionary = {}
var team_observation: Dictionary = {}
var ai_restart_age := 0.0
var restart_offers:Dictionary={}
var restart_offer_taker:int=-1
var restart_trace_at:float=0.0
var restart_trace:Array[Dictionary]=[]
var restart_kick_setup: Dictionary = {}
var restart_walk_clock := 0.0
var restart_walk_serial := -1
var restart_waypoints := {}
const LocalStandingTackle := preload("res://scripts/tactics/local_tackle_window.gd")
var local_standing_tackle = LocalStandingTackle.new()

func _ready() -> void:
	name = "TacticalPlanning"
	process_physics_priority = -45
	# Static profile tables caused a one-off first-live planning spike. Build before
	# play; these exact tables were already cached for the rest of each session.
	call_deferred("_warm_delivery_tables")

func _warm_delivery_tables()->void:
	var began:int=Time.get_ticks_usec()
	_build_delivery_table()
	_build_loft_table()
	set_meta("delivery_warm_usec",Time.get_ticks_usec()-began)

func _physics_process(delta: float) -> void:
	if not _dir_ctx.is_empty() and (game.phase!=game.Phase.PLAY or not game.ai_enabled or game.services.rules.state!=game.Rules.State.LIVE):
		_complete_director_stages(false) # keep director state consistent; intents discarded like a dropped snapshot
	if game.phase==game.Phase.PAUSED:
		_staged_snapshot.clear()
		local_standing_tackle.clear()
		return
	if game.phase in [game.Phase.MENU,game.Phase.FINISHED] or not game.ai_enabled:
		_staged_snapshot.clear()
		local_standing_tackle.clear()
		game.tactical_director.cancel_tactical_tasks("inactive")
		return
	if game.services.rules.state!=game.Rules.State.LIVE:
		_staged_snapshot.clear()
		local_standing_tackle.clear()
		_dead_ball(delta)
		return
	ai_restart_age = 0
	local_standing_tackle.elapse(delta)
	decision_elapsed += delta
	clock -= delta
	if contact_refresh_requested and decision_elapsed>=.075:
		# Contact-driven refresh stays synchronous (responsiveness over cost).
		clock = REFRESH_INTERVAL_S
		var step := decision_elapsed
		decision_elapsed = 0
		contact_refresh_requested = false
		_staged_snapshot.clear()
		SpikeWatch.tactics_kind="contact"
		_complete_director_stages(true)
		if CONTACT_STAGING_ENABLED and pipeline_enabled and DIRECTOR_STAGING_ENABLED and game.phase==game.Phase.PLAY:
			# R004: contact snapshot is taken now; director phases follow on the next ticks.
			var began:int=Time.get_ticks_usec()
			_staged_snapshot=_build_snapshot()
			_staged_snapshot.step=step
			SpikeWatch.tactics_us+=Time.get_ticks_usec()-began
		else:
			refresh_now(step)
	elif not _dir_ctx.is_empty():
		# R004 stages 3..5: one director phase per physics tick.
		var began:int=Time.get_ticks_usec()
		SpikeWatch.tactics_kind="stage%d"%(_dir_stage+1)
		_advance_director_stage()
		SpikeWatch.tactics_us+=Time.get_ticks_usec()-began
	elif not _staged_snapshot.is_empty():
		# R004 stage 2: director + intent apply one tick after the snapshot build.
		SpikeWatch.tactics_kind="director"
		refresh_now(float(_staged_snapshot.step),true)
	elif clock<=0:
		clock = REFRESH_INTERVAL_S
		var step := decision_elapsed
		decision_elapsed = 0
		if pipeline_enabled and game.phase==game.Phase.PLAY and game.ai_enabled:
			# R004 stage 1: snapshot only; spreads one ~8 ms refresh over two ticks.
			var began:int=Time.get_ticks_usec()
			SpikeWatch.tactics_kind="snapshot"
			_staged_snapshot=_build_snapshot()
			_staged_snapshot.step=step
			SpikeWatch.tactics_us+=Time.get_ticks_usec()-began
		else:
			refresh_now(step)
	elif not game.tactical_director.receive_plan.active.is_empty() and game.tactical_director.clock+decision_elapsed-receive_motion_at>=.095:
		SpikeWatch.tactics_kind="receive_motion"
		_refresh_receive_motion()
	local_standing_tackle.try_due(game)

func canonical(v: Vector3) -> Vector3:
	return Vector3(-v.x,v.y,-v.z) if game.attack_direction(0)>0 else v

const SpikeWatch:=preload("res://scripts/frame_spike_watch.gd")
func refresh_now(delta := .20, use_staged:bool=false) -> void:
	var frame:int=Engine.get_physics_frames()
	if frame==last_refresh_frame:
		_staged_snapshot.clear()
		contact_refresh_requested=true
		coalesced_refreshes+=1
		return
	last_refresh_frame=frame
	refresh_count+=1
	var began:int=Time.get_ticks_usec()
	_refresh_now_impl(delta,use_staged)
	SpikeWatch.tactics_us+=Time.get_ticks_usec()-began
## R004 scheduling (tunable). 0.20 s = original 5 Hz; 0.10 s = 10 Hz.
const REFRESH_INTERVAL_S := 0.20
const PIPELINE_ENABLED := true
var pipeline_enabled := PIPELINE_ENABLED # Headless A/B only; normal entry retains default.
## R004: spread director.tick over ticks (begin -> team 0 -> team 1 -> finish+apply).
## false = old single director.tick call on the tick after the snapshot.
const DIRECTOR_STAGING_ENABLED := true
## R004: contact-triggered refreshes also use the staged path (+4 ticks, ~33 ms latency).
## false = old synchronous contact refresh (one ~8 ms tick).
const CONTACT_STAGING_ENABLED := true
var _staged_snapshot: Dictionary = {}
var _dir_ctx: Dictionary = {}
var _dir_stage := 0
var _dir_actors: Array[Dictionary] = []
var _dir_snapshot: Dictionary = {}
var staged_director_ticks := 0

func _advance_director_stage() -> void:
	var t:int=Time.get_ticks_usec()
	if _dir_stage<2:
		game.tactical_director.tick_team(_dir_ctx,_dir_stage)
		_dir_stage+=1
		SpikeWatch.seg_director_us+=Time.get_ticks_usec()-t
		return
	observation=game.tactical_director.tick_finish(_dir_ctx)
	SpikeWatch.seg_director_us+=Time.get_ticks_usec()-t
	_dir_ctx={}
	staged_director_ticks+=1
	_apply_director(_dir_actors,_dir_snapshot)

## Finishes an in-flight staged director tick now, so a contact/external refresh never
## interleaves with it (director clock/state advance exactly once per tick).
func _complete_director_stages(apply:bool) -> void:
	if _dir_ctx.is_empty():return
	var t:int=Time.get_ticks_usec()
	while _dir_stage<2:
		game.tactical_director.tick_team(_dir_ctx,_dir_stage)
		_dir_stage+=1
	var result:Dictionary=game.tactical_director.tick_finish(_dir_ctx)
	SpikeWatch.seg_director_us+=Time.get_ticks_usec()-t
	_dir_ctx={}
	staged_director_ticks+=1
	if apply:
		observation=result
		_apply_director(_dir_actors,_dir_snapshot)

func _refresh_now_impl(delta:float,use_staged:bool=false) -> void:
	if game.phase!=game.Phase.PLAY or not game.ai_enabled:
		_staged_snapshot.clear()
		return
	_complete_director_stages(true)
	var from_pipeline:=use_staged and _staged_valid()
	var staged:Dictionary=_staged_snapshot if from_pipeline else _build_snapshot()
	_staged_snapshot={}
	var actors: Array[Dictionary] = staged.actors
	var snapshot: Dictionary = staged.snapshot
	if DIRECTOR_STAGING_ENABLED and from_pipeline:
		var t:int=Time.get_ticks_usec()
		var ctx:Dictionary=game.tactical_director.tick_begin(snapshot,delta)
		SpikeWatch.seg_director_us+=Time.get_ticks_usec()-t
		if ctx.has("result"):
			observation=ctx.result
			_apply_director(actors,snapshot)
			return
		_dir_ctx=ctx;_dir_stage=0;_dir_actors=actors;_dir_snapshot=snapshot
		return
	_run_director(actors,snapshot,delta)

func _staged_valid()->bool:
	if _staged_snapshot.is_empty() or contact_refresh_requested:return false
	if int(_staged_snapshot.get("generation",-1))!=game.match_generation:return false
	if Engine.get_physics_frames()-int(_staged_snapshot.get("frame",-10))>2:return false
	if _staged_snapshot.get("attack",0)!=game.attack_direction(0):return false
	var old:Dictionary=_staged_snapshot.snapshot
	var owner:int=game.players.find(game.ball.carrier) if is_instance_valid(game.ball.carrier) else -1
	if int(old.carrier_id)!=owner:return false
	var dt:float=float(Engine.get_physics_frames()-int(_staged_snapshot.frame))/Engine.physics_ticks_per_second
	return canonical(game.ball.position).distance_to(old.ball_position+old.ball_velocity*dt)<.35 and canonical(game.ball.velocity).distance_to(old.ball_velocity)<.75

func _build_snapshot() -> Dictionary:
	var _t0:int=Time.get_ticks_usec()
	var actors: Array[Dictionary] = []
	for i in range(game.players.size()):
		var actor: Node3D = game.players[i]
		actors.append({"id":i,"team":actor.team,"position":canonical(actor.position),"velocity":canonical(actor.velocity),"facing":canonical(actor.facing),"shielding":actor.shielding,"human":actor.is_human,"goalkeeper":actor.is_goalkeeper,"active":actor.visible,"can_kick":game.ball.can_kick(actor),"kick_setup_blocked":not actor.is_human and actor.kick_retry_at>game.tactical_director.clock if actor is FootballAgent else false,"kick_ready":actor.action_cooldown<=0,"tackle_ready":actor.tackle_cooldown<=0,"foot_idle":actor.foot.idle(),"foot_action":actor.foot.kind,"foot_hit":actor.foot.hit,"stamina":actor.get("stamina") if actor.get("stamina")!=null else 100.0,"sprint_locked":actor.get("sprint_locked")==true,"foot_cap":actor.foot.movement_cap(),"can_reach":actor.position.distance_squared_to(game.ball.position)<9.0 and game.can_reach_ball(actor)})
	for i in range(actors.size()):
		var actor=game.players[i]
		actors[i].merge(preload("res://scripts/player_abilities.gd").observation(actor))
		actors[i].can_pass=game.ball.can_pass(actor)
		actors[i].visible_weight_cue=canonical(actor.dribble_balance.cue)
		actors[i].ball_offset=canonical(game.ball.position-actor.position)
		actors[i].reaction_delay=AiAwareness.reaction_delay(float(actors[i].get("ability_touch",1.0))) # R004
		actors[i].ball_relative_speed=(game.ball.velocity-actor.velocity).length()
		actors[i].ball_velocity=canonical(game.ball.velocity)
		actors[i].brake_deceleration=preload("res://scripts/movement_inertia.gd").braking_rate(actor.profile)
		actors[i].motor_profile=actor.profile
		actors[i].carry_heading=canonical(actor.ai_carry_aim) if actor is FootballAgent and actor.ai_carry_aim.length_squared()>.1 else actors[i].facing
		actors[i].cut_ready=actor is FootballAgent and actor.ai_cut_cooldown<=0 and actor.pending_kick.is_empty() and actor.foot.can_schedule_kick() and not actor.foot.has_buffer() and (actor.foot.idle() or actor.foot.continuous_control() or actor.foot.phase==actor.foot.Phase.RECOVER)
	var snapshot := {"players":actors,"field_half_width":game.field_half_width,"field_half_length":game.field_half_length,"goal_half_width":game.goal_width*.5,"ball_position":canonical(game.ball.position),"ball_velocity":canonical(game.ball.velocity),"carrier_id":game.players.find(game.ball.carrier) if is_instance_valid(game.ball.carrier) else -1,"receiver_id":game.players.find(game.pass_receiver) if is_instance_valid(game.pass_receiver) else -1,"receiver_time":game.pass_receiver_timer,"possession_age":game.ball.possession_age,"last_touch_team":game.ball.last_touch_team,"call_id":0 if game.call_timer>0 else -1,"capabilities":{"reaction_delay":.16,"standoff":1.4,"exposed_gap":.90,"tackle_reach":game.tuning.tackle_reach,"receive_reach":.90,"ground_receive_height":.42,"safe_receive_speed":14,"receive_speed":game.tuning.running_move_speed,"run_acceleration":game.physics_profile.start_acceleration_mps2,"brake_deceleration":game.physics_profile.brake_deceleration_mps2,"turn_speed":5.8,"roll_deceleration":game.physics_profile.roll_deceleration_mps2,"gravity":game.physics_profile.gravity_mps2}}
	_build_delivery_table()
	snapshot.ground_delivery=ground_delivery
	_build_loft_table()
	snapshot.loft_delivery=loft_delivery
	snapshot.aerial_delivery=aerial_delivery
	if not is_instance_valid(game.ball.carrier) and not game.ball.held:
		snapshot.roll_samples=ReceiveMotion.ball_samples(canonical(game.ball.position),canonical(game.ball.velocity),canonical(game.ball.spin_rads),game.physics_profile)
	snapshot.motor_profile=game.physics_profile
	snapshot.movement_cfg=game.tuning
	snapshot.physics_frame=Engine.get_physics_frames()
	snapshot.ball_held=game.ball.held
	var keeper_host:Node=game.ball.get("keeper_host")
	snapshot.hand_owner_id=game.players.find(keeper_host.hand_owner) if is_instance_valid(keeper_host) and is_instance_valid(keeper_host.hand_owner) else -1
	snapshot.control_hint_id=-1
	# A recent dribbler may finish one free-roll touch; this is only a team-role hint.
	# Actual carrier/contact permissions are never invented or retained here.
	var previous:Node3D=game.ball.previous_carrier
	if not is_instance_valid(game.ball.carrier) and not game.ball.held and is_instance_valid(previous) and game.ball.last_contact_actor==previous and game.ball.touch_age<.55 and previous.position.distance_squared_to(game.ball.position)<4.0 and game.ball.position.y<.50 and game.ball.control_mode in ["LOOSE","PUSH"] and previous.foot.kind not in ["PASS","SHOT"]:
		snapshot.control_hint_id=game.players.find(previous)
	snapshot.small_sided = game.training_configuration!=null
	snapshot.tactical_scale = clampf(game.field_half_length/52.5,.40,1.0)
	SpikeWatch.seg_snapshot_us+=Time.get_ticks_usec()-_t0
	return {"actors":actors,"snapshot":snapshot,"generation":game.match_generation,"frame":Engine.get_physics_frames(),"attack":game.attack_direction(0)}

func _run_director(actors:Array[Dictionary],snapshot:Dictionary,delta:float) -> void:
	var _t1:int=Time.get_ticks_usec()
	observation = game.tactical_director.tick(snapshot,delta)
	SpikeWatch.seg_director_us+=Time.get_ticks_usec()-_t1
	_apply_director(actors,snapshot)

func _apply_director(actors:Array[Dictionary],snapshot:Dictionary) -> void:
	receive_motion_at=game.tactical_director.clock
	team_observation = observation.get("teams",{})
	_refresh_standing_tackle_observation(snapshot)
	for team in [0,1]:
		var id := int(team_observation.get(team,{}).get("presser_id",-1))
		game.chasers[team] = game.players[id] if id>=0 else null
	for id in observation.get("intents",{}):
		var actor: Node3D = game.players[int(id)]
		var intent: Dictionary = observation.intents[id].duplicate(true)
		for key in ["move_target","face_direction","aim_point","receive_offset","space_target","space_origin"]:
			if intent.has(key): intent[key] = canonical(intent[key])
		if intent.has("receive_plan"):
			for key in ["receive_point","approach_point","face_direction","live_ball_position","live_ball_velocity","next_direction","next_target","first_touch_direction","first_touch_target"]:
				if intent.receive_plan.has(key): intent.receive_plan[key] = canonical(intent.receive_plan[key])
		if intent.has("give_go_plan"):
			for key in ["runner_start","runner_goal","return_target","return_direction","wall_setup_target"]:
				if intent.give_go_plan.has(key): intent.give_go_plan[key] = canonical(intent.give_go_plan[key])
		if intent.has("third_man_plan"):
			for key in ["runner_target"]:
				if intent.third_man_plan.has(key): intent.third_man_plan[key] = canonical(intent.third_man_plan[key])
		if actor.is_human: continue
		# Apply in the live world frame before targets, pace and action dispatch.
		if is_instance_valid(game.training_mode):
			intent = game.training_mode.adapt_intent(actor,intent)
		if actor.pending_kick.has("give_go_pass_id") and (actor.pending_kick.give_go_pass_id!=intent.get("give_go_plan",{}).get("pass_id","") or intent.get("give_go_plan",{}).get("command","")!="RETURN"):
			actor.pending_kick.clear() # Cancel only the uncommitted planned return.
		if actor.pending_kick.has("third_man_pass_id") and (actor.pending_kick.third_man_pass_id!=intent.get("third_man_plan",{}).get("pass_id","") or intent.get("third_man_plan",{}).get("state","")!="CONTROLLED" or not intent.get("third_man_plan",{}).get("receiver_onside_now",true)):
			actor.pending_kick.clear() # Only a still-uncommitted planned second pass.
		if actor.pending_kick.has("plan_kick_id") and actor.pending_kick.plan_kick_id!=intent.get("shared_plan_id",-1):
			actor.pending_kick.clear() # Only an uncommitted kick; actual contact remains authoritative.
		if intent.get("primary_action","")=="RECEIVE": actor.pending_kick.clear()
		if actor.is_goalkeeper and is_instance_valid(game.ball.keeper_host) and game.ball.keeper_host.reserve_slow_capture(actor):
			intent.action="NONE";intent.press=false;intent.receive=false;intent.pace=0.0;intent.move_target=actor.position
			intent.reason="keeper_hand_priority";intent.primary_action="KEEPER_HANDS";intent.erase("receive_plan");actor.pending_kick.clear()
		if actor.foot.kind in ["PASS","SHOT"] and actor.foot.phase in [actor.foot.Phase.PREPARE,actor.foot.Phase.CONTACT]:
			intent.action=actor.foot.kind;intent.primary_action=actor.foot.kind
			intent.intent_owner="committed_contact";intent.receive=false;intent.press=false;intent.shield=false;intent.close_control=false
			intent.erase("receive_plan")
			intent.face_direction=actor.foot.direction
			intent.move_target=game.ball.position-actor.foot.direction*.44
		var buffered_cut:bool=actor.foot.buffer.get("kind","")=="CUT"
		var preparing_cut:bool=actor.foot.touch_plan.has("cut_style") and actor.foot.phase==actor.foot.Phase.PREPARE and not actor.foot.hit
		if (buffered_cut or preparing_cut) and game.ball.carrier==actor:
			var opposition:Array[Dictionary]=[]
			for row in actors:
				if row.team!=actor.team:opposition.append(row)
			var cut_direction:Vector3=actor.foot.buffer.direction if buffered_cut else actor.foot.direction
			var cut_route:Dictionary=preload("res://scripts/tactics/pressure_route.gd").inspect(actors[id],actors[id].position+canonical(cut_direction)*4.0,opposition,5.0,true)
			if float(cut_route.immediate)<.80 or intent.action in ["PASS","SHOT","CROSS","CUTBACK"]:
				if buffered_cut:actor.foot.clear_buffer("ai_cut_exit_closed")
				elif preparing_cut:actor.foot.cancel("ai_cut_exit_closed")
				actor.ai_cut_cooldown=maxf(actor.ai_cut_cooldown,.25)
		if actor.foot.touch_plan.has("cut_style") and actor.foot.phase in [actor.foot.Phase.PREPARE,actor.foot.Phase.CONTACT] and game.ball.carrier==actor:
			intent.action="NONE";intent.move_target=actor.target;intent.face_direction=actor.face_target
			intent.pace=minf(float(intent.pace),2.8);intent.receive=false;intent.press=false
			intent.intent_owner="committed_cut";intent.erase("receive_plan")
		actor.tactical_intent = intent
		local_standing_tackle.grant(actor,intent,int(team_observation.get(actor.team,{}).get("presser_id",-1)),int(id))
		actor.target = intent.move_target
		actor.face_target = intent.face_direction
		actor.tactical_pace = float(intent.pace)
		actor.shielding = intent.shield
		actor.close_control = bool(intent.get("close_control",false))
		if intent.get("carry_cut",false) and intent.action=="NONE" and game.ball.carrier==actor and actor.pending_kick.is_empty() and actor.ai_cut_cooldown<=0 and (actor.foot.idle() or actor.foot.continuous_control() or actor.foot.phase==actor.foot.Phase.RECOVER):
			var cut_axis:Vector3=intent.move_target-actor.position;cut_axis.y=0
			# The same selected exit drives the shoe and subsequent body travel.
			if cut_axis.length_squared()>.04 and actor.foot.request_cut(cut_axis.normalized()):
				actor.ai_cut_cooldown=.90
				intent.pace=minf(float(intent.pace),2.8)
				intent.close_control=false;intent.shield=false
				actor.tactical_pace=intent.pace;actor.close_control=false;actor.shielding=false
				intent.reason="cut_committed_to_exit"
				if game.tactical_director.carry_routes.has(int(id)):game.tactical_director.carry_routes[int(id)]["cut_requested_at"]=game.tactical_director.clock
		if _dispatch_receive_continuation(actor,intent): continue
		var action := String(intent.action)
		if action=="NONE" and actor.pending_age>.35 and actor.foot.kind not in ["PASS","SHOT"] and intent.get("reason","") not in ["confirm_control_then_turn","receive_follow_through"]:actor.pending_kick.clear()
		if action=="TACKLE":
			pass # The authorized local standing window uses the same stamped sample.
		elif action in ["PASS","SHOT","CROSS","CUTBACK","CLEARANCE"] and actor.foot.kind not in ["PASS","SHOT"] and actor.action_cooldown<=0 and actor.kick_retry_at<=game.tactical_director.clock:
			var aim: Vector3 = intent.aim_point-game.ball.position
			aim.y = 0
			if aim.length()<.1: continue
			var semantic := {"action":"shoot_curve" if action=="SHOT" and intent.spin.length()>.01 else "shoot_straight" if action=="SHOT" else "pass_spin" if intent.spin.length()>.01 else "pass_high" if float(intent.loft_deg)>1 else "pass_ground","direction":aim.normalized(),"power":float(intent.power01),"elevation_deg":float(intent.loft_deg),"spin":intent.spin,"receiver_id":int(intent.receiver_id),"tactical_action":action}
			if action=="PASS" and semantic.action=="pass_ground" and int(intent.receiver_id)>=0 and not intent.has("space_target"):
				var recipient:Node3D=game.players[int(intent.receiver_id)]
				# The real contact solver supplies velocity lead once. Do not feed its
				# predicted endpoint back as an additional directional lead offset.
				var base:Vector3=recipient.position-game.ball.position;base.y=0
				if base.length()>.1:semantic.direction=base.normalized()
			if intent.has("plan_kick_id"):semantic.plan_kick_id=intent.plan_kick_id
			if intent.has("ai_loft_speed"):semantic.ai_loft_speed=intent.ai_loft_speed
			if intent.has("space_target"):
				semantic.space_target=intent.space_target
				semantic.space_origin=intent.space_origin
				semantic.space_valid_until=intent.space_valid_until
			if intent.has("give_go_plan"): semantic.give_go_pass_id = intent.give_go_plan.pass_id
			if intent.has("third_man_plan"): semantic.third_man_pass_id = intent.third_man_plan.pass_id
			if actor.pending_kick.is_empty() or actor.pending_kick.get("receiver_id",-1)!=semantic.receiver_id or actor.pending_kick.action!=semantic.action:actor.pending_age=0
			actor.pending_kick = semantic
			actor.face_target = aim.normalized()
			actor.target = game.ball.position+Vector3(game.ball.velocity.x,0,game.ball.velocity.z)*.20-semantic.direction*.44

func _refresh_standing_tackle_observation(snapshot: Dictionary) -> void:
	# Capture once from the EXISTING 5 Hz snapshot, after tactical decisions.
	# Do not refresh this sample from the 13 Hz local checks.
	var owner_slot: int = int(snapshot.get("carrier_id",-1))
	if owner_slot<0 or owner_slot>=game.players.size():
		local_standing_tackle.sample.clear()
		local_standing_tackle.slots.clear()
		return
	var owner: Node3D = game.players[owner_slot]
	var row: Dictionary = snapshot.players[owner_slot]
	var world_ball: Vector3 = canonical(snapshot.ball_position)
	var shoe_gap := -1.0
	# Existing sampled final-IK shoe feedback: no new skeleton solve/query.
	if owner.foot.kind!="" and bool(owner.foot.actual_contact.get("valid",false)):
		var shoe: Vector3 = owner.foot.toe_world
		if shoe.is_finite(): shoe_gap = maxf(0.0,shoe.distance_to(world_ball)-game.ball.radius)
	local_standing_tackle.begin_observation({"position":world_ball,"velocity":canonical(snapshot.ball_velocity),"owner_position":canonical(row.position),"owner_velocity":canonical(row.velocity),"owner_team":int(row.team),"owner_id":owner.get_instance_id(),"owner_slot":owner_slot,"owner_shoe_gap_m":shoe_gap,"generation":game.match_generation,"ball_id":game.ball.get_instance_id()})

func _dead_ball(delta: float) -> void:
	receive_continuations_sent.clear()
	decision_elapsed = 0
	contact_refresh_requested = false
	# Cancellation is a transition, not a full planner reset 120 times per second.
	var rules: FBMatchRulesEngine = game.services.rules
	var restart: Dictionary = rules.restart
	restart_walk_clock += delta
	var walk_serial: int = game.match_generation*100000+int(restart.get("serial",-1))
	if walk_serial!=restart_walk_serial:
		game.tactical_director.cancel_tactical_tasks("dead_ball")
		restart_offer_taker=-1
		restart_walk_serial = walk_serial
		restart_waypoints.clear()
		restart_kick_setup.clear()
		restart_offers.clear()
	if int(restart.get("taker_id",-1))!=restart_offer_taker:
		restart_offer_taker=int(restart.get("taker_id",-1))
		restart_waypoints.clear()
		restart_kick_setup.clear()
		restart_offers=_restart_offer_targets(restart)
	_trace_restart(rules,restart)
	for actor in game.agents:
		if not actor.visible: continue
		actor.pending_kick.clear()
		actor.shielding = false
		actor.tactical_intent = {"reason":"restart_position","press":false,"receive":false}
		actor.tactical_pace = 6.2
		if rules.state in [game.Rules.State.RESTART_SETUP,game.Rules.State.RESTART_READY]:
			var desired: Vector3 = restart_offers.get(actor.get_instance_id(),actor.position)
			if actor.get_instance_id()==int(restart.get("taker_id",-1)): desired = restart_kick_setup.get("point",restart.taker_target)
			else:
				if restart.get("kind", "")=="kickoff":
					desired = _kickoff_shape_target(actor, game.attack_direction(actor.team))
				var proposed := desired
				desired = game.services.constrain_restart_position({"id":actor.get_instance_id(),"team":actor.team},desired)
				var clearance := Vector3(desired.x-proposed.x,0,desired.z-proposed.z)
				if clearance.length()>.025: desired += clearance.normalized()*.65
			if actor.get_instance_id()==int(restart.get("taker_id",-1)) and not restart_kick_setup.is_empty():
				actor.target = _restart_taker_walk_target(actor,desired,restart.point)
			else: actor.target = _restart_walk_target(actor,desired)
			if actor.get_instance_id()==int(restart.get("taker_id",-1)):
				if actor.foot.kind in ["PASS","SHOT"] and not actor.foot.idle():actor.target=actor.position
				actor.tactical_pace = _restart_taker_pace(actor,actor.target,restart.point)
			actor.face_target = restart_kick_setup.get("direction",restart.get("inward",Vector3.FORWARD)) if actor.get_instance_id()==int(restart.get("taker_id",-1)) else Vector3(game.ball.position.x-actor.position.x,0,game.ball.position.z-actor.position.z).normalized()
		elif rules.state in [game.Rules.State.GOAL_CELEBRATION,game.Rules.State.HALF_TIME]:
			var target: Vector3 = actor.position
			var attack: float = game.attack_direction(actor.team)
			# Walk toward the next half during the interval. Rule signs flip once.
			if rules.state == game.Rules.State.HALF_TIME: attack = -attack
			target = _kickoff_shape_target(actor, attack)
			actor.target = _restart_walk_target(actor,target)
			actor.face_target = Vector3(0,0,attack)
		else: actor.target = actor.position
	if rules.state!=game.Rules.State.RESTART_READY:
		ai_restart_age = 0
		return
	ai_restart_age += delta
	var taker: Node3D = game.actor_by_instance(int(restart.get("taker_id",-1)))
	if not is_instance_valid(taker) or taker.is_human or not taker.foot.idle() or ai_restart_age<.4 or game.throw_requests.has(taker.get_instance_id()): return
	# AI waits for a usable formation while the referee remains READY.
	# Human input/view stay active; this never changes the legal restart gate.
	if restart.kind=="kickoff" and ai_restart_age<1.2 and not _kickoff_shape_ready(taker): return
	var direction: Vector3 = restart.inward
	var receiver: Node3D
	var best := INF
	for other in game.players:
		if other==taker or other.team!=taker.team or not other.visible: continue
		var offset := Vector3(other.position.x-restart.point.x,0,other.position.z-restart.point.z)
		var distance := offset.length()
		if distance<3 or distance>32: continue
		if restart.kind=="throw_in" and offset.normalized().dot(direction)<.10: continue
		if distance<best:
			best = distance
			receiver = other
	if is_instance_valid(receiver): direction = (receiver.position-restart.point).normalized()
	if not restart_kick_setup.is_empty():
		direction = restart_kick_setup.direction
		receiver = restart_kick_setup.get("receiver",null)
	if is_instance_valid(receiver):best=game.flat_distance(receiver.position,restart.point)
	direction.y = 0
	var penalty: bool = restart.kind=="penalty"
	if penalty: direction = (game.target_goal(taker.team)-restart.point+Vector3(1.5,0,0)).normalized()
	var intent := {"action":"shoot_straight" if penalty else "pass_ground","direction":direction.normalized(),"power":.68 if penalty else clampf((best*.65-3.5)/13.5,.25,.85) if best<INF else .5,"elevation_deg":3.0 if penalty else 0.0,"spin":Vector3.ZERO}
	if not penalty and best<INF and restart.kind!="throw_in":
		var profile:FootballPhysicsProfile=game.physics_profile
		var speed:float=preload("res://addons/football_ground_pass/ground_pass_solution.gd").launch_speed(best,profile)
		intent.power=preload("res://addons/football_ground_pass/ground_pass_solution.gd").power_for_distance(best,profile)
	taker.face_target = direction
	# The referee's staging target is behind its default inward direction.
	# A backward/sideways kickoff needs a legal physical step around the ball;
	# turning in place left the ball behind the new facing and stalled READY.
	if restart.kind not in ["throw_in","dropped_ball"]:
		# Motor stops within .18 m. Keep staged gap + stop radius below
		# the unchanged .58 m request gate; body sweeps remain authoritative.
		var kick_point: Vector3 = restart.point-direction.normalized()*.44
		restart_kick_setup = {"point":kick_point,"direction":direction,"receiver":receiver}
		taker.target = _restart_taker_walk_target(taker,kick_point,restart.point)
		taker.tactical_pace = _restart_taker_pace(taker,taker.target,restart.point)
	# The restart is performed by the same contact action, never by READY's timer.
	if restart.kind=="dropped_ball":
		game.services.request_restart(taker.get_instance_id(),direction,1,0)
	elif taker.facing.dot(direction)>.94:
		if restart.kind!="throw_in":
			# Arrive behind the chosen pass before beginning the real foot action.
			# Passing while crossing the ball put it inside the taker's body and
			# immediately caused an authoritative restart-double-touch foul.
			var ball_offset := Vector3(game.ball.position.x-taker.position.x,0,game.ball.position.z-taker.position.z)
			if game.flat_distance(taker.position,restart_kick_setup.point)>.24: return
			if ball_offset.length()<.24 or ball_offset.length()>=.72: return
			if ball_offset.normalized().dot(direction)<.90: return
			if Vector2(taker.velocity.x,taker.velocity.z).length()>.75: return
		game.request_actor_kick(taker,intent,receiver)

func _restart_taker_walk_target(actor: Node3D, desired: Vector3, ball_point: Vector3) -> Vector3:
	var radial := Vector3(actor.position.x-ball_point.x,0,actor.position.z-ball_point.z)
	var goal_radial := Vector3(desired.x-ball_point.x,0,desired.z-ball_point.z)
	if radial.length()<.10 and goal_radial.length()>.05:
		return _restart_walk_target(actor,ball_point+goal_radial.normalized()*.80)
	if radial.length()>.05 and radial.length()<1.1 and goal_radial.length()>.05:
		var turn := radial.signed_angle_to(goal_radial,Vector3.UP)
		if absf(turn)>.35:
			# Short deterministic arc segments keep the body clear of the held
			# ball when a backward/sideways pass changes the staging direction.
			var arc := radial.normalized().rotated(Vector3.UP,signf(turn)*minf(.8,absf(turn)))*.80
			return _restart_walk_target(actor,ball_point+arc)
		if radial.length()<.24:
			# If already too close, first step away on the selected rear side.
			return _restart_walk_target(actor,ball_point+goal_radial.normalized()*.80)
	return _restart_walk_target(actor,desired)

func _restart_taker_pace(actor: Node3D, target: Vector3, ball_point: Vector3) -> float:
	var gap: float = game.flat_distance(actor.position,target)
	var circling: bool = game.flat_distance(actor.position,ball_point)>.6 and game.flat_distance(target,ball_point)>.7
	# The agent also eases within .8 m of each waypoint. Preserve a usable
	# walking pace on the arc, then ease down for the final stationary kick.
	return minf(6.2,maxf(2.4 if circling else 1.1,gap*2.2))

func _restart_walk_target(actor: Node3D, desired: Vector3) -> Vector3:
	var id := actor.get_instance_id()
	if restart_waypoints.has(id):
		var route: Dictionary = restart_waypoints[id]
		if game.flat_distance(actor.position,route.point)>.25 and restart_walk_clock<float(route.until): return route.point
		restart_waypoints.erase(id)
	var toward := Vector3(desired.x-actor.position.x,0,desired.z-actor.position.z)
	if toward.length()<.18: return desired
	var axis := toward.normalized()
	# Legal stationary players can physically block an opponent returning to
	# its half. A short right-side walking detour resolves that deadlock without
	# moving anyone by transform or disabling real body contacts.
	for other in game.players:
		if other==actor or not other.visible: continue
		var offset: Vector3 = other.position-actor.position
		offset.y = 0
		var along := offset.dot(axis)
		if along<.1 or along>1.4: continue
		# Check the actual walk segment, including its endpoint. A player
		# farther past a nearby staging target must not trigger an endless detour.
		if (offset-axis*minf(along,toward.length())).length()>.70: continue
		var point := actor.position+Vector3(axis.z,0,-axis.x)*1.05+axis*.10
		restart_waypoints[id] = {"point":point,"until":restart_walk_clock+1.8}
		return point
	return desired

func _kickoff_shape_target(actor: Node3D, attack: float) -> Vector3:
	return preload("res://scripts/tactics/restart_shape.gd").kickoff_target(actor.role, actor.lane, attack, game.field_half_width, game.field_half_length)

func _kickoff_shape_ready(taker: Node3D) -> bool:
	for actor in game.agents:
		if actor==taker or not actor.visible: continue
		var goal := _kickoff_shape_target(actor,game.attack_direction(actor.team))
		if game.flat_distance(actor.position,goal)>3.0: return false
	return true


func _dispatch_receive_continuation(actor: Node3D, intent: Dictionary) -> bool:
	# AI next_* has already crossed canonical -> live world above. No new plan.
	var plan: Dictionary = intent.get("receive_plan",{})
	if plan.is_empty() or plan.get("state","")!="IN_FLIGHT" or plan.get("next_action","")!="PASS": return false
	var receiver_index := int(plan.get("receiver_id",-1))
	var next_index := int(plan.get("next_receiver_id",-1))
	if receiver_index<0 or receiver_index>=game.players.size() or game.players[receiver_index]!=actor: return false
	if next_index<0 or next_index>=game.players.size(): return false
	var recipient: Node3D = game.players[next_index]
	if recipient==actor or recipient.team!=actor.team or not recipient.visible: return false
	var active: Dictionary = game.tactical_director.receive_plan.active
	var pass_id := String(plan.get("pass_id",""))
	if pass_id=="" or active.get("pass_id","")!=pass_id or int(active.get("receiver_id",-1))!=receiver_index: return false
	var remaining: float = float(plan.get("next_valid_until",0.0))-game.tactical_director.clock
	if remaining<.05 or is_instance_valid(game.ball.carrier) or actor.action_cooldown>0: return false
	var identity := "receive-next:%d:%s:%d:%d" % [game.match_generation,pass_id,receiver_index,next_index]
	if receive_continuations_sent.has(identity): return false
	if actor.foot.receive_pass_window().is_empty(): return false
	var direction: Vector3 = plan.get("next_direction",Vector3.ZERO)
	var target: Vector3 = plan.get("next_target",actor.position)
	if not direction.is_finite() or not target.is_finite() or direction.length_squared()<.001: return false
	var p: FootballPhysicsProfile = game.physics_profile
	var distance := Vector2(target.x-game.ball.position.x,target.z-game.ball.position.z).length()
	var power := clampf((distance-3.5)/13.5,0.0,1.0)
	if p.ground_pass_distance_mapping_enabled:
		power=preload("res://addons/football_ground_pass/ground_pass_solution.gd").power_for_distance(distance,p)

	var request := {"action":"pass_ground","direction":direction.normalized(),"power":power,"elevation_deg":0.0,"spin":Vector3.ZERO,"receiver_id":next_index,"tactical_action":"PASS","one_touch_pass":true,"one_touch_id":identity,"one_touch_valid_seconds":minf(.30,remaining),"source_receive_pass_id":pass_id,"source_next_valid_until":float(plan.next_valid_until)}
	if not game.request_actor_kick(actor,request,recipient): return false
	receive_continuations_sent[identity] = true
	if receive_continuations_sent.size()>32: receive_continuations_sent.erase(receive_continuations_sent.keys()[0])
	return true

func apply_receive_handover(actor:Node3D,event:Dictionary)->void:
	# This is the existing intent's transition at confirmed contact, not a new action clock.
	if game.ball.carrier!=actor:return
	var completed:Dictionary=game.tactical_director.receive_plan.last_plan
	var plan:Dictionary=actor.tactical_intent.get("receive_plan",{})
	var direction:Vector3=actor.facing
	if completed.get("state","")=="COMPLETED" and int(completed.get("receiver_id",-1))==game.players.find(actor) and completed.get("completion_contact",{}).get("serial",-2)==event.get("serial",-1):
		if game.tactical_director.clock<float(plan.get("first_touch_valid_until",0)):
			direction=plan.get("first_touch_direction",direction)
	var actual_outlet:Vector3=Vector3(game.ball.velocity.x,0,game.ball.velocity.z)
	if actual_outlet.length()>.65:direction=actual_outlet.normalized() # Follow the touch that actually happened.
	if direction.length_squared()<.01:direction=actor.facing
	direction=Vector3(direction.x,0,direction.z).normalized()
	var resume_pass:Dictionary={}
	if completed.get("state","")=="COMPLETED" and int(completed.get("receiver_id",-1))==game.players.find(actor) and completed.get("next_action","")=="PASS":
		var next_id:int=int(completed.get("next_receiver_id",-1))
		if next_id>=0 and next_id<game.players.size() and game.players[next_id].team==actor.team:
			# Refresh next decision promptly. The planner owns lane/offside checks;
			# this saved plan only supplies alignment until that decision arrives.
			resume_pass={"pass_id":completed.get("pass_id",""),"receiver_id":next_id,"direction":canonical(completed.get("next_direction",Vector3.ZERO)),"until":game.tactical_director.clock+.35}
			# Save the prospective pass alignment, but follow the real first touch
			# until the planner actually commits that pass. Do not move away from it.
	clock=0.0
	_staged_snapshot.clear()
	contact_refresh_requested=true
	actor.tactical_intent.erase("receive_plan")
	actor.tactical_intent.receive=false
	actor.tactical_intent.press=false
	actor.tactical_intent.close_control=false
	actor.tactical_intent.primary_action="CARRY"
	actor.tactical_intent.reason="receive_follow_through"
	if not resume_pass.is_empty():actor.tactical_intent["receive_outlet_alignment"]=resume_pass
	actor.tactical_intent.face_direction=direction
	actor.tactical_intent.move_target=game.ball.position+direction*2.0
	actor.target=actor.tactical_intent.move_target
	actor.face_target=direction
	actor.tactical_pace=clampf(actual_outlet.length()+.7,2.4,4.8)
	actor.tactical_intent.pace=actor.tactical_pace
	receive_probes[actor.get_instance_id()]={"actor":actor,"at":Time.get_ticks_usec(),"start_frame":Engine.get_physics_frames(),"serial":event.get("serial",-1),"command_ms":-1.0}

func observe_receive_flow()->void:
	for id in receive_probes.keys():
		var probe:Dictionary=receive_probes[id]
		var actor:Node3D=probe.actor
		if not is_instance_valid(actor):receive_probes.erase(id);continue
		var elapsed:float=float(Time.get_ticks_usec()-int(probe.at))/1000.0
		if float(probe.command_ms)<0 and actor._prepared_motion.length()>.4:probe.command_ms=elapsed
		var moved:bool=Vector2(actor.velocity.x,actor.velocity.z).length()>.6
		if moved or elapsed>2000 or game.ball.carrier!=actor:
			receive_timings.append({"actor":game.players.find(actor),"serial":probe.serial,"command_ms":probe.command_ms,"motion_ms":elapsed if moved else -1.0,"end_reason":"moving" if moved else "lost_ball" if game.ball.carrier!=actor else "still_slow","intent":actor.tactical_intent.get("reason",""),"foot":actor.foot.kind,"pending_kick":not actor.pending_kick.is_empty(),"target_gap":actor.position.distance_to(actor.target)})
			if receive_timings.size()>64:receive_timings.pop_front()
			receive_probes.erase(id)

func _restart_offer_targets(restart:Dictionary)->Dictionary:
	var result:Dictionary={}
	if restart.is_empty() or restart.get("kind","") in ["kickoff","penalty","dropped_ball"]:return result
	var taker:Node3D=game.actor_by_instance(int(restart.get("taker_id",-1)))
	if not is_instance_valid(taker):return result
	var candidates:Array=[]
	for other in game.agents:
		if other!=taker and other.team==taker.team and other.visible and other.role!="goalkeeper":candidates.append(other)
	candidates.sort_custom(func(a,b):return a.position.distance_squared_to(restart.point)<b.position.distance_squared_to(restart.point))
	var inward:Vector3=restart.get("inward",Vector3.FORWARD)
	var side:Vector3=Vector3(-inward.z,0,inward.x)
	for i in range(mini(2,candidates.size())):
		var point:Vector3=restart.point+inward*(5.0+i*3.0)+side*(-4.0 if i==0 else 4.0)
		point.x=clampf(point.x,-game.field_half_width+1.5,game.field_half_width-1.5)
		point.z=clampf(point.z,-game.field_half_length+1.5,game.field_half_length-1.5)
		result[candidates[i].get_instance_id()]=point
	return result

func _trace_restart(rules:FBMatchRulesEngine,restart:Dictionary)->void:
	if restart_walk_clock<restart_trace_at:return
	restart_trace_at=restart_walk_clock+2.0
	var taker:Node3D=game.actor_by_instance(int(restart.get("taker_id",-1)))
	var row:Dictionary={"state":rules.state_name(),"serial":restart.get("serial",-1),"kind":restart.get("kind",""),"held":game.ball.held,"ball":str(game.ball.position),"violations":rules.restart_violations()}
	if is_instance_valid(taker):
		row.merge({"taker":game.players.find(taker),"human":taker.is_human,"position":str(taker.position),"target":str(taker.position if taker.is_human else taker.target),"speed":taker.velocity.length(),"foot":taker.foot.kind,"failure":taker.foot.contact_failure,"hit":taker.foot.hit})
	restart_trace.append(row)
	if restart_trace.size()>48:restart_trace.pop_front()
	print("RESTART_PROGRESS ",JSON.stringify(row))

func _receive_snapshot()->Dictionary:
	var rows:Array=[]
	for i in game.players.size():
		var actor:Node3D=game.players[i]
		rows.append({"id":i,"team":actor.team,"position":canonical(actor.position),"velocity":canonical(actor.velocity),"facing":canonical(actor.facing),"active":actor.visible,"stamina":actor.get("stamina") if actor.get("stamina")!=null else 100.0,"sprint_locked":actor.get("sprint_locked")==true,"foot_cap":actor.foot.movement_cap()})
	for i in range(rows.size()):rows[i].merge(preload("res://scripts/player_abilities.gd").observation(game.players[i]))
	var p=game.physics_profile
	return {"players":rows,"ball_position":canonical(game.ball.position),"ball_velocity":canonical(game.ball.velocity),"carrier_id":game.players.find(game.ball.carrier),"field_half_width":game.field_half_width,"field_half_length":game.field_half_length,"physics_frame":Engine.get_physics_frames(),"motor_profile":p,"movement_cfg":game.tuning,"roll_samples":ReceiveMotion.ball_samples(canonical(game.ball.position),canonical(game.ball.velocity),canonical(game.ball.spin_rads),p),"capabilities":{"receive_speed":game.tuning.running_move_speed,"brake_deceleration":p.brake_deceleration_mps2,"run_acceleration":p.start_acceleration_mps2,"turn_speed":5.8,"ground_receive_height":.42,"reaction_delay":.16}}

func infer_receive_target(passer:Node3D)->Node3D:
	# Called once at a real unaddressed pass. Direction/force have already been applied.
	var snapshot:Dictionary=_receive_snapshot()
	var candidates:Array=[]
	var origin:Vector3=snapshot.ball_position
	var axis:Vector3=Vector3(snapshot.ball_velocity.x,0,snapshot.ball_velocity.z).normalized()
	for row in snapshot.players:
		var actor:Node3D=game.players[int(row.id)]
		if actor==passer or actor.team!=passer.team or not actor.visible or actor.is_goalkeeper:continue
		var delta:Vector3=row.position-origin;delta.y=0
		# Side-on and recently overtaken runners can still reach the ball ahead.
		if delta.length()>48 or (delta.dot(axis)<-5.0 and delta.length()>7.0):continue
		var nearest:float=INF
		for sample in snapshot.roll_samples:
			nearest=minf(nearest,(Vector3(sample.point.x,0,sample.point.z)-Vector3(row.position.x,0,row.position.z)).length())
		if nearest>9.0:continue
		candidates.append({"row":row,"cost":nearest+delta.length()*.06})
	candidates.sort_custom(func(a,b):return a.cost<b.cost)
	var evaluator=preload("res://scripts/tactics/receive_plan.gd").new()
	var selected:Node3D=null
	var best:float=INF
	for i in mini(4,candidates.size()):
		var row:Dictionary=candidates[i].row
		var prediction:Dictionary=evaluator._intercept(row,snapshot)
		# Permit a small chase margin, not an impossible six-second reservation.
		if not prediction.reachable and float(prediction.late_by)>.30:continue
		var cost:float=float(prediction.receiver_eta)+maxf(0,float(prediction.late_by))*2.0+float(candidates[i].cost)*.04
		if cost<best:best=cost;selected=game.players[int(row.id)]
	return selected

func _refresh_receive_motion()->void:
	var now:float=game.tactical_director.clock+decision_elapsed
	receive_motion_at=now
	var plan:Dictionary=game.tactical_director.receive_plan.tick(_receive_snapshot(),now,0)
	if plan.is_empty():clock=0;return
	var actor:Node3D=game.players[int(plan.receiver_id)]
	if actor.is_human:return
	# Same receive-plan owner and same bridge as the full tick. No second tactical job.
	for key in ["receive_point","approach_point","face_direction","live_ball_position","live_ball_velocity","next_direction","next_target","first_touch_direction","first_touch_target"]:
		if plan.has(key):plan[key]=canonical(plan[key])
	actor.tactical_intent["receive_plan"]=plan
	actor.tactical_intent["move_target"]=plan.approach_point
	actor.tactical_intent["face_direction"]=plan.face_direction
	actor.tactical_intent["pace"]=plan.pace
	actor.tactical_intent["receive"]=true
	actor.tactical_intent["press"]=false
	actor.tactical_intent["ball_job_owner"]=int(plan.receiver_id)
	actor.tactical_intent["primary_action"]="RECEIVE"
	actor.pending_kick.clear()
	actor.shielding=false;actor.close_control=false
	actor.tactical_intent["shield"]=false;actor.tactical_intent["close_control"]=false
	actor.target=plan.approach_point;actor.face_target=plan.face_direction;actor.tactical_pace=plan.pace
