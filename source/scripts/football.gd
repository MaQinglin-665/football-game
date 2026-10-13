class_name MatchFootball
extends "res://addons/football_physics/football_ball.gd"
const DribbleRhythm := preload("res://scripts/dribble_rhythm.gd")
const VisualScript := preload("res://scripts/football_visual.gd")
var tuning: FootballControlTuning
var control_mode := "SETTLE"
var last_contact_position := Vector3.ZERO
var last_contact_delta := Vector3.ZERO
var carrier: Node3D
var previous_carrier: Node3D
var pickup_block := 0.0
var possession_grace := 0.0
var last_touch_team := -1
var match_controller: Node
var touch_timer := 0.0
var dribble_free_roll_remaining := 0.0
var touch_age := 0.0
var touch_count := 0
var possession_age := 0.0
var last_foot_position := Vector3.ZERO
var last_dribbler: Node3D
var last_contact_actor: Node3D
var push_age := 0.0
var last_kick_intent: Dictionary = {}
var visual: MeshInstance3D
var marker: MeshInstance3D
var held := true
var receive_ab_legacy := false

func _ready() -> void:
	name = "Football"
	super._ready()
	auto_step = false
	process_physics_priority = -20
	tuning = match_controller.tuning
	visual = MeshInstance3D.new()
	visual.name = "LeatherBall"
	visual.mesh = VisualScript.make(radius)
	add_child(visual)
	marker = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = .145
	ring.outer_radius = .154
	ring.rings = 16
	ring.ring_segments = 8
	marker.mesh = ring
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("f3ce78")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.material_override = material
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(marker)
	marker.top_level=true
	marker.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	physical_contact.connect(match_controller.on_ball_body_contact)
	set_held(true)

func _physics_process(delta: float) -> void:
	if match_controller.phase in [match_controller.Phase.MENU,match_controller.Phase.PAUSED,match_controller.Phase.FINISHED]: return
	pickup_block = maxf(0,pickup_block-delta)
	touch_timer = maxf(0,touch_timer-delta)
	dribble_free_roll_remaining = maxf(0,dribble_free_roll_remaining-delta)
	touch_age += delta
	push_age = maxf(0,push_age-delta)
	if is_instance_valid(carrier):
		possession_age += delta
		_update_dribble()
	if not held:
		match_controller.schedule_interceptions(delta)
		match_controller.schedule_receiving()
	for actor in match_controller.players:
		if actor.visible: actor.foot.advance(delta)

func _process(_delta: float) -> void:
	if is_instance_valid(marker):
		var shown:Vector3=get_global_transform_interpolated().origin
		marker.global_position = Vector3(shown.x,.045,shown.z)
		marker.visible = position.y<1 and match_controller.phase!=match_controller.Phase.MENU

func _substep(delta: float) -> void:
	if not held:
		var before_spin := spin_rads
		var before_position:=global_position
		var was_supported:=grounded
		super._substep(delta)
		var average_spin:Vector3=(before_spin+spin_rads)*.5
		var slip:float=(velocity+spin_rads.cross(Vector3.DOWN*radius)).length()
		if was_supported and grounded and slip<.03:
			# One visual owner; pure rolling follows actual swept displacement.
			average_spin=Vector3.UP.cross(global_position-before_position)/(radius*delta)+Vector3.UP*average_spin.y
		_advance_visual_spin(average_spin, delta)

func _advance_visual_spin(spin_world: Vector3, delta: float) -> void:
	# Visual only: integrate at the same substeps as the existing ball motion.
	# Modulo a full turn preserves orientation; it never caps elapsed rotation.
	if not is_instance_valid(visual) or not spin_world.is_finite() \
			or not is_finite(delta) or delta <= 0.0:
		return
	var speed := spin_world.length()
	var angle := speed * delta
	if speed <= 0.00000001 or not is_finite(speed) or not is_finite(angle):
		return
	var axis := (global_basis.orthonormalized().inverse() * (spin_world / speed)).normalized()
	var turn := Quaternion(axis, fposmod(angle, TAU))
	visual.quaternion = (turn * visual.quaternion).normalized()

