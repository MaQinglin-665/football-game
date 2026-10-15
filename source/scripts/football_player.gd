extends MovementController
const FootScript := preload("res://addons/publisher_adapters/ground_pass_scope.gd")
const PoseState02 := preload("res://addons/football_motion/pose_state_02.gd")
const CharacterScene := preload("res://addons/football_character/football_character.tscn")
const PoseScript := preload("res://addons/football_ground_pass/ground_pass_avatar.gd")
const LowerContacts := preload("res://scripts/football_lower_contacts.gd")
const ViewEyeComfort045 := preload("res://addons/football_motion/view_eye_comfort_045.gd")
var team := 0
var role := "attacking_midfielder"
var jersey := 10
var lane := .55
var is_goalkeeper := false
var is_human := true
var shielding := false
var close_control := false
var shield_side := 1.0
var facing := Vector3.FORWARD
var body_facing := Vector3.FORWARD
var ball_direction := Vector3.FORWARD
var turn_hint := 1.0
var stamina := 100.0
var sprint_locked := false
var tackle_cooldown := 0.0
var action_cooldown := 0.0
var stop_requested := 0.0
var move_requested := false
var sole_stopped := false
var sprinting := false
var sprint_release_carry_remaining := 0.0
var gather_after_sprint := false
var long_touch := false
var match_controller: Node
var interaction: Node
var foot: FootballFootAction
var avatar: Node3D
var locomotion := "idle"
var semantic_motion := Vector3.ZERO
var semantic_move_style := "run"
var movement_tier := "walk_jog"
var shift_policy: Dictionary = {}
var big_chase_remaining := 0.0
var semantic_policies: Dictionary = {}
var previous_yaw := 0.0
var pending_pose_delta := 0.0
var pose_updates_enabled := true # External profiler only; normal play stays true.
var motion_acceleration := Vector3.ZERO
var dribble_balance=preload("res://scripts/dribble_balance.gd").new()
var last_motion_velocity := Vector3.ZERO
var _eye_previous:=Vector3(0,1.6,-.11)
var _eye_current:=Vector3(0,1.6,-.11)
var _eye_tick:=-1
var _eye_root:=Vector3.ZERO
var _eye_horizontal:=Vector3.ZERO
var camera_bob_enabled:=true
var hip_yaw:=0.0
var call_age:=2.0
var call_weight:=0.0
var _fp_torso_materials:Array[ShaderMaterial]=[]
var _fp_arm_nodes:Array[MeshInstance3D]=[]
var _fp_cut_previous:=-1.0
var _view_head_bone := -1
var _view_comfort045=ViewEyeComfort045.new()
var first_touch_timing:=FirstTouchTiming.new() # R004
var human_motion:=HumanMotion.new() # R004 human locomotion curve
var human_motion_enabled:=true
## R004 camera comfort constants
const CAMERA_BASE_FOV:=90.0
const SPRINT_FOV_MULTIPLIER:=1.06
const SPRINT_FOV_RATE:=4.0
const BOB_LIMIT_M:=0.015
const BOB_SPRINT_SCALE:=0.5
const BOB_BASELINE_RATE:=2.0
const DRIBBLE_DOWN_BIAS_DEG:=6.0 # 5–8°, only while the human owns the ball
const DOWN_BIAS_RATE:=3.0
var base_fov:=CAMERA_BASE_FOV
var _bob_baseline:=-1.0
var _down_bias:=0.0
static func limit_bob(visual_y:float,baseline:float,sprint:bool)->float:
	var limit:=BOB_LIMIT_M*(BOB_SPRINT_SCALE if sprint else 1.0)
	return baseline+clampf(visual_y-baseline,-limit,limit)
var first_touch_clock_override:=-1.0 # tests only; <0 uses active-play clock
var first_touch_clock:=0.0
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera

