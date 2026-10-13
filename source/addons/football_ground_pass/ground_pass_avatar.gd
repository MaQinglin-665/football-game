extends "res://addons/football_role_actions/defence_avatar_03.gd"
## Optional action wrapper. Original FP visibility, shot and gait are inherited.
const PassPose := preload("res://addons/football_ground_pass/ground_pass_pose.gd")
var pass_pose: RefCounted
var pass_bind_ok := false
var pass_support: Dictionary = {}
var _pass_sequence := -1
var _support_anchor := Vector3.ZERO
var _last_pass_state: Dictionary = {}

func setup(team: int, jersey: int, first_person: bool) -> void:
	super.setup(team,jersey,first_person)
	# View/kit refresh must keep the original neutral, including during a pass.
	if pass_pose==null or pass_pose.skeleton!=skeleton:
		if pass_pose!=null and action_pose_sampled.is_connected(pass_pose.sample): action_pose_sampled.disconnect(pass_pose.sample)
		pass_pose = PassPose.new()
		pass_bind_ok = pass_pose.bind(skeleton)
	if pass_bind_ok:
		if not action_pose_sampled.is_connected(pass_pose.sample): action_pose_sampled.connect(pass_pose.sample)
	else: push_warning("Ground pass disabled: "+pass_pose.bind_error)

func update_pose(delta: float, state: Dictionary) -> void:
	_last_pass_state = state.duplicate(true)
	var selected := String(_action.get("pass_style","")) == PassPose.STYLE and String(_action.get("kind","")) == "PASS"
	if selected and int(_action.get("sequence",-1)) != _pass_sequence:
		_pass_sequence = int(_action.sequence)
		_support_anchor = super.get_foot_contact(-1,"SOLE").point
		_support_anchor.y = global_position.y + .006
		invalidate_pose_snapshot()
	super.update_pose(delta,state)
	pass_support.clear()
	if not selected:
		_pass_sequence = -1
		return
	var support_now: Dictionary = super.get_foot_contact(-1,"SOLE")
	var target := _support_anchor
	var t := float(_action.get("normalized_time",0.0))
	if String(_action.get("phase","")) == "RECOVER":
		target = target.lerp(support_now.point,smoothstep(.68,.95,t))
	var forward: Vector3 = state.get("forward",Vector3.FORWARD)
	var solved := apply_foot_target(-1,"SOLE",target,forward)
	var final: Dictionary = super.get_foot_contact(-1,"SOLE")
	var error: float = (final.point as Vector3).distance_to(target)
	pass_support = final.duplicate()
	pass_support.merge({"ready":solved and bool(state.get("grounded",true)) and error<.035,"target":target,"anchor":_support_anchor,"error_m":error,"sequence":_pass_sequence},true)
	planted_support = pass_support.duplicate()

func ground_pass_support() -> Dictionary:
	return pass_support.duplicate(true)

func ground_pass_shared_state() -> Dictionary:
	return _last_pass_state.duplicate(true)
