class_name FootballAgent
extends "res://scripts/integration_player_motor.gd"
const FootScript := preload("res://scripts/foot_action.gd")
const PoseState02 := preload("res://addons/football_motion/pose_state_02.gd")
const CharacterScene := preload("res://addons/football_character/football_character.tscn")
const PoseScript := preload("res://addons/football_role_actions/defence_avatar_03.gd")
const KeeperPoseScript := preload("res://addons/football_keeper/keeper_avatar.gd")
const LowerContacts := preload("res://scripts/football_lower_contacts.gd")
var match_controller: Node
var down_state: Node
var team := 1
var role := "midfielder"
var lane := 0.0
var jersey := 9
var is_human := false
var is_goalkeeper := false
var target := Vector3.ZERO
var home := Vector3.ZERO
var facing := Vector3.BACK
var body_facing := Vector3.BACK
var face_target := Vector3.BACK
var shielding := false
var close_control := false
var ai_pocket_recover := false
var ai_carry_aim := Vector3.ZERO
var ai_touch_pace := 5.0
var shield_side := 1.0
var turn_hint := 1.0
var move_requested := false
var sprinting := false
var long_touch := false
var sole_stopped := false
var stop_requested := 0.0
var tackle_cooldown := 0.0
var action_cooldown := 0.0
var tactical_pace := 5.4
var tactical_intent: Dictionary = {}
var pending_kick: Dictionary = {}
var pending_age := 0.0
var kick_retry_at:=0.0
var pending_receive_confirmed := false
var active := false
var foot: FootballFootAction
var avatar: Node3D
var body_root: Node3D
var locomotion := "idle"
var pending_pose_delta := 0.0
var pose_updates_enabled := true # External profiler only; normal play stays true.
var motion_acceleration := Vector3.ZERO
var dribble_balance=preload("res://scripts/dribble_balance.gd").new()
var last_motion_velocity := Vector3.ZERO
var control_arc_side := 0.0
var _ai_rhythm_feature := true
var _ai_turn_feature := true
var _ai_ordinary_rhythm := false
var running_to_target := false
var ai_cut_cooldown:=0.0
var guarding_lane:=false
var holding_position:=false

func ai_ordinary_rhythm() -> bool:
	# Cached geometry only; cheap live ownership/action recheck at each caller.
	return _ai_rhythm_feature and _ai_ordinary_rhythm and active and match_controller.phase==match_controller.Phase.PLAY and not match_controller.ball.held and match_controller.ball.carrier==self and pending_kick.is_empty() and not foot.has_buffer() and (foot.idle() or foot.continuous_control() or foot.kind=="RECEIVE" and foot.hit)

func ai_ordinary_turn() -> bool:
	return _ai_turn_feature and ai_ordinary_rhythm()


func _ready() -> void:
	super._ready()
	var feature_args := OS.get_cmdline_user_args()
	_ai_rhythm_feature = not "--ai-dribble-rhythm=A" in feature_args and not "--dribble-rhythm=A" in feature_args
	_ai_turn_feature = not "--three-speed-turn=A" in feature_args and not "--dribble-turn=A" in feature_args
	auto_step = false
	process_physics_priority = -40
	foot = FootScript.new(self,match_controller)
	avatar = CharacterScene.instantiate()
	avatar.set_script(KeeperPoseScript if is_goalkeeper else PoseScript)
	avatar.name = "CharacterVisual"
	add_child(avatar)
	avatar.setup(team,jersey,false)
	var lower_contacts := LowerContacts.new()
	lower_contacts.actor = self
	add_child(lower_contacts)
	body_root = avatar
	refresh_pose(0)

