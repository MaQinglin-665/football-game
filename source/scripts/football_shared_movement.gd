extends RefCounted
const DribbleRhythm := preload("res://scripts/dribble_rhythm.gd")
## Shared movement/ordinary-close intent policy only. No World or foot impulses.
## Input/tactics choose commands; identical command and numeric state => result.
static func resolve(command: Dictionary, state: Dictionary, cfg: Variant, delta: float) -> Dictionary:
	var enabled: bool = bool(command.get("enabled",false))
	var move: Vector3 = command.get("move",Vector3.ZERO) if enabled else Vector3.ZERO
	move.y = 0
	move = move.limit_length(1.0)
	var facing: Vector3 = state.get("facing",Vector3.FORWARD)
	var owned: bool = bool(state.get("owned",false))
	var stamina: float = float(state.get("stamina",100.0))
	var locked: bool = bool(state.get("sprint_locked",false))
	var backwards: bool = move.dot(state.get("movement_facing",facing))<-.2
	var close: bool = enabled and bool(command.get("close_control",false))
	var shield: bool = enabled and owned and bool(command.get("shield",false)) and stamina>2
	var sprint: bool = enabled and command.get("tier","walk_jog")=="run" and not locked and stamina>1 and not shield and not close and not backwards
	var speed: float = cfg.sprint_ball_speed if owned and sprint else cfg.normal_ball_speed if owned else (cfg.big_chase_speed if state.get("big_chase_remaining",0.0)>0 else cfg.running_move_speed) if sprint else cfg.normal_move_speed
	if shield: speed = cfg.shield_speed
	elif close or command.get("style","run")=="walk": speed = cfg.close_speed
	if close and not shield:speed=maxf(speed,float(command.get("steady_control_speed",0.0)))
	# A finite controlled setup tracks the ball; ordinary CLOSE is still slow.
	var setup_tracking: bool = enabled and owned and not shield and command.has("prepared_motion") and bool(command.get("control_setup_tracking",false))
	if setup_tracking: speed = maxf(speed,(command.prepared_motion as Vector3).length())
	if backwards and not bool(command.get("receiving",false)):
		var retreat:float=cfg.retreat_close_speed if close or shield or command.get("style","run")=="walk" else cfg.retreat_fast_speed if command.get("tier","")=="run" and not locked and stamina>1 else cfg.retreat_speed
		speed=minf(speed,retreat if owned else 3.1)
	if owned and float(state.get("stop_requested",0.0))>0: speed = 0
	if owned and state.has("turn_chase_brake"):
		speed=lerpf(speed,minf(speed,1.6),float(state.turn_chase_brake))
	elif owned and float(state.get("gap",0.0))>.80 and not setup_tracking and not bool(state.get("free_ball_chase",false)): speed = minf(speed,1.6)
	# Preserve existing incoming momentum only until a real braking touch.
	# Apply action/interaction and explicit requested pace caps AFTER this budget.
	speed = maxf(speed,float(state.get("incoming_carry_speed",0.0)))
	speed = minf(speed,float(state.get("foot_cap",100.0)))
	var requested: float = float(command.get("requested_pace",-1.0))
	if requested>=0: speed = minf(speed,requested)
	var velocity: Vector3 = state.get("velocity",Vector3.ZERO)
	if shield: stamina = maxf(0,stamina-delta*4)
	elif sprint and velocity.length()>5.5: stamina = maxf(0,stamina-delta*15*float(state.get("endurance",1.0)))
	else: stamina = minf(100,stamina+delta*12)
	if stamina<2: locked = true
	elif stamina>26: locked = false
	return {"move":move,"speed":speed,"motion":move*speed,"move_requested":move.length()>.05,"backwards":backwards,"close_control":close,"shield":shield,"sprint":sprint,"stamina":stamina,"sprint_locked":locked,"ball_direction":move.normalized() if move.length()>.05 else facing}