func _ready() -> void:
	for child in get_children():
		if child is CollisionShape3D:
			remove_child(child)
			child.queue_free()
	super._ready()
	auto_step = false
	process_physics_priority = -40
	$Sprint.set_physics_process(false)
	head.position = Vector3(0,1.60,-.11)
	camera.position = Vector3.ZERO # Fixed body-frame eye; pitch rotates only the view.
	camera.fov = CAMERA_BASE_FOV
	camera.top_level=true
	camera.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	foot = FootScript.new(self,match_controller)
	foot.ground_pass_enabled = true # Experimental pass/defence batch03; existing contact owns release.
	avatar = CharacterScene.instantiate()
	avatar.set_script(PoseScript)
	avatar.name = "CharacterVisual"
	add_child(avatar)
	avatar.setup(team,jersey,true)
	for mesh in avatar.mesh_nodes:
		if String(mesh.name).begins_with("RobotArm"):_fp_arm_nodes.append(mesh)
		if String(mesh.name)=="BodyCore":
			for surface in mesh.mesh.get_surface_count():
				var material=mesh.get_active_material(surface)
				if material is ShaderMaterial:
					var own:ShaderMaterial=material.duplicate()
					mesh.set_surface_override_material(surface,own);_fp_torso_materials.append(own)
	var lower_contacts := LowerContacts.new()
	lower_contacts.actor = self
	add_child(lower_contacts)
	reset_view(0.0)
	refresh_pose(0)

func _physics_process(delta: float) -> void:
	motion_acceleration = ((velocity-last_motion_velocity)/maxf(delta,.000001)).limit_length(32.0)
	last_motion_velocity = velocity
	var cfg: FootballControlTuning = match_controller.tuning
	var owned: bool = match_controller.ball.carrier == self
	var flat_speed:float=Vector2(velocity.x,velocity.z).length()
	var body_target_yaw:float=rotation.y
	if controller_v07_enabled:
		body_target_yaw=preload("res://scripts/player_body_direction.gd").target(rotation.y,semantic_motion,velocity,owned,semantic_policies.get("pressure",false))
		if owned and (not foot.ordinary_scheduler.follow_step.pending.is_empty() or foot.ordinary_scheduler.follow_step.edge_recovery):
			var approach:Vector3=match_controller.ball.position-position;approach.y=0
			if approach.length()>.24:body_target_yaw=atan2(-approach.x,-approach.z)
		if owned and gather_after_sprint and semantic_motion.length()>.05:
			var to_ball:Vector3=match_controller.ball.position-position;to_ball.y=0
			if to_ball.length()>.30:
				var approach_yaw:float=atan2(-to_ball.x,-to_ball.z)
				body_target_yaw=approach_yaw+clampf(angle_difference(approach_yaw,body_target_yaw),-.40,.40)
	var pressure:RefCounted=match_controller.input_bridge.pressure
	if pressure.active:body_target_yaw=atan2(-pressure.direction.x,-pressure.direction.z)
	if foot.kind=="TACKLE" and not foot.idle() and foot.phase!=foot.Phase.RECOVER and not bool(foot.touch_plan.get("automatic",false)):
		body_target_yaw=atan2(-foot.direction.x,-foot.direction.z)
	var view_delta:float=angle_difference(hip_yaw,body_target_yaw)
	var follow:float=smoothstep(.12,.60,absf(view_delta))
	var turn_rate:float=preload("res://scripts/movement_inertia.gd").yaw_rate(flat_speed)
	if controller_v07_enabled:hip_yaw=movement_motor.turn_body(hip_yaw,body_target_yaw,flat_speed,delta)
	else:hip_yaw+=clampf(view_delta,-turn_rate*delta*follow,turn_rate*delta*follow)
	facing = Vector3(-sin(hip_yaw),0,-cos(hip_yaw))
	call_age+=delta
	var call_target:float=smoothstep(0,.16,call_age)*(1-smoothstep(.70,1.05,call_age))
	if not foot.idle() or not input_enabled:
		call_age=maxf(call_age,.85);call_target=0
	call_weight=move_toward(call_weight,call_target,delta*9.0)
	var yaw_change := angle_difference(previous_yaw,rotation.y)
	if absf(yaw_change)>.0001: turn_hint = signf(yaw_change)
	previous_yaw = rotation.y
	var intended := semantic_motion if input_enabled else Vector3.ZERO
	if input_enabled: intended = match_controller.constrained_human_intent(intended)
	move_requested = intended.length()>.05
	var backwards := intended.dot(-global_basis.z if controller_v07_enabled else facing)<-.2
	ball_direction = intended.normalized() if move_requested else facing
	if match_controller.phase==match_controller.Phase.PLAY:first_touch_clock+=delta
	first_touch_timing.observe(intended if move_requested and input_enabled else Vector3.ZERO,first_touch_clock if first_touch_clock_override<0 else first_touch_clock_override)
	shielding = input_enabled and owned and semantic_policies.get("shield",false) and stamina>2
	close_control = input_enabled and semantic_policies.get("close_control",false)
	stop_requested = maxf(0,stop_requested-delta)
	if move_requested and stop_requested<=0: sole_stopped = false
	big_chase_remaining = maxf(0,big_chase_remaining-delta)
	var was_sprinting:bool=sprinting
	sprinting = input_enabled and movement_tier=="run" and can_sprint_for_match() and not backwards
	sprint_release_carry_remaining=maxf(0,sprint_release_carry_remaining-delta)
	if was_sprinting and not sprinting and owned:sprint_release_carry_remaining=.40
	if was_sprinting and movement_tier!="run" and owned:gather_after_sprint=true
	if not owned or sprinting or not input_enabled or shielding or stop_requested>0:gather_after_sprint=false
	body_facing = facing
	if shielding and absf(intended.dot(global_basis.x))>.1: shield_side = signf(intended.dot(global_basis.x))
	if not uses_shared_movement() or is_instance_valid(interaction) and not interaction.accepts_mobility_input():_apply_base_movement(intended,owned,backwards,delta)
	tackle_cooldown = maxf(0,tackle_cooldown-delta)
	action_cooldown = maxf(0,action_cooldown-delta)
	dribble_balance.step(self,delta,owned)
	locomotion = "idle" if flat_speed<.12 else "retreat" if backwards else "shield" if shielding else "jockey" if semantic_policies.get("pressure",false) else "dribble" if owned and move_requested else "sprint" if sprinting else "run" if velocity.length()>3.5 else "walk" if velocity.length()>.12 else "idle"
	pending_pose_delta += delta