func _physics_process(delta: float) -> void:
	ai_cut_cooldown=maxf(0,ai_cut_cooldown-delta)
	_ai_ordinary_rhythm = false
	motion_acceleration = ((velocity-last_motion_velocity)/maxf(delta,.000001)).limit_length(32.0)
	last_motion_velocity = velocity
	tackle_cooldown = maxf(0,tackle_cooldown-delta)
	action_cooldown = maxf(0,action_cooldown-delta)
	stop_requested = maxf(0,stop_requested-delta)
	if is_instance_valid(down_state) and down_state.blocked():
		down_state.clear_action_cache()
		set_move_intent(Vector3.ZERO)
		move_requested = false
		pending_pose_delta += delta
		return
	if not active:
		set_move_intent(Vector3.ZERO)
		return
	if match_controller.services.rules.state!=match_controller.Rules.State.LIVE:
		_restart_motion(delta)
		return
	var toward := Vector3(target.x-position.x,0,target.z-position.z)
	var owned: bool = match_controller.ball.carrier == self
	# Each new reservation may cushion once; only an actual shoe hit confirms it.
	if pending_kick.is_empty() or pending_age==0.0: pending_receive_confirmed = false
	if not pending_kick.is_empty() and foot.kind=="RECEIVE" and foot.hit:
		pending_receive_confirmed = true
	# Normal carry was released by the planner's real control contact gate.
	# Only that single owner reads reach; no extra pose/support snapshots.
	# One carry executor owns the complete rolling pocket, including brief reach loss.
	# Actual shoe reach still gates every contact; do not switch to legacy PULL on it.
	_ai_ordinary_rhythm = _ai_rhythm_feature and owned and pending_kick.is_empty() and not foot.has_buffer() and match_controller.ball.position.y<.42 and (foot.idle() or foot.continuous_control() or foot.kind=="RECEIVE" and foot.hit)
	var cut_active:bool=owned and not foot.idle() and foot.touch_plan.has("cut_style")
	var third_setup: bool = owned and tactical_intent.get("third_man_plan",{}).get("state","")=="CONTROLLED" and tactical_intent.get("reason","") in ["confirm_control_then_turn","third_man_prepare_outlet"]
	var controlled_setup := false
	var setup_motion := Vector3.ZERO
	move_requested = toward.length()>.18
	var reachable_pass:bool=not pending_kick.is_empty() and String(pending_kick.action).begins_with("pass_") and not preload("res://scripts/pass_contact_choice.gd").choose(self,match_controller.ball,pending_kick).is_empty()
	if not pending_kick.is_empty(): face_target = facing if reachable_pass else pending_kick.direction
	elif foot.kind in ["PASS","SHOT"] and foot.phase in [foot.Phase.PREPARE,foot.Phase.CONTACT]: face_target = facing if foot.kind=="PASS" else foot.direction
	var desired_facing := face_target if face_target.length()>.1 else toward.normalized()
	var ball_gap:float=match_controller.flat_distance(position,match_controller.ball.position)
	# Recover only a stalled, out-of-pocket AI ball. Normal rolling carry never
	# enters this path, and neither ball placement nor contact reach is changed.
	var pocket_offset:Vector3=Vector3(match_controller.ball.position.x-position.x,0,match_controller.ball.position.z-position.z)
	var pocket_front:float=pocket_offset.dot(face_target.normalized())
	ai_pocket_recover=owned and pending_kick.is_empty() and match_controller.ball.velocity.length()<.65 and (ai_pocket_recover or velocity.length()<1.5) and (ball_gap>(.60 if ai_pocket_recover else .78) or pocket_front<(.25 if ai_pocket_recover else -.10))
	if ai_pocket_recover:_ai_ordinary_rhythm=false
	if _ai_ordinary_rhythm and toward.length()>.1:
		if ai_carry_aim.length_squared()<.1:ai_carry_aim=facing
		var turn_rate:float=lerpf(4.0,1.6,clampf(velocity.length()/5.0,0,1))
		var angle:float=ai_carry_aim.signed_angle_to(toward.normalized(),Vector3.UP)
		ai_carry_aim=ai_carry_aim.rotated(Vector3.UP,clampf(angle,-turn_rate*delta,turn_rate*delta)).normalized()
		if tactical_intent.get("reason","")=="keep_ball_inside_before_line":
			# Begin real motor braking now. Retaining a slowly rotating old target
			# until after the line consumes the available stopping distance.
			ai_carry_aim=toward.normalized()
		toward=ai_carry_aim*toward.length();desired_facing=ai_carry_aim
		ai_touch_pace=tactical_pace
	else:ai_carry_aim=Vector3.ZERO
	# Chase with the body facing travel; close marking and reception still face the ball.
	# Hysteresis avoids toggling at the edge of jockey range. Actual turning shares the speed-dependent body limit.
	var travel_allowed:bool=not owned and not is_goalkeeper and pending_kick.is_empty() and not tactical_intent.has("receive_plan") and (foot.idle() or foot.phase==foot.Phase.RECOVER)
	var travel_need:bool=toward.length()>(.85 if running_to_target else 1.4) and tactical_pace>3.2 and (ball_gap>(2.2 if running_to_target else 3.0) or toward.normalized().dot(desired_facing.normalized())<.25)
	running_to_target=travel_allowed and travel_need
	var defensive_job:String=String(tactical_intent.get("defensive_task",{}).get("task",""))
	var guard_range:float=3.6 if guarding_lane else 2.8
	guarding_lane=not owned and not is_goalkeeper and pending_kick.is_empty() and defensive_job in ["PRESS","COVER","MARK","SCREEN","HOLD"] and toward.length()<guard_range and ball_gap<maxf(7.0,match_controller.field_half_length*.32) and not tactical_intent.get("receive",false)
	if guarding_lane and ball_gap>2.0 and toward.length()>1.2 and match_controller.ball.velocity.length()>3.4:
		guarding_lane=false;running_to_target=travel_allowed
	if guarding_lane:
		running_to_target=false
		var watch:Vector3=Vector3(match_controller.ball.position.x-position.x,0,match_controller.ball.position.z-position.z).normalized()
		if ball_gap>.40:desired_facing=watch.rotated(Vector3.UP,.22*(-1.0 if jersey%2 else 1.0))
		else:desired_facing=facing
	elif running_to_target:desired_facing=toward.normalized()
	if owned and not (foot.kind in ["PASS","SHOT"] and not foot.idle()):
		var offset := Vector3(match_controller.ball.position.x-position.x,0,match_controller.ball.position.z-position.z)
		var requested_face := face_target.normalized() if face_target.length()>.1 else facing
		var receiving:bool = foot.kind=="RECEIVE" and not foot.idle() and not foot.hit
		if not cut_active and (third_setup or receiving or (not ai_ordinary_rhythm() and (offset.dot(requested_face)<.25 or not match_controller.ball.reception_ready(self)))):
			controlled_setup = true
			# Finish the finite receive action while facing the actual ball. Then
			# walk around it to the requested heading; never run through/past it.
			var aligned := offset.normalized().dot(requested_face)>.86
			var setup_face := offset.normalized() if receiving and not aligned else requested_face
			# A front, reachable ball needs a short linear setup, not an orbit.
			# Backside/unreachable geometry retains the original clearance arc.
			setup_motion = _ball_setup_motion(setup_face)
			desired_facing = requested_face if aligned else offset.normalized() if offset.length()>.1 else setup_face
	if not controlled_setup: control_arc_side = 0.0
	if ai_pocket_recover and pocket_front>.15:
		var pocket:Vector3=Vector3(match_controller.ball.position.x-position.x,0,match_controller.ball.position.z-position.z)
		controlled_setup=true;desired_facing=pocket.normalized()
		setup_motion=pocket.normalized()*clampf((pocket.length()-.48)*4.0,0.0,1.4)
	if not owned and tactical_intent.has("receive_plan"):
		var reception:Dictionary=tactical_intent.receive_plan
		var elapsed:float=float(Engine.get_physics_frames()-int(reception.get("sample_frame",Engine.get_physics_frames())))/Engine.physics_ticks_per_second
		var remaining:float=float(reception.get("arrival_time",0))-float(reception.get("sample_time",match_controller.tactical_director.clock))-elapsed
		desired_facing=preload("res://scripts/tactics/receive_motion.gd").travel_facing(position,target,face_target,remaining)
	if foot.kind=="TACKLE" and not foot.idle() and foot.phase!=foot.Phase.RECOVER and not bool(foot.touch_plan.get("automatic",false)):desired_facing=foot.direction
	var current_yaw := atan2(-facing.x,-facing.z)
	var wanted_yaw := atan2(-desired_facing.x,-desired_facing.z)
	var turn_rate:float=preload("res://scripts/movement_inertia.gd").yaw_rate(Vector2(velocity.x,velocity.z).length())
	var change := clampf(angle_difference(current_yaw,wanted_yaw),-turn_rate*delta,turn_rate*delta)
	if absf(change)>.0001: turn_hint = signf(change)
	current_yaw += change
	facing = Vector3(-sin(current_yaw),0,-cos(current_yaw))
	body_facing = facing
	var pace := tactical_pace
	if not owned and pace>3.0:pace*=preload("res://scripts/player_abilities.gd").value(self,"pace")
	if _ai_ordinary_rhythm and pocket_offset.dot(ai_carry_aim)>.45 and tactical_intent.get("reason","")!="keep_ball_inside_before_line":
		# Do not brake the body away from its already rolling ball before the
		# next actual shoe contact can shorten that ball's stride.
		pace=maxf(pace,minf(5.0,Vector2(match_controller.ball.velocity.x,match_controller.ball.velocity.z).length()))
	set_meta("motor_guard",guarding_lane)
	if guarding_lane:pace=minf(pace,3.0)
	var run_carry:bool=owned and tactical_intent.get("carry_run",false) and not shielding and not close_control and pending_kick.is_empty() and not controlled_setup
	if owned: pace = minf(pace,match_controller.tuning.sprint_ball_speed if run_carry else 4.8)
	# Select the existing running touch schedule BEFORE ball-follow evaluates it.
	if owned:sprinting=run_carry
	if shielding: pace = minf(pace,2.1)
	var preparing_kick := false
	if not pending_kick.is_empty():
		pending_age += delta
		if pending_age>.85 or not owned:
			if owned:kick_retry_at=match_controller.tactical_director.clock+.65
			pending_kick.clear()
		else:
			preparing_kick = true
			# Follow a moving ball while cushioning with actual inside-foot contact.
			# A full STOP slowed the body before reaching the ball and lost reach.
			var setup: Vector3 = match_controller.ball.position-(facing if reachable_pass else pending_kick.direction)*.44
			var offset := Vector3(setup.x-position.x,0,setup.z-position.z)
			var ball_motion := Vector3(match_controller.ball.velocity.x,0,match_controller.ball.velocity.z)
			var approach := setup_motion if controlled_setup else (ball_motion+offset*4.0).limit_length(4.8)
			toward = approach
			move_requested = approach.length()>.08
			pace = approach.length()
			stop_requested = 0
			var gap: float = match_controller.flat_distance(position,match_controller.ball.position)
			# A controlled rolling ball may be fast in world space while matching
			# the player's motion. Keep real reception/reach/foot permission gates;
			# world speed alone must not leave a ready pending kick waiting forever.
			var relative_motion: Vector3 = match_controller.ball.velocity-velocity
			var controlled_motion: bool = owned and match_controller.ball.reception_ready(self) and relative_motion.length()<2.8
			var yielding_touch:bool=foot.phase==foot.Phase.RECOVER and foot.hit and foot.kind in ["CLOSE","TURN","SHIELD","CARRY","RECEIVE"]
			if yielding_touch and controlled_motion and (reachable_pass or facing.dot(pending_kick.direction)>.84) and gap<.92:
				foot.cancel("ai_ready_kick_handover")
			var kick_aligned:bool=controlled_motion and gap>=.18 and gap<.94 and Vector3(match_controller.ball.position.x-position.x,0,match_controller.ball.position.z-position.z).normalized().dot(pending_kick.direction)>(.38 if String(pending_kick.action).begins_with("pass_") else .60)
			if ((reachable_pass and match_controller.ball.can_pass(self)) or (kick_aligned and facing.dot(pending_kick.direction)>.94 and match_controller.ball.can_kick(self))) and (foot.idle() or (foot.kind=="RECEIVE" and foot.hit and match_controller.ball.reception_ready(self))) and action_cooldown<=0 and gap<.94 and controlled_motion:
				if match_controller.request_actor_kick(self,pending_kick): pending_kick.clear()
			elif not pending_receive_confirmed and foot.idle() and gap<.73 and match_controller.can_reach_ball(self) and not match_controller.ball.reception_ready(self):
				foot.begin("RECEIVE",facing,Vector3.ZERO,0,.18)
	if controlled_setup:
		toward = setup_motion
		pace = setup_motion.length()
		move_requested = pace>.08
	elif owned and not preparing_kick:
		# Use the existing rolling-ball follow helper also for AI carrier intent.
		# The motor still supplies the same acceleration and swept collisions.
		toward = match_controller.ball.human_dribble_motion(self,toward.normalized(),pace)
		pace = toward.length()
		move_requested = pace>.08
	# Endpoint hysteresis belongs to the motor, not a second tactical target filter.
	if not owned and not preparing_kick and not tactical_intent.has("receive_plan"):
		var urgent:bool=defensive_job=="PRESS" and ball_gap<1.45
		var distance:float=toward.length()
		if urgent or distance>(.34 if holding_position else .16):holding_position=false
		elif distance<.16:holding_position=true
		if holding_position:move_requested=false
		pace=minf(pace,sqrt(2.0*profile.brake_deceleration_mps2*maxf(0,distance-.10)))
	else:holding_position=false
	pace = minf(pace,foot.movement_cap())
	if not preparing_kick and not owned and toward.length()<.8 and not tactical_intent.has("receive_plan"): pace *= clampf(toward.length()/.8,0,1)
	sprinting = run_carry or pace>profile.jog_speed_mps
	var sprint_value := clampf((pace-profile.jog_speed_mps)/(profile.sprint_speed_mps-profile.jog_speed_mps),0,1)
	var axis := toward.normalized() if move_requested else Vector3.ZERO
	set_move_intent(axis*pace/lerpf(profile.jog_speed_mps,profile.sprint_speed_mps,sprint_value),sprint_value)
	var backwards := axis.dot(facing)<-.3
	dribble_balance.step(self,delta,owned)
	locomotion = "shield" if shielding else "retreat" if guarding_lane and backwards else "strafe" if guarding_lane and absf(axis.dot(facing))<.65 else "jockey" if guarding_lane or tactical_intent.get("press",false) and not running_to_target and velocity.length()<3.5 else "retreat" if backwards else "dribble" if owned and move_requested else "run" if velocity.length()>3.5 else "walk" if velocity.length()>.12 else "idle"
	pending_pose_delta += delta