func set_held(value: bool) -> void:
	held = value
	collision_layer = 0 if value else 4
	collision_mask = 1 if value else 11 # Turf + upper bodies + separate lower contacts.
	if value:
		velocity = Vector3.ZERO
		spin_rads = Vector3.ZERO

func clear_control(cancel_actions := true) -> void:
	if is_instance_valid(carrier):carrier.foot.ordinary_scheduler.reset_turn(carrier,"control_cleared")
	previous_carrier = carrier
	carrier = null
	pickup_block = 0
	touch_timer = 0
	possession_age = 0
	last_dribbler = null
	push_age = 0
	if cancel_actions:
		for actor in match_controller.players:
			actor.foot.cancel()
			if not actor.is_human: actor.pending_kick.clear()
	match_controller.sync_input_context()

func _update_dribble() -> void:
	var owner := carrier
	if held or not match_controller.can_touch_ball(owner): return
	var offset: Vector3 = position-owner.position
	offset.y = 0
	var gap := offset.length()
	if gap>DribbleRhythm.control_reach(owner,self) or position.y>.65:
		detach("球已离脚，追上后接球")
		return
	# Let the single cut impulse cross the body before an automatic settle/retap.
	if Engine.get_physics_frames()<owner.foot.cut_roll_until and gap<.95 and last_contact_actor==owner:return
	if owner.foot.shared_ordinary_control() and (owner.is_human or owner.pending_kick.is_empty()):
		_update_human_dribble(owner,offset,gap)
		return
	if not owner.foot.idle() or owner.foot.has_buffer() or touch_timer>0: return
	if not owner.is_human and not owner.pending_kick.is_empty(): return
	if gap>tuning.foot_reach+radius:
		control_mode = "CHASE"
		return
	var run := Vector3(owner.velocity.x,0,owner.velocity.z)
	var aim: Vector3 = owner.get_ball_direction()
	var radial := offset.normalized()
	var flat := Vector3(velocity.x,0,velocity.z)
	var mode := "CARRY"
	var strength := tuning.foot_impulse
	var period := tuning.carry_interval
	var bias := Vector3.ZERO
	if owner.stop_requested>0 or (owner.sole_stopped and not owner.move_requested):
		mode = "STOP"
	elif run.dot(owner.body_facing)<-.25:
		mode = "PULL"
	elif not owner.move_requested:
		if flat.length()<.15 and gap<.82:
			control_mode = "SETTLE"
			return
		mode = "SETTLE"
	elif radial.angle_to(aim)>deg_to_rad(35):
		mode = "TURN"
		var tangent := Vector3(radial.z,0,-radial.x)*signf(radial.cross(aim).y)
		bias = tangent*1.4-radial*.4
		strength = 2.5
		period = .17
	elif owner.shielding or owner.close_control:
		mode = "SHIELD" if owner.shielding else "CLOSE"
		bias = aim*(.55 if gap<.53 else -.25)
		period = .18
	elif owner.sprinting and owner.long_touch:
		mode = "SPRINT"
		bias = aim*3.0
		strength = 5.2
		period = .36
	else:
		bias = aim*(1.3 if gap<.48 else .55 if gap<.69 else -.4)
	if owner.foot.begin(mode,aim,bias,strength,period): control_mode = mode