static func apply(actor: Node3D, game: Node, command: Dictionary, before: Dictionary, delta: float) -> Dictionary:
	var owned: bool = game.ball.carrier==actor
	var state := {"facing":actor.facing,"owned":owned,"stamina":before.stamina,"sprint_locked":before.sprint_locked,"velocity":actor.velocity,"gap":game.flat_distance(game.ball.position,actor.position),"foot_cap":actor.foot.movement_cap(),"stop_requested":actor.stop_requested,"big_chase_remaining":actor.big_chase_remaining}
	if actor.is_human and actor.get("controller_v07_enabled")==true:state["movement_facing"]=-actor.global_basis.z
	if actor.is_human and actor.has_method("interaction_vertical_bounds") and is_instance_valid(actor.interaction):
		state.foot_cap = minf(float(state.foot_cap),actor.interaction.movement_cap())
	# Player ordinary carry only; reserved reception/pass motion keeps its caps.
	state["free_ball_chase"]=not command.has("prepared_motion") and DribbleRhythm.may_chase(actor,game.ball,command.get("move",Vector3.ZERO))
	if not command.has("prepared_motion"):
		var turn_brake:float=DribbleRhythm.turn_chase_brake(actor,game.ball,command.get("move",Vector3.ZERO),bool(state.free_ball_chase))
		if turn_brake>=0:state["turn_chase_brake"]=turn_brake
	var scheduler=actor.foot.ordinary_scheduler
	var incoming_carry:bool=not command.has("prepared_motion") and owned and bool(command.get("enabled",false)) and not bool(command.get("shield",false)) and not bool(command.get("close_control",false)) and command.get("style","run")!="walk" and scheduler.keep_incoming042(actor,command.get("move",Vector3.ZERO))
	if incoming_carry:state["incoming_carry_speed"]=Vector2(actor.velocity.x,actor.velocity.z).length()
	state.endurance=preload("res://scripts/player_abilities.gd").value(actor,"endurance")
	var human_v07:bool=actor.is_human and actor.get("controller_v07_enabled")==true
	var cfg:Variant=actor.controller_tuning(game.tuning) if human_v07 else game.tuning
	var result := resolve(command,state,cfg,delta)
	var committed_follow:Dictionary={}
	if human_v07 and owned and bool(command.get("enabled",false)) and (result.move_requested or not scheduler.follow_step.pending.is_empty()) and not command.has("prepared_motion"):
		var follow_budget:float=minf(float(state.foot_cap),maxf(result.speed,minf(float(cfg.sprint_ball_speed),float(scheduler.follow_step.pending.get("speed",0.0)))))
		committed_follow=scheduler.follow_step.follow_motion(actor,game.ball,result.move,follow_budget)
		if not committed_follow.is_empty():result.speed=follow_budget
	if human_v07 and owned and result.move_requested and not command.has("prepared_motion"):
		var retreat:Dictionary=scheduler.follow_step.retreat_approach(actor,game.ball,result.move)
		if not retreat.is_empty():
			result.speed=minf(float(state.foot_cap),maxf(result.speed,minf(float(cfg.sprint_ball_speed),(retreat.motion as Vector3).length())))
	if human_v07 and owned and actor.gather_after_sprint and result.move_requested and actor.stop_requested<=0:
		# Stay within reach until the sole can cushion; no ball impulse here.
		var roll:Vector3=game.ball.velocity;roll.y=0
		var offset:Vector3=game.ball.position-actor.position;offset.y=0
		if offset.length()<1.15 and offset.dot(roll)>.05:
			result.speed=minf(float(state.foot_cap),maxf(result.speed,minf(float(cfg.sprint_ball_speed),roll.length()+clampf((offset.length()-.38)*4.0,0,1.2))))
	if human_v07:
		actor.movement_motor.controlled=owned
		actor.set_meta("motor_guard",not owned and actor.semantic_policies.get("pressure",false) and not result.sprint)
		if not owned and (result.close_control or command.get("style","")=="walk"):result.speed=minf(actor.movement_motor.walk_speed,float(state.foot_cap));result.motion=result.move*result.speed
		var energy:Dictionary=actor.get_node("Sprint").update_state(result.sprint,Vector2(actor.velocity.x,actor.velocity.z).length(),result.shield,before.stamina,before.sprint_locked,true,delta)
		result.stamina=energy.stamina;result.sprint_locked=energy.locked
	if bool(command.get("resolved_ai_motion",false)):
		# AI target arrival, approach, turn and ball follow were already solved once.
		# This layer retains stamina/action limits without reapplying the player's gap governor.
		result.speed=minf((command.prepared_motion as Vector3).length(),float(state.foot_cap))
		if result.sprint_locked:result.speed=minf(result.speed,actor.profile.jog_speed_mps)
		result.motion=(command.prepared_motion as Vector3).limit_length(result.speed)
		result.sprint=(bool(command.get("carry_run",false)) or result.speed>actor.profile.jog_speed_mps) and not result.sprint_locked and not result.close_control and not result.shield
		result.ball_direction=command.get("ball_aim",result.ball_direction)
	actor.move_requested = result.move_requested
	actor.close_control = result.close_control
	actor.shielding = result.shield
	actor.sprinting = result.sprint
	actor.stamina = result.stamina
	actor.sprint_locked = result.sprint_locked
	actor.ball_direction = result.ball_direction
	actor.speed = result.speed
	var motion: Vector3 = result.motion
	if not committed_follow.is_empty():
		motion=committed_follow.motion
	elif command.has("prepared_motion"):
		# The released reception/kick setup is a finite, action-reserved intent.
		# Preserve its direction and requested pace, through the same speed caps.
		if not bool(command.get("resolved_ai_motion",false)) or actor._reserve_recovery:
			actor.foot.ordinary_scheduler.reset_turn(actor,"prepared_motion_priority")
		motion = (command.prepared_motion as Vector3).limit_length(result.speed)
	elif owned and result.move_requested and actor.stop_requested<=0 and actor.foot.movement_cap()>1.4:
		if not committed_follow.is_empty():
			motion=committed_follow.motion
		elif incoming_carry and scheduler.turn_stage.is_empty():
			# Debounce defers the turn, including its direction-specific speed cap.
			motion=Vector3(actor.velocity.x,0,actor.velocity.z).limit_length(result.speed)
		else:
			motion = game.ball.human_dribble_motion(actor,result.move,result.speed)
	var sprint_value := 1.0 if result.sprint else 0.0
	var motor_limit:float=actor.motor_speed_limit(sprint_value)
	actor.set_move_intent(motion/motor_limit,sprint_value)
	if actor.is_human:_auto_shield(actor,game,owned,delta) # AI tactical shield already owns its body/pace.
	result.motion = motion
	return result