func _ball_setup_motion(wanted: Vector3) -> Vector3:
	var ball: MatchFootball = match_controller.ball
	var radial := Vector3(position.x-ball.position.x,0,position.z-ball.position.z)
	var goal_radial := -wanted*.44
	var point := Vector3(ball.position.x,0,ball.position.z)+goal_radial
	var offset := -radial
	var reachable_front: bool = offset.length()>=.18 and offset.length()<.72 and offset.normalized().dot(wanted)>.60 and offset.normalized().dot(facing)>.60 and match_controller.can_reach_ball(self)
	if reachable_front:
		control_arc_side = 0.0
		# No readiness assertion: existing real-contact/relative-speed gates remain.
		return (Vector3(ball.velocity.x,0,ball.velocity.z)+(point-position)*4.0).limit_length(4.8 if not pending_kick.is_empty() or tactical_intent.get("third_man_plan",{}).get("state","")=="CONTROLLED" else 2.4)
	if radial.length()>.10 and goal_radial.length()>.10:
		var turn := radial.signed_angle_to(goal_radial,Vector3.UP)
		if absf(turn)>.35:
			if control_arc_side==0.0: control_arc_side = signf(turn)
			# Keep the selected side across the +/-PI seam instead of folding back.
			point = Vector3(ball.position.x,0,ball.position.z)+radial.normalized().rotated(Vector3.UP,control_arc_side*minf(.65,absf(turn)))*.64
		else: control_arc_side = 0.0
	var error := Vector3(point.x-position.x,0,point.z-position.z)
	var rolling := Vector3(ball.velocity.x,0,ball.velocity.z)
	# A reserved kick follows the rolling ball while circling to its heading.
	# Use the existing pending approach budget; ordinary reception stays 2.4.
	return (rolling+error*4.0).limit_length(4.8 if not pending_kick.is_empty() or tactical_intent.get("third_man_plan",{}).get("state","")=="CONTROLLED" else 2.4)