func _update_human_dribble(owner: Node3D, offset: Vector3, gap: float) -> void:
	# IOSoccer policy reference: gated directional actions and target-result
	# velocity; the actual socket owns contact. Never place/spring the ball at
	# a camera/body anchor or push it merely because ownership is set.
	var moving: bool = owner.move_requested and owner.stop_requested<=0
	var stopping: bool = not moving or owner.stop_requested>0
	# A committed pass/shot already owns the next real foot slot. Movement
	# release or a new direction must not cancel its buffer to auto-settle.
	# FootAction still expires or cancels it on authority/ownership changes.
	if owner.foot.has_buffer() and owner.foot.buffer.get("kind","") in ["KICK","NUDGE","CUT"]:
		owner.foot.ordinary_scheduler.reset_turn(owner,"queued_action_priority")
		return
	var scheduler=owner.foot.ordinary_scheduler
	var stable_aim:Vector3=scheduler.stable_direction(owner)
	if stable_aim.dot(owner.body_facing)<-.35:scheduler.reset_turn(owner,"backward_sole_control")
	else:scheduler.update_turn(owner,self,stable_aim)
	var changed_direction: bool = moving and owner.foot.direction.dot(stable_aim)<.75 and scheduler.turn_stage.is_empty()
	var keep_prepared_shoe:bool=DribbleRhythm.can_steer(owner,stable_aim)
	if changed_direction and not keep_prepared_shoe and owner.foot.continuous_control() and not owner.foot.hit and owner.foot.phase==FootballFootAction.Phase.PREPARE:
		owner.foot.cancel()
		touch_timer = 0.0
	if stopping and owner.foot.continuous_control() and not owner.foot.hit and owner.foot.phase!=FootballFootAction.Phase.CONTACT:
		owner.foot.cancel()
		touch_timer = 0.0
	if not owner.foot.idle() or owner.foot.has_buffer():
		if owner.is_human and owner.foot.planned_dribble() and moving:
			scheduler.consider(owner,self,stable_aim,"TURN" if changed_direction else "CLOSE",changed_direction)
		return
	if scheduler.turn_stage=="STEPS":return
	if not stopping and dribble_free_roll_remaining>0: return
	if not stopping and touch_timer>0 and not changed_direction: return
	if gap>tuning.foot_reach+radius:
		control_mode = "CHASE"
		return
	var flat := Vector3(velocity.x,0,velocity.z)
	if stopping:
		if flat.length()<.08:
			control_mode = "SETTLE"
			return
		if owner.foot.begin("STOP" if owner.stop_requested>0 else "SETTLE",owner.body_facing,Vector3.ZERO,0,.10): control_mode = "SETTLE"
		return
	var aim: Vector3 = scheduler.turn_incoming if scheduler.turn_stage=="BRAKE" else stable_aim
	var backward: bool = aim.dot(owner.body_facing)<-.35
	var lateral_axis:Vector3=owner.global_basis.x if owner.is_human else Vector3(-owner.body_facing.z,0,owner.body_facing.x)
	# Opposed high-speed carry brakes with one ordinary contact before the
	# released low-speed PULL takes over. No new action/permission type.
	var mode := "TURN" if scheduler.turn_stage=="CUT90" else "TURN" if scheduler.turn_stage=="EXIT" and absf(aim.dot(lateral_axis))>.35 else "CLOSE" if not scheduler.turn_stage.is_empty() or DribbleRhythm.braking_turn(owner,aim) else "PULL" if backward else "SHIELD" if owner.shielding else "TURN" if absf(aim.dot(lateral_axis))>.35 else "CLOSE"
	if backward:mode="PULL" # Retreat keeps the shoe above a ball in front of the body.
	var period := tuning.retreat_touch_period if backward else tuning.running_contact_interval if owner.sprinting else tuning.near_contact_interval
	var preparation: Dictionary = {}
	if mode in ["CLOSE","TURN","SHIELD"]:
		preparation = scheduler.consider(owner,self,aim,mode,changed_direction or not scheduler.turn_stage.is_empty())
		if bool(preparation.get("ready",false)) or preparation.get("reason","") in ["support_wait","recovery_wait","shoe_outside_next_window"]:
			preparation=scheduler.reserve_window(owner,self,aim,preparation,mode)
		preparation["turn_stage"]=scheduler.turn_stage
		scheduler.last_decision=preparation
		if not bool(preparation.get("ready",false)):
			control_mode = "FREE_ROLL" if preparation.get("reason","")=="roll_sufficient" else "PREPARE_SUPPORT"
			return
	# Direction is distinct from camera/stance heading. A/D selects an inside
	# or outside foot roll without demanding a turn of the camera/whole body.
	if owner.foot.begin(mode,aim,Vector3.ZERO,1.2,period,preparation): control_mode = mode