func uses_shared_movement()->bool:
	return false

func _apply_base_movement(intended:Vector3,owned:bool,backwards:bool,delta:float)->void:
	var cfg:FootballControlTuning=match_controller.tuning
	var flat_speed:=Vector2(velocity.x,velocity.z).length()
	speed = cfg.sprint_ball_speed if owned and sprinting else cfg.normal_ball_speed if owned else (cfg.big_chase_speed if big_chase_remaining>0 else cfg.running_move_speed) if sprinting else cfg.normal_move_speed
	if controller_v07_enabled:
		movement_motor.controlled=owned
		if not owned:speed=movement_motor.sprint_speed if sprinting else movement_motor.jog_speed
	if shielding: speed = cfg.shield_speed
	elif close_control or semantic_move_style=="walk": speed = cfg.close_speed if owned or not controller_v07_enabled else movement_motor.walk_speed
	if backwards:
		var retreat:float=cfg.retreat_close_speed if close_control or shielding or semantic_move_style=="walk" else cfg.retreat_fast_speed if movement_tier=="run" and can_sprint_for_match() else cfg.retreat_speed
		speed=minf(speed,retreat if owned else 3.1)
	# On sprint release let the next reachable touch brake the rolling ball.
	# Follow only forward input and a recent free roll; never alter ball velocity
	# here, extend reach, override a stop/reversal, or retain an acceleration latch.
	if owned and sprint_release_carry_remaining>0 and stop_requested<=0 and not shielding and intended.length()>.05 and intended.normalized().dot(body_facing)>.7 and (foot.idle() or foot.planned_dribble()):
		var roll:Vector3=match_controller.ball.velocity;roll.y=0
		var offset:Vector3=match_controller.ball.position-position;offset.y=0
		var aim:Vector3=intended.normalized()
		if offset.dot(aim)>.2 and offset.slide(aim).length()<.45 and offset.length()<1.15:
			speed=maxf(speed,minf(Vector2(velocity.x,velocity.z).length(),roll.dot(aim)))
	if owned and stop_requested>0: speed = 0
	if owned:
		var gap: float = match_controller.flat_distance(match_controller.ball.position,position)
		if gap>.80 and not preload("res://scripts/dribble_rhythm.gd").may_chase(self,match_controller.ball,intended): speed = minf(speed,1.6)
	speed = minf(speed,foot.movement_cap())
	if is_instance_valid(interaction): speed = minf(speed,interaction.movement_cap())
	var motion := intended*speed
	if owned and move_requested and stop_requested<=0 and foot.movement_cap()>1.4:
		motion = match_controller.ball.human_dribble_motion(self,intended,speed)
	set_meta("motor_guard",not owned and semantic_policies.get("pressure",false) and not sprinting)
	var sprint_value := 1.0 if sprinting else 0.0
	if sprint_release_carry_remaining>0 and owned and not sprinting:
		sprint_value=clampf((motion.length()-profile.jog_speed_mps)/maxf(.01,profile.sprint_speed_mps-profile.jog_speed_mps),0,1)
	set_move_intent(motion/lerpf(profile.jog_speed_mps,profile.sprint_speed_mps,sprint_value),sprint_value)
	var energy:Dictionary=$Sprint.update_state(sprinting,flat_speed,shielding,stamina,sprint_locked,not is_instance_valid(interaction) or interaction.accepts_mobility_input(),delta)
	stamina=energy.stamina;sprint_locked=energy.locked