const VisualCadence39:=preload("res://scripts/visual_pose_cadence39.gd")
var _visual_far39:=false
var _visual_pose_deferred39:=false
var _visual_pose_forcing39:=false
var _visual_pose_tick39:=-100
var _visual_pose_skips39:=0
var _visual_policy_tick_perf:=-1
var _visual_next_draw_usec_perf:=0
var _visual_mid_draw_frame:=-1
var _display_gait_only:=false
var _display_gait_pending:=false
var _display_exact_handoffs:=0
func ensure_contact_pose_current()->void:
	if _visual_pose_forcing39:return
	if not _display_gait_pending and not _visual_pose_deferred39 and (not _visual_far39 or _visual_pose_tick39==Engine.get_physics_frames()):return
	_visual_pose_forcing39=true
	refresh_pose()
	_visual_pose_forcing39=false

func refresh_pose(delta := 0.0) -> void:
	if _display_gait_only:
		if not is_instance_valid(avatar):return
		avatar.ai_body_presentation.restore(avatar)
		avatar.update_display_gait(delta+pending_pose_delta,{"velocity":velocity,"acceleration":motion_acceleration,"forward":facing,"locomotion":locomotion,"ai_guard":guarding_lane})
		pending_pose_delta=0.0
		_display_gait_pending=true;_visual_pose_deferred39=true
		return
	var tick39:int=Engine.get_physics_frames()
	if not _visual_pose_forcing39 and VisualCadence39.far_visual(self):
		_visual_pose_deferred39=true;_visual_pose_skips39+=1
		return
	if not _visual_pose_forcing39 and VisualCadence39.defer_mid_pose(self):
		_visual_pose_deferred39=true
		preload("res://scripts/frame_spike_watch.gd").mid_pose_skips+=1
		return
	if _display_gait_pending:_display_exact_handoffs+=1
	_display_gait_pending=false
	_visual_pose_tick39=tick39
	_visual_pose_deferred39=false
	if not is_instance_valid(avatar): return
	if not pose_updates_enabled:
		pending_pose_delta = 0.0
		return
	delta += pending_pose_delta
	pending_pose_delta = 0.0
	if foot != null and not foot.idle(): avatar.set_foot_action(foot.pose_request())
	else: avatar.clear_foot_action()
	var low: bool = is_instance_valid(down_state) and down_state.blocked()
	var pose_state := {"velocity":velocity,"acceleration":motion_acceleration,"forward":down_state.direction if low else facing,"grounded":not low and position.y<.025,"locomotion":locomotion,"interaction":down_state.pose_state() if low else {}}
	pose_state["ai_guard"]=guarding_lane
	pose_state["ai_carry_continuity"]=true
	var owned: bool = is_instance_valid(match_controller.ball) and match_controller.ball.carrier == self
	var active_kind := String(foot.kind) if foot != null and not foot.idle() else ""
	# Real controlled free-roll intervals keep the carry presentation; possession,
	# motor intent and foot permissions continue to use the original owned flag.
	var rolling_carry:bool=is_instance_valid(match_controller.ball) and not is_instance_valid(match_controller.ball.carrier) and match_controller.ball.last_contact_actor==self and match_controller.ball.touch_age<.28 and position.distance_squared_to(match_controller.ball.position)<2.25 and active_kind in ["","CLOSE","TURN","CARRY","SPRINT","SHIELD"]
	var carry_visual:bool=owned or rolling_carry
	if carry_visual and move_requested and not shielding:pose_state.locomotion="dribble"
	var tier := PoseState02.control_tier({},carry_visual,close_control,shielding,active_kind,0.0)
	var world_step: int = match_controller.physics_world.step_serial if is_instance_valid(match_controller.physics_world) else -1
	avatar.update_pose(delta,PoseState02.stamp(pose_state,Engine.get_physics_frames(),tier,world_step))
	if low: down_state.sync_head_shape()