func close_touch_velocity(owner: Node3D, aim: Vector3, mode: String) -> Vector3:
	var run := Vector3(owner.velocity.x,0,owner.velocity.z)
	if mode in ["STOP","SETTLE"] or not owner.move_requested: return stopping_touch_velocity(owner)
	var offset := Vector3(position.x-owner.position.x,0,position.z-owner.position.z)
	var gap := offset.length()
	if mode=="PULL":
		# A sole roll follows the retreating player's actual pace. Its small
		# contact-only speed difference brings a forward ball near the hips;
		# it must not keep accelerating the ball behind the player's heels.
		var ahead := offset.dot(owner.body_facing)
		var coast_loss:float=FootballBallForces.rolling_deceleration_mps2(run.length(),profile)
		var relative_pull := clampf((ahead-tuning.retreat_front_distance)*2.5+coast_loss*.10,-.75,.65)
		# Bound the exit relative to the moving body; never roll past its front.
		relative_pull=minf(relative_pull,maxf(-.75,(ahead-.24)/.22))
		return run+aim*relative_pull
	if DribbleRhythm.enabled(owner) and mode in ["CLOSE","TURN","SHIELD"]:
		return DribbleRhythm.target_velocity(owner,self,aim)
	# A short touch gives a finite rolling result, rather than matching the
	# body's current velocity throughout the whole contact window. Outside
	# pushes lead further; an inside cut takes out some incoming crosswise roll.
	var outside: bool = owner.foot.surface=="OUTSIDE"
	var lead := (1.25 if outside else .85)+(.25 if owner.sprinting else 0.0)
	if owner.shielding: lead *= .70
	var outer := .65 if owner.sprinting else .50
	if gap>outer: lead = .10
	if owner.is_human and owner.foot.ordinary_scheduler.dominant_control_enabled and not owner.sprinting and run.length()<=2.10 and gap<=.65:
		# One contact compensates only the EXTRA low-speed turf loss over one
		# short control horizon. Free rolling/F7 coast and force limits stay as
		# released; do not follow the ball or bypass support recovery.
		var response: float = clampf(float(owner.foot.touch_plan.get("response_seconds",.035)),0.0,.035)
		var gain: float = 1.0-exp(-response/maxf(profile.receiver_relaxation_time_s,.001))
		var loss: float = profile.low_speed_roll_extra_mps2*.20
		lead += minf(.35,loss/maxf(gain,.001))
	var wished := tuning.sprint_ball_speed if owner.sprinting else tuning.shield_speed if owner.shielding else tuning.close_speed if owner.close_control else tuning.normal_ball_speed
	var along := maxf(0.0,run.dot(aim))
	if mode=="TURN" and run.length()>1.0 and run.normalized().dot(aim)<.75:
		along = maxf(along,run.length()*.65)
	var speed := clampf(along+lead,.65,wished+lead)
	var opposed_turn := mode=="TURN" and run.length()>1.0 and run.normalized().dot(aim)<-.60 and (outside or run.length()>3.0)
	if owner.foot.planned_dribble() and (outside and mode=="TURN" and run.length()>3.0 or opposed_turn):
		# Bound the rolling result by the existing next-touch spacing. This is
		# a constant-velocity root estimate, not a predicted valid leg pose.
		var horizon := maxf(owner.foot.interval,.001)
		var exit_limit := maxf(0.0,run.dot(aim)+(outer-gap)/horizon)
		var response := clampf(float(owner.foot.touch_plan.get("response_seconds",.035)),0.0,.035)
		var gain := 1.0-exp(-response/maxf(profile.receiver_relaxation_time_s,.001))
		var before_along := Vector3(velocity.x,0,velocity.z).dot(aim)
		var desired_limit := before_along+(exit_limit-before_along)/maxf(gain,.001)
		# Cushion the incoming roll while the actual person is still braking.
		# Zero exit speed is a finite result; no force follows it during free roll.
		speed = desired_limit if opposed_turn else minf(speed,maxf(.65,desired_limit))
	var incoming := run.slide(aim)*(.45 if outside else .25) if mode=="TURN" else Vector3.ZERO
	return aim*speed+incoming