static func _auto_shield(actor:Node3D,game:Node,owned:bool,delta:float)->void:
	if not owned or actor.sprinting or actor.shielding or actor.foot.kind in ["PASS","SHOT","SPRINT"]:return
	var ball_side:Vector3=game.ball.position-actor.position;ball_side.y=0
	if ball_side.length()>.85 or ball_side.length()<.12:return
	var tick:int=Engine.get_physics_frames()
	var threat:Vector3=actor.get_meta("shield_threat",Vector3.ZERO)
	if tick>=int(actor.get_meta("shield_check",0)):
		actor.set_meta("shield_check",tick+9)
		threat=Vector3.ZERO
		var nearest:float=1.45*1.45
		for other in game.players:
			if other.team==actor.team or not other.visible:continue
			var offset:Vector3=other.position-actor.position;offset.y=0
			if offset.length_squared()<nearest:nearest=offset.length_squared();threat=offset
		actor.set_meta("shield_threat",threat)
	if threat.length_squared()<.01:return
	# Present the hip/shoulder to pressure while retaining the user's full axis.
	var away:Vector3=-threat.normalized()
	var desired:Vector3=(ball_side.normalized()*.65+away*.35).normalized()
	var previous:Vector3=actor.get_meta("shield_body_facing",actor.body_facing)
	if not actor.is_human or actor.get("controller_v07_enabled")!=true:
		actor.body_facing=previous.slerp(desired,minf(1,delta*5.0)).normalized()
	actor.set_meta("shield_body_facing",actor.body_facing)
	actor.shield_side=signf(Vector3(-actor.body_facing.z,0,actor.body_facing.x).dot(threat))
	actor.locomotion="shield"

# Allocation-light exact specialization for read-only, unowned receiving forecasts.
# move is horizontal and normalized, no shield/close/big-chase/incoming carry.
# Returns speed, stamina, locked, sprint. Runtime player control still uses resolve().
static func resolve_receiving_budget(move:Vector3,facing:Vector3,velocity:Vector3,stamina:float,locked:bool,foot_cap:float,requested:float,cfg:Variant,delta:float)->Vector4:
	var sprint:bool=requested>cfg.normal_move_speed and not locked and stamina>1 and move.dot(facing)>=-.2
	var speed:float=minf(minf(cfg.running_move_speed if sprint else cfg.normal_move_speed,foot_cap),requested)
	if sprint and velocity.length()>5.5:stamina=maxf(0,stamina-delta*15*float(cfg.get_meta("endurance",1.0)))
	else:stamina=minf(100,stamina+delta*12)
	if stamina<2:locked=true
	elif stamina>26:locked=false
	return Vector4(speed,stamina,1 if locked else 0,1 if sprint else 0)