func refresh_pose(delta := 0.0) -> void:
	if not is_instance_valid(avatar): return
	if not pose_updates_enabled:
		pending_pose_delta = 0.0
		return
	delta += pending_pose_delta
	pending_pose_delta = 0.0
	if foot != null and not foot.idle(): avatar.set_foot_action(foot.pose_request())
	else: avatar.clear_foot_action()
	var pose_state := {"velocity":velocity,"acceleration":motion_acceleration,"move_direction":semantic_motion,"forward":interaction.pose_forward(body_facing) if is_instance_valid(interaction) else body_facing,"grounded":interaction.pose_grounded() if is_instance_valid(interaction) else position.y<.025,"locomotion":locomotion,"interaction":interaction.pose_state() if is_instance_valid(interaction) else {}}
	if controller_v07_enabled:
		movement_motor.observe_velocity(velocity)
		pose_state["controller_motion"]=movement_motor.animation_state()
	var owned: bool = is_instance_valid(match_controller.ball) and match_controller.ball.carrier == self
	var active_kind := String(foot.kind) if foot != null and not foot.idle() else ""
	if avatar.has_method("set_lateral_support_request09"):
		var dominant:int=-1 if int(get_meta("dominant_foot_side",1))<0 else 1
		var right:Vector3=Vector3(-body_facing.z,0,body_facing.x)
		var request_active:bool=is_human and owned and move_requested and stop_requested<=0 and not sprinting and Vector2(velocity.x,velocity.z).length()<=2.10 and get_ball_direction().dot(right)*dominant<-.5 and foot.ordinary_scheduler.dominant_control_enabled and foot.ordinary_scheduler.continuous_control_enabled and (foot.idle() or (active_kind in ["CLOSE","TURN","SHIELD"] and foot.side==dominant and foot.surface=="INSIDE"))
		# Set the intent before this complete pose update; the scheduler only
		# consumes its completed support_step LANDED episode afterward.
		avatar.set_lateral_support_request09({"active":request_active,"dominant_side":dominant,"move_direction":get_ball_direction(),"after_touch_episode":foot.ordinary_scheduler.consumed_support_episode})
	var tier := PoseState02.control_tier(shift_policy,owned,close_control,shielding,active_kind,big_chase_remaining)
	var world_step: int = match_controller.physics_world.step_serial if is_instance_valid(match_controller.physics_world) else -1
	avatar.update_pose(delta,PoseState02.stamp(pose_state,Engine.get_physics_frames(),tier,world_step))
	_refresh_view_anchor(delta)
	if is_instance_valid(interaction): interaction.sync_head_shape()