func advance_motor(dt: float) -> void:
	if is_instance_valid(down_state) and down_state.override_motor(dt):
		_apply_origin_ground_support(dt)
		return
	super.advance_motor(dt)

func interaction_vertical_bounds() -> Vector2:
	return down_state.vertical_bounds() if is_instance_valid(down_state) and down_state.blocked() else Vector2(global_position.y,global_position.y+profile.player_height_m)

func refresh_legs() -> void:
	refresh_pose()

func get_ball_direction() -> Vector3:
	if ai_ordinary_rhythm() and ai_carry_aim.length_squared()>.1:return ai_carry_aim
	if ai_ordinary_rhythm() and move_requested:
		var requested:Vector3=target-position;requested.y=0
		if requested.length_squared()>.01:return requested.normalized()
	return facing

func set_match_active(enabled: bool) -> void:
	active = enabled
	if not active:
		pending_kick.clear()
		set_move_intent(Vector3.ZERO)
		foot.cancel()

func kick_touch(_at: Vector3, _side: float, _mode: String) -> void:
	refresh_pose()

# Read only at a real RECEIVE contact; the contact owner still limits the impulse.
func planned_receive_direction() -> Vector3:
	if not active or match_controller.phase!=match_controller.Phase.PLAY or match_controller.ball.held: return Vector3.ZERO
	var plan: Dictionary = tactical_intent.get("receive_plan",{})
	var current: Dictionary = match_controller.tactical_director.receive_plan.active
	if plan.is_empty() or current.get("state","")!="IN_FLIGHT" or current.get("pass_id","")!=plan.get("pass_id",""): return Vector3.ZERO
	if int(current.get("receiver_id",-1))!=match_controller.players.find(self): return Vector3.ZERO
	if match_controller.tactical_director.clock>=float(plan.get("first_touch_valid_until",0.0)): return Vector3.ZERO
	if is_instance_valid(match_controller.ball.carrier) and match_controller.ball.carrier!=self: return Vector3.ZERO
	var outlet: Vector3 = plan.get("first_touch_direction",Vector3.ZERO)
	if not outlet.is_finite() or outlet.length_squared()<.01: return Vector3.ZERO
	outlet = Vector3(outlet.x,0,outlet.z).normalized()
	# A body cannot take an outlet behind its current facing with an inside touch.
	if outlet.dot(facing)<-.85 and Vector2(velocity.x,velocity.z).length()<.5:return Vector3.ZERO
	var point: Vector3 = plan.get("first_touch_target",match_controller.ball.position)
	if not point.is_finite() or absf(point.x)>match_controller.field_half_width-1.0 or absf(point.z)>match_controller.field_half_length-1.0: return Vector3.ZERO
	for opponent in match_controller.players:
		if not opponent.visible or opponent.team==team: continue
		# Recheck the short outlet against actual pressure at contact, not an old preview.
		var threat: Vector3 = opponent.position+Vector3(opponent.velocity.x,0,opponent.velocity.z)*.15
		if Vector2(threat.x-point.x,threat.z-point.z).length()<1.2: return Vector3.ZERO
	return outlet