func human_dribble_motion(owner: Node3D, intended: Vector3, maximum_speed: float) -> Vector3:
	# Move the PERSON after the rolling ball. Changing the input axis must not
	# project away all of its old speed and force a 5 -> .30 m/s target step.
	# The existing motor still supplies acceleration, braking and collision.
	if intended.length()<.05 or maximum_speed<=0: return Vector3.ZERO
	var aim := intended.normalized()
	if aim.dot(owner.body_facing)<-.35:
		# Move the body backwards while the sole pulls a ball kept in FRONT.
		# The outgoing ball is never positioned or accelerated from this motor path.
		var offset:Vector3=position-owner.position;offset.y=0
		var rolling:Vector3=velocity;rolling.y=0
		var front:float=offset.dot(owner.body_facing)
		# Normal input requests its full tier. Ease only as the real ball starts
		# falling beyond the forward reach, instead of following every speed dip.
		var limit:float=maxf(0.0,rolling.dot(aim)+(tuning.retreat_outer_distance-front)/tuning.retreat_prediction_seconds)
		var pace:float=minf(maximum_speed,limit)
		var lateral:Vector3=offset.slide(owner.body_facing)
		var correction:Vector3=lateral.limit_length(.12)*1.5
		return (aim*pace+correction).limit_length(maximum_speed)*minf(1.0,intended.length())
	if DribbleRhythm.enabled(owner):
		aim=owner.foot.ordinary_scheduler.stable_direction(owner)
		if owner.foot.has_buffer() or not owner.foot.idle() and not owner.foot.planned_dribble():owner.foot.ordinary_scheduler.reset_turn(owner,"motor_action_priority")
		if owner.foot.ordinary_scheduler.turn_stage in ["BRAKE","STEPS","EXIT","CUT90"]:
			return owner.foot.ordinary_scheduler.turn_motion(owner).limit_length(maximum_speed)
	if DribbleRhythm.enabled(owner):
		return DribbleRhythm.pace(owner,self,aim,maximum_speed)*minf(1.0,intended.length())
	var gap := Vector2(position.x-owner.position.x,position.z-owner.position.z).length()
	var rolling := Vector3(velocity.x,0,velocity.z)
	var run := Vector3(owner.velocity.x,0,owner.velocity.z)
	var working := .42 if owner.sprinting else .28
	var pace := clampf(rolling.length()+(gap-working)*4.0+.25,.30,maximum_speed)
	var dominant_for_motion:int=-1 if int(owner.get_meta("dominant_foot_side",1))<0 else 1
	var stance_right:Vector3=Vector3(-owner.body_facing.z,0,owner.body_facing.x)
	var cross_control:bool=owner.is_human and owner.foot.ordinary_scheduler.dominant_control_enabled and owner.foot.ordinary_scheduler.continuous_control_enabled and not owner.sprinting and run.length()<=2.10 and aim.dot(stance_right)*dominant_for_motion<-.5 and gap<.80 and (owner.foot.idle() or owner.foot.kind in ["CLOSE","TURN","SHIELD"])
	if cross_control:
		# Follow the actual rolling result into a small stance pocket. The
		# intended step remains visible even when body speed must ease to avoid
		# outrunning a ball on the dominant side; no ball force is introduced.
		var along:float=Vector3(position.x-owner.position.x,0,position.z-owner.position.z).dot(aim)
		var carry_reference:float=maxf(rolling.dot(aim),owner.foot.ordinary_scheduler.last_exit_velocity.dot(aim)*.65)
		pace=clampf(carry_reference+(along+.06)*2.0+.25,.08,maximum_speed)
	if run.length()>1.0 and run.normalized().dot(aim)<.55 and gap<.80:
		pace = maxf(pace,minf(maximum_speed,run.length()*.65))
	var offset := Vector3(position.x-owner.position.x,0,position.z-owner.position.z)
	var side_error := offset.slide(aim).length()
	var follow_weight := clampf((side_error-.20)/.35,0.0,.65)
	if offset.dot(aim)<-.12: follow_weight = maxf(follow_weight,.65)
	var approach := offset+rolling*.05
	var follow := approach.normalized()*pace if approach.length()>.05 else aim*pace
	var motion := (aim*pace).lerp(follow,follow_weight)
	var dominant := -1 if int(owner.get_meta("dominant_foot_side",1))<0 else 1
	var right := Vector3(-owner.body_facing.z,0,owner.body_facing.x)
	if owner.is_human and owner.foot.ordinary_scheduler.dominant_control_enabled and not owner.sprinting and run.length()<=2.10 and aim.dot(right)*dominant<-.5 and gap<.80:
		# A soft stance target moves only the PERSON using the existing motor.
		# Near the dominant hip projection, the inside shoe can meet the ball
		# after the opposite support step. No ball anchor/force or bone writes.
		var stance_error: Vector3 = offset-right*(.06*dominant)-owner.body_facing*.28
		var weight := clampf((stance_error.length()-.06)/.35,0.0,.55)
		var adjustment: Vector3 = stance_error.normalized()*pace if stance_error.length()>.06 else aim*pace
		# Keep the requested lateral motion immediate even during repositioning.
		if adjustment.dot(aim)<0: adjustment=adjustment.slide(aim)+aim*pace*.35
		motion = motion.lerp(adjustment,weight)
	if cross_control:
		var forward_error:float=offset.dot(owner.body_facing)-.28
		motion=aim*pace+owner.body_facing*clampf(forward_error*2.0,-.35,.35)
	return motion.limit_length(maximum_speed)*minf(1.0,intended.length())