func _refresh_view_anchor(delta:float=0.0) -> void:
	# The existing gait/lean moves the torso and head. Keep the view origin
	# attached to that animated head, with a fixed body-frame eye offset;
	# existing Head input alone still owns the camera rotation.
	if not is_instance_valid(avatar) or not is_instance_valid(avatar.visual): return
	if _view_head_bone<0: _view_head_bone=avatar.skeleton.find_bone("head")
	if _view_head_bone<0: return
	var head_world: Vector3=(avatar.skeleton.global_transform*avatar.skeleton.get_bone_global_pose(_view_head_bone)).origin
	head.global_position = head_world+avatar.visual.global_basis*Vector3(0,.06,-.20)
	# The Head node remains the exact physical body anchor: sync_head_shape
	# below still sees that position. Only its visual Camera child compensates
	# the immediate support-safe sink, without delaying any collision or IK.
	var raw_eye:Vector3=head.global_position
	var visual_y:float=_view_comfort045.update(raw_eye.y-global_position.y,maxf(delta,0),Engine.get_physics_frames())
	var tick:int=Engine.get_physics_frames()
	# Follow the real forward lean rather than leaving the eye above the hips.
	# Filter lateral gait sway, keep rotation independent, and reuse the one display interpolation.
	var body_forward:Vector3=-avatar.visual.global_basis.z
	body_forward.y=0;body_forward=body_forward.normalized()
	var body_right:=Vector3(-body_forward.z,0,body_forward.x)
	var relative_eye:Vector3=raw_eye-global_position
	var horizontal:Vector3=body_forward*clampf(relative_eye.dot(body_forward),.16,.48)+body_right*clampf(relative_eye.dot(body_right),-.025,.025)
	if _eye_tick<0 or global_position.distance_squared_to(_eye_root)>1.0:
		_eye_horizontal=horizontal
	elif tick!=_eye_tick and delta>0:
		_eye_horizontal=_eye_horizontal.lerp(horizontal,1.0-exp(-18.0*minf(delta,.05)))
	# R004: bob = deviation from a slow baseline, clamped to 1.5 cm (half while sprinting).
	if _bob_baseline<0:_bob_baseline=visual_y
	_bob_baseline=lerpf(_bob_baseline,visual_y,1.0-exp(-BOB_BASELINE_RATE*maxf(delta,0)))
	visual_y=limit_bob(visual_y,_bob_baseline,sprinting)
	var eye:Vector3=_eye_horizontal+Vector3(0,visual_y if camera_bob_enabled else 1.60,0)
	if _eye_tick<0 or global_position.distance_squared_to(_eye_root)>1.0:
		_eye_previous=eye;_eye_current=eye;reset_physics_interpolation()
	elif tick!=_eye_tick:_eye_previous=_eye_current
	_eye_current=eye;_eye_tick=tick;_eye_root=global_position
	# Physics head collider above remains exact. Only the rendered eye is interpolated.

