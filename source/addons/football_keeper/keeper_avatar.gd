extends "res://addons/football_role_actions/defence_avatar_03.gd"
## Host owns phase clocks, role, contact decisions and all ball state.
const KeeperPose := preload("res://addons/football_keeper/keeper_pose.gd")
const KeeperGloves := preload("res://addons/football_role_actions/goalkeeper_gloves.gd")
var _keeper_pose = KeeperPose.new()
var _keeper_gloves = KeeperGloves.new()
var _keeper_action: Dictionary = {"phase": "IDLE", "sequence": 0, "weight": 0.0}
var _keeper_first_person := false
var _keeper_gloves_bound := false
var keeper_arm_samples := 0
var keeper_dive: RefCounted

func setup(team: int, jersey: int, first_person: bool) -> void:
	super.setup(team, jersey, first_person)
	_keeper_first_person = first_person
	_sync_keeper_role()

func _is_keeper() -> bool:
	var actor := get_parent()
	if not is_instance_valid(actor):
		return false
	return bool(actor.get("is_goalkeeper"))

func _sync_keeper_role() -> bool:
	var enabled := _is_keeper()
	if enabled:
		ensure_loaded()
		if not _keeper_pose.bound:
			_keeper_pose.bind(skeleton)
		if _keeper_pose.bound and not _keeper_gloves_bound:
			_keeper_gloves.bind(skeleton, _team, _keeper_first_person)
			_keeper_gloves_bound = true
	if _keeper_gloves_bound:
		_keeper_gloves.configure(enabled and _keeper_pose.bound, _keeper_first_person)
	return enabled and _keeper_pose.bound

func set_keeper_action(action: Dictionary) -> void:
	_keeper_action = action.duplicate(true)
	invalidate_pose_snapshot()
	_sync_keeper_role() # Actor's keeper flag can be set after setup().
	if String(_keeper_action.get("phase", "IDLE")).to_upper() == "IDLE":
		_keeper_pose.restore()
		_keeper_pose.clear_debug(_keeper_action)
		if _keeper_gloves_bound:
			_keeper_gloves.refresh()

func keeper_reset() -> void:
	set_keeper_action({"phase": "IDLE", "sequence": 0, "weight": 0.0})

func update_pose(delta: float, state: Dictionary) -> void:
	_keeper_pose.restore()
	if keeper_dive!=null: keeper_dive.body.restore()
	super.update_pose(delta, state)
	if _sync_keeper_role():
		if keeper_dive!=null and keeper_dive.active(): keeper_dive.body.apply()
		_keeper_pose.apply(_keeper_action, global_position, keeper_facing_basis())
		_finish_dive_floor()
	elif _keeper_pose.bound:
		_keeper_pose.clear_debug(_keeper_action)
	if _keeper_gloves_bound:
		_keeper_gloves.refresh()

func keeper_sample_action() -> void:
	# Called for only two GK: rotations of six arm bones, no full-body refresh.
	_keeper_pose.restore()
	if keeper_dive!=null: keeper_dive.body.restore()
	if _sync_keeper_role():
		if keeper_dive!=null and keeper_dive.active(): keeper_dive.body.apply()
		_keeper_pose.apply(_keeper_action, global_position, keeper_facing_basis())
		_finish_dive_floor()
		_keeper_gloves.refresh()
		keeper_arm_samples += 1

func keeper_contact_debug() -> Dictionary:
	# Host only needs compact reach/error data; geometry is read separately.
	var result: Dictionary = _keeper_pose.debug()
	if keeper_dive!=null and keeper_dive.active():
		var hands: Dictionary = keeper_hand_geometry().get("hands",{})
		for side in ["L","R"]:
			if not hands.has(side) or not result.get("hand_errors",{}).has(side): continue
			var error: Dictionary = result.hand_errors[side]
			var actual: Transform3D = hands[side].padded_box_transform
			error.error_m = actual.origin.distance_to(error.target_centre_world)
			error.valid = bool(error.valid) and float(error.error_m)<.006
			result.reachable = bool(result.reachable) and bool(error.valid)
	return result

func keeper_hand_geometry() -> Dictionary:
	if not _is_keeper() or not _keeper_gloves_bound:
		return {}
	return _keeper_gloves.get_geometry()

func keeper_pose_debug() -> Dictionary:
	var result: Dictionary = keeper_contact_debug()
	result["dive"] = keeper_dive_debug()
	result["geometry"] = keeper_hand_geometry()
	return result

func keeper_facing_basis() -> Basis:
	return keeper_dive.facing_basis if keeper_dive!=null and keeper_dive.active() else visual.global_basis.orthonormalized()

func _finish_dive_floor() -> void:
	if keeper_dive==null or not keeper_dive.active(): return
	keeper_dive.body.enforce_floor()
	keeper_dive.body.sync_volume()
	keeper_dive.actor.down_state.sync_head_shape()

func keeper_dive_debug() -> Dictionary:
	if keeper_dive==null: return {}
	return {"phase":keeper_dive.phase,"weight":keeper_dive.weight(),"body_samples":keeper_dive.body.samples,"mesh_floor_y":keeper_dive.body.last_floor,"ground_y":keeper_dive.ground_y,"owns_low_state":keeper_dive.owns_low_state()}

func _exit_tree() -> void:
	_keeper_pose.restore()
	if keeper_dive!=null:
		keeper_dive.body.restore()
		# Break Motion -> Body -> Motion reference cycle after pose restore.
		keeper_dive.body.driver = null
	_keeper_gloves.detach()