func commit_dribble_result(owner: Node3D, desired: Vector3, contact_point: Vector3, response_seconds: float, period: float) -> Dictionary:
	# One bounded assisted result at the first real shoe contact. The response
	# budget matches the old 35ms cushion, without following the ball afterward.
	if not desired.is_finite() or not contact_point.is_finite(): return {"accepted":false}
	var before := velocity
	var duration := clampf(response_seconds,0.0,.035)
	var gain := 1.0-exp(-duration/maxf(profile.receiver_relaxation_time_s,.001))
	var impulse := ((desired-before)*mass_kg*gain).limit_length(profile.receiver_force_budget_n*duration)
	if not apply_impulse_ns(impulse): return {"accepted":false}
	if profile.receiver_sync_ground_roll and grounded:
		var axial := spin_rads.y*exp(-profile.receiver_spin_brake_per_second*duration)
		spin_rads = Vector3.UP.cross(Vector3(velocity.x,0,velocity.z))/radius+Vector3.UP*axial
	else: spin_rads *= exp(-profile.receiver_spin_brake_per_second*duration)
	dribble_free_roll_remaining = minf(.060,period*.35)
	return {"accepted":true,"impulse_ns":impulse,"exit_velocity":velocity,"response_seconds":duration}

func stopping_touch_velocity(owner: Node3D) -> Vector3:
	var run := Vector3(owner.velocity.x,0,owner.velocity.z)
	return run*.25 if run.length()>.25 else Vector3.ZERO

var last_lower_contact_frame := -100

func locks_lower_contact(owner: Node3D) -> bool:
	# One action-authoritative contact per player, also during its brief
	# cooldown: don't stack the moving shoe/capsule collision onto a foot kick.
	return carrier==owner or (owner.foot!=null and not owner.foot.idle()) or (last_contact_actor==owner and touch_age<.085)

func apply_foot_contact(owner: Node3D, desired: Vector3, delta_speed_limit: float, period: float, mode: String, contact_point: Vector3) -> bool:
	var before := velocity
	var target := Vector3(desired.x,0,desired.z)
	var change := (target-Vector3(velocity.x,0,velocity.z)).limit_length(delta_speed_limit)
	if not apply_impulse_ns(change*mass_kg,contact_point-position): return false
	record_touch(owner,before,period,mode,contact_point)
	return true