func _process(_delta:float)->void:
	if _eye_tick<0:return
	var alpha:float=Engine.get_physics_interpolation_fraction()
	camera.global_position=get_global_transform_interpolated().origin+_eye_previous.lerp(_eye_current,alpha)
	# No smoothing or physics interpolation on mouse rotation.
	camera.global_basis=head.global_basis
	# R004: small automatic down-bias only while dribbling; sprint FOV kick.
	var owns:bool=is_instance_valid(match_controller) and match_controller.ball.carrier==self
	_down_bias=lerpf(_down_bias,deg_to_rad(DRIBBLE_DOWN_BIAS_DEG) if owns else 0.0,1.0-exp(-DOWN_BIAS_RATE*_delta))
	if absf(_down_bias)>.0001:camera.global_basis=camera.global_basis*Basis(Vector3.RIGHT,-_down_bias)
	camera.fov=lerpf(camera.fov,base_fov*(SPRINT_FOV_MULTIPLIER if sprinting else 1.0),clampf(_delta*SPRINT_FOV_RATE,0,1))
	# Turning behind must not expose the inside of the first-person torso subset.
	# This trims the first-person subset; anatomy, collision and contacts stay live.
	var look_error:float=absf(angle_difference(avatar.visual.global_rotation.y,rotation.y)) if camera.current else 0.0
	var cut:float=lerpf(2.0,1.06,smoothstep(deg_to_rad(45),deg_to_rad(90),look_error))
	if absf(cut-_fp_cut_previous)>.002:
		for material in _fp_torso_materials:material.set_shader_parameter("fp_torso_cut",cut)
		_fp_cut_previous=cut
	for mesh in _fp_arm_nodes:mesh.visible=look_error<deg_to_rad(100)

func get_view_comfort_debug045()->Dictionary:
	return _view_comfort045.debug()

func advance_motor(dt: float) -> void:
	if is_instance_valid(interaction) and interaction.override_motor(dt):
		_apply_origin_ground_support(dt)
		return
	super.advance_motor(dt)

func observe_interaction_body_collision(other: CharacterBody3D, normal: Vector3, impulse: Vector3, point: Vector3, own_shape: Object, other_shape: Object) -> void:
	if is_instance_valid(interaction): interaction.observe_body_collision(other,normal,impulse,point,own_shape,other_shape)

func resolve_interaction_ball_contact(ball_body: FootballPhysicsBall, point: Vector3) -> bool:
	return is_instance_valid(interaction) and interaction.resolve_ball_collision(ball_body,point)

func interaction_vertical_bounds() -> Vector2:
	if is_instance_valid(interaction): return interaction.vertical_bounds()
	return Vector2(global_position.y,global_position.y+profile.player_height_m)

func refresh_legs() -> void:
	refresh_pose(0)

func set_semantic_movement(motion: Vector3, style: String) -> void:
	semantic_motion = motion.limit_length(1)
	semantic_move_style = style

func set_shift_policy(policy: Dictionary) -> void:
	shift_policy = policy.duplicate(true)
	movement_tier = String(policy.get("tier","walk_jog"))

func set_semantic_policy(action: String, enabled: bool) -> void:
	if action=="push_ball": return # Hold Shift is never an automatic big touch.
	semantic_policies[action] = enabled

func get_ball_direction() -> Vector3:
	return ball_direction

func can_sprint_for_match() -> bool:
	return not sprint_locked and stamina>1 and not semantic_policies.get("shield",false) and not semantic_policies.get("close_control",false)

func turn_view(yaw: float) -> void:
	rotation.y = yaw
	head.rot.y = yaw

func reset_view(yaw: float) -> void:
	human_motion.reset()
	if is_instance_valid(movement_motor):movement_motor.reset()
	_bob_baseline=-1.0;_down_bias=0.0
	_eye_tick=-1
	hip_yaw=yaw
	call_age=2.0;call_weight=0.0
	rotation.y = yaw
	head.rot = Vector3(deg_to_rad(-42.0),yaw,0)
	head.rotation.x = head.rot.x
	facing = -global_basis.z
	body_facing = facing
	ball_direction = facing
	previous_yaw = yaw
	reset_physics_interpolation()

func set_match_active(active: bool) -> void:
	input_enabled = active
	head.enabled = active
	if not active:
		semantic_motion = Vector3.ZERO
		semantic_policies.clear()
		set_move_intent(Vector3.ZERO)
		foot.cancel()

func request_call_gesture()->void:
	if call_age>=1.30:call_age=0.0

func kick_touch(_at: Vector3, _side: float, _mode: String) -> void:
	refresh_pose()

func kick(_strength := .8) -> void:
	refresh_pose()
