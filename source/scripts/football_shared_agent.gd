extends "res://scripts/football_agent.gd"
## Existing AI018 reception/turn/kick decisions run intact; common motor policy
## replaces their outgoing intent before the sole physics World advances.
const SharedMovement := preload("res://scripts/football_shared_movement.gd")
var stamina := 100.0
var sprint_locked := false
var big_chase_remaining := 0.0
var ball_direction := Vector3.BACK
var speed := 0.0
var shared_last_result: Dictionary = {}
var _prepared_motion := Vector3.ZERO
var _reserve_recovery := false
func set_move_intent(axis: Vector3, sprint_amount: float = 0.0, shield_amount: float = 0.0) -> void:
	_prepared_motion = axis*lerpf(profile.jog_speed_mps,profile.sprint_speed_mps,sprint_amount)
	super.set_move_intent(axis,sprint_amount,shield_amount)
func _physics_process(delta: float) -> void:
	var before := {"stamina":stamina,"sprint_locked":sprint_locked}
	super._physics_process(delta)
	if is_instance_valid(down_state) and down_state.blocked():
		_prepared_motion = Vector3.ZERO
		_reserve_recovery = false
		shared_last_result = {"protected_mobility":true}
		return # Local recovery retains the AI's target, without restoring its old kick.
	if match_controller.services.rules.state!=match_controller.Rules.State.LIVE:
		_reserve_recovery=false
		return # The base restart motor already submitted the sole movement command.
	big_chase_remaining = maxf(0,big_chase_remaining-delta)
	var move := Vector3(target.x-position.x,0,target.z-position.z)
	var owned: bool = match_controller.ball.carrier==self
	var reserved: bool = owned and (ai_pocket_recover or (tactical_intent.get("third_man_plan",{}).get("state","")=="CONTROLLED" and tactical_intent.get("reason","") in ["confirm_control_then_turn","third_man_prepare_outlet"]) or not pending_kick.is_empty() or (foot.kind in ["PASS","SHOT"] and not foot.idle() or foot.kind=="RECEIVE" and not foot.hit and not foot.idle()) or (not ai_ordinary_rhythm() and Vector3(match_controller.ball.position.x-position.x,0,match_controller.ball.position.z-position.z).dot(face_target.normalized())<.25))
	_reserve_recovery = reserved
	var run_requested:bool=_prepared_motion.length()>match_controller.tuning.normal_move_speed and (move.length()>1.25 or tactical_intent.has("receive_plan") or owned)
	var command := {"enabled":active,"move":_prepared_motion.normalized() if _prepared_motion.length()>.08 else Vector3.ZERO,"tier":"run" if run_requested else "walk_jog","requested_pace":_prepared_motion.length(),"prepared_motion":_prepared_motion,"close_control":tactical_intent.get("close_control",false),"shield":shielding}
	command["carry_run"]=owned and tactical_intent.get("carry_run",false) and not reserved and not shielding and not close_control
	if command.carry_run:command.tier="run"
	if owned:command.control_setup_tracking=tactical_intent.get("third_man_plan",{}).get("state","")=="CONTROLLED" and tactical_intent.get("reason","") in ["confirm_control_then_turn","third_man_prepare_outlet"]
	command["resolved_ai_motion"]=true # Base actor is the sole target/ball-follow velocity owner.
	command["ball_aim"]=ai_carry_aim if owned and not reserved and ai_carry_aim.length_squared()>.1 else (target-position).normalized() if owned and not reserved and move.length()>.10 else facing
	command["receiving"]=not owned and tactical_intent.has("receive_plan")
	shared_last_result = SharedMovement.apply(self,match_controller,command,before,delta)
func get_ball_direction() -> Vector3:
	# Ordinary close/carry intent has the same command direction as the player.
	# Reserved reception/kick setup retains the released facing contract.
	return facing if _reserve_recovery or not pending_kick.is_empty() or (foot.kind in ["PASS","SHOT"] and not foot.idle() or foot.kind=="RECEIVE" and not foot.hit and not foot.idle()) else ball_direction