func record_touch(owner: Node3D, before: Vector3, period: float, mode: String, contact_point: Vector3, consume_cooldown := true) -> void:
	last_contact_actor = owner
	last_touch_team = owner.team
	if consume_cooldown:
		# The timer schedules the next swing; its windup is already part of the
		# first-touch interval. Repeated samples of this foot consume it once.
		touch_timer = maxf(0.0,period-owner.foot.windup) if owner.foot.continuous_control() else period
	touch_age = 0
	touch_count += 1
	control_mode = mode
	last_contact_position = position
	last_contact_delta = velocity-before
	last_foot_position = contact_point

func reception_ready(owner: Node3D) -> bool:
	# Shared readiness after an actual shoe cushion, distinct from mere contact.
	# This reads geometry/motion and supplies no impulse or transform correction.
	var offset := Vector3(position.x-owner.position.x,0,position.z-owner.position.z)
	var relative := Vector3(velocity.x-owner.velocity.x,0,velocity.z-owner.velocity.z)
	var ball_speed := Vector2(velocity.x,velocity.z).length()
	var speed_threshold := 1.8 if receive_ab_legacy else clampf(1.8+ball_speed*.25,1.8,4.5)
	return position.y<.30 and offset.length()>=.18 and offset.length()<(1.10 if control_mode=="RECEIVE" or owner.foot.kind=="RECEIVE" else .95) and offset.normalized().dot(owner.facing)>-.45 and relative.length()<speed_threshold

func can_kick(owner: Node3D) -> bool:
	var offset := position-owner.position
	offset.y = 0
	return (carrier==owner or match_controller.is_restart_taker(owner)) and position.y<.46 and offset.length()<1.02 and offset.dot(owner.facing)>-.25 and match_controller.can_reach_ball(owner)

func can_pass(owner:Node3D)->bool:
	var offset:Vector3=position-owner.position;offset.y=0
	return (carrier==owner or match_controller.is_restart_taker(owner)) and position.y<.46 and offset.length()<1.02 and offset.dot(owner.body_facing)>-.44 and match_controller.can_reach_ball(owner)

func stop_at_foot(owner: Node3D) -> bool:
	if carrier!=owner or not can_kick(owner): return false
	owner.stop_requested = .38
	return owner.foot.request_stop()

func push_free(owner: Node3D) -> void:
	if owner.is_human: owner.big_chase_remaining = tuning.big_chase_seconds
	previous_carrier = owner
	last_dribbler = owner
	carrier = null
	pickup_block = .25
	push_age = .65
	control_mode = "PUSH"
	match_controller.sync_input_context()

func detach(reason := "") -> void:
	if is_instance_valid(carrier):carrier.foot.ordinary_scheduler.reset_turn(carrier,"possession_lost")
	previous_carrier = carrier
	carrier = null
	pickup_block = .12
	control_mode = "LOOSE"
	match_controller.sync_input_context()
	if reason!="" and is_instance_valid(previous_carrier) and previous_carrier.is_human: match_controller.message(reason,1.4)

func take(owner: Node3D) -> void:
	if is_instance_valid(carrier) and carrier!=owner:carrier.foot.ordinary_scheduler.reset_turn(carrier,"possession_transferred")
	# A control claim follows confirmed shoe contact; this changes no transform.
	carrier = owner
	last_touch_team = owner.team
	possession_age = 0
	push_age = 0
	match_controller.sync_input_context()

func knock_free(direction: Vector3) -> void:
	detach()
	apply_impulse_ns(direction.normalized()*tuning.tackle_poke*mass_kg)
	pickup_block = .18

func reset(at: Vector3) -> void:
	clear_control()
	velocity = Vector3.ZERO
	spin_rads = Vector3.ZERO
	position = Vector3(at.x,radius+.003 if at.y<radius else at.y,at.z)
	previous_position = position
	reset_physics_interpolation()
	control_mode = "SETTLE"
