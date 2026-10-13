extends "res://scripts/integration_character_pose.gd"
## Narrow host adapter: reuse READY01 stance after the existing full-body pose.
## A foot action, possession, keeper or inactive match suppresses this layer.
const RoleLayer := preload("res://addons/football_role_actions/role_actions.gd")
var role_layer: RefCounted
var role_bind_attempted := false
var role_bind_ok := false
var _role_weight := 0.0
var _role_pose_applied := false
var _contain_side := 1.0

func update_pose(delta: float, state: Dictionary) -> void:
	ensure_loaded()
	var actor := get_parent() as Node3D
	var game: Node = actor.get("match_controller") if actor != null else null
	if actor!=null and not bool(actor.is_human) and not bool(actor.is_goalkeeper):
		super.update_pose(delta,state)
		return # AI defence is solved before support, never on top of final feet.
	if not role_bind_attempted and game != null and is_instance_valid(game.get("ball")):
		role_bind_attempted = true
		role_layer = RoleLayer.new()
		# Gloves/request gestures are separate follow-up patches, not this batch.
		role_bind_ok = role_layer.bind(self,int(actor.get("team")),bool(actor.get("is_human")),false)
		if not role_bind_ok: push_warning("Role stance disabled: "+String(role_layer.rig_error))
	if role_bind_ok and _role_pose_applied:
		role_layer.before_pose()
		_role_pose_applied = false
	super.update_pose(delta,state)
	if not role_bind_ok or game == null: return
	var owns_ball: bool = is_instance_valid(game.ball) and game.ball.carrier == actor
	var active: bool = actor.visible and (bool(actor.get("is_human")) or bool(actor.get("active")))
	var playing: bool = game.phase == game.Phase.PLAY
	var keeper := bool(actor.get("is_goalkeeper"))
	var mobility_busy: bool = bool(state.get("interaction",{}).get("mobility_busy",false))
	var pressure_input:bool=bool(actor.is_human) and is_instance_valid(game.input_bridge) and game.input_bridge.pressure.active
	var local_pressure:bool=(pressure_input or (not bool(actor.is_human) and actor.tactical_intent.get("press",false))) and actor.position.distance_squared_to(game.ball.position)<12.25
	var defending := playing and active and not keeper and not owns_ball and not mobility_busy and (local_pressure or String(state.get("locomotion","")) == "jockey")
	var velocity: Vector3 = state.get("velocity",Vector3.ZERO)
	# Keep ordinary walk/run and all contact IK on their existing fast path.
	if (not defending or Vector2(velocity.x,velocity.z).length() >= 3.5) and _role_weight <= 0.0: return
	var role_state := state.duplicate()
	role_state.foot_action = _action
	role_state.owns_ball = owns_ball
	role_state.active = active
	role_state.defending = defending
	if local_pressure:
		var forward:Vector3=state.get("forward",Vector3.FORWARD)
		var right:Vector3=Vector3(-forward.z,0,forward.x)
		var lateral:float=(game.ball.position-actor.position).dot(right)
		if absf(lateral)>.15:_contain_side=signf(lateral)
		role_state["contain_side"]=_contain_side
	role_state.upper_body_busy = not playing or not active or owns_ball or keeper or mobility_busy
	role_layer.after_pose(delta,role_state)
	var status: Dictionary = role_layer.get_state()
	_role_weight = float(status.get("defence_weight",0.0))
	_role_pose_applied = _role_weight > 0.0 and _action.is_empty() and not bool(role_state.upper_body_busy) and not bool(status.get("defence_rejected",false))

func role_batch_debug() -> Dictionary:
	return {"batch":"pass_defence_03","rig_bind_attempted":role_bind_attempted,"rig_bind_ok":role_bind_ok,"defence_weight":_role_weight,"pose_applied":_role_pose_applied,"rig_error":String(role_layer.rig_error) if role_layer != null else "","gloves_installed":false,"request_gesture_installed":false,"keeper_hand_actions_installed":false}