func _restart_motion(delta:float)->void:
	var travel:Vector3=Vector3(target.x-position.x,0,target.z-position.z)
	var committed:bool=foot.kind in ["PASS","SHOT"] and not foot.idle() or match_controller.throw_requests.has(get_instance_id())
	var desired:Vector3=foot.direction if committed and not foot.idle() else face_target
	if not committed and travel.length()>1.5:desired=travel.normalized()
	if desired.length_squared()>.01:
		var yaw:float=atan2(-facing.x,-facing.z)
		yaw+=clampf(angle_difference(yaw,atan2(-desired.x,-desired.z)),-5.8*delta,5.8*delta)
		facing=Vector3(-sin(yaw),0,-cos(yaw));body_facing=facing
	var pace:float=minf(tactical_pace,sqrt(2.0*profile.brake_deceleration_mps2*maxf(0,travel.length()-.10)))
	pace=minf(pace,foot.movement_cap())
	move_requested=not committed and travel.length()>.10
	var motion:Vector3=travel.normalized()*pace if move_requested else Vector3.ZERO
	var run:float=clampf((pace-profile.jog_speed_mps)/maxf(.01,profile.sprint_speed_mps-profile.jog_speed_mps),0,1)
	set_move_intent(motion/lerpf(profile.jog_speed_mps,profile.sprint_speed_mps,run),run)
	locomotion="run" if velocity.length()>3.5 else "walk" if velocity.length()>.12 else "idle"
	pending_pose_delta+=delta
