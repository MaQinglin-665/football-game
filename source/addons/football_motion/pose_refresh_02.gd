extends "res://addons/football_motion/football_motion_avatar.gd"
## First narrow batch: stable same-tick snapshots and world-space zero refresh.
## Existing animation, support, real-contact servo and host timing stay in use.
var _refresh_ready:=false
var _refresh_state:Dictionary={}
var _refresh_action:Dictionary={}
var _refresh_transform:=Transform3D.IDENTITY
var _refresh_calls:=0
var _refresh_solves:=0
var _refresh_zero_solves:=0
var _refresh_zero_skips:=0
var _refresh_reprojections:=0

func set_foot_action(action:Dictionary)->void:
	# Identical requests must preserve the last actual reach result when a
	# same-snapshot refresh is skipped. The base setter clears that result.
	if _refresh_ready and _action==action:return
	super.set_foot_action(action)

func clear_foot_action()->void:
	if _action.is_empty():return
	super.clear_foot_action()

func invalidate_pose_snapshot()->void:
	_refresh_ready=false

func _same_pose_state(state:Dictionary)->bool:
	# Epochs identify the authoritative snapshot but do not change its pose.
	for key in state:
		if key in ["pose_tick","pose_world_step"]:continue
		if not _refresh_state.has(key) or state[key]!=_refresh_state[key]:return false
	for key in _refresh_state:
		if key in ["pose_tick","pose_world_step"]:continue
		if not state.has(key):return false
	return true

func update_pose(delta:float,state:Dictionary)->void:
	_refresh_calls+=1
	var dt:=maxf(0,delta)
	ensure_loaded()
	var current_transform:=skeleton.global_transform
	if dt<=0 and _refresh_ready and _same_pose_state(state) and _action==_refresh_action and current_transform==_refresh_transform:
		_refresh_zero_skips+=1
		_refresh_state.pose_tick=state.get("pose_tick",-1)
		_refresh_state.pose_world_step=state.get("pose_world_step",-1)
		return
	if dt<=0 and not _last_ankles.is_empty():
		# World moved the actor since the contact solve. Re-express the actual
		# previous world ankles in the CURRENT skeleton frame. Reusing their
		# old local coordinates would overwrite the world plant solve below.
		var to_local:=current_transform.affine_inverse()
		var inverse_rotation:=current_transform.basis.get_rotation_quaternion().inverse()
		var active_side:=side_suffix(int(_action.get("side",1))) if not _action.is_empty() else ""
		var projected:=false
		for side in ["L","R"]:
			# Only a confirmed world plant receives root-motion compensation.
			# An active contact or swing foot stays free in the actor frame.
			if side==active_side or not _last_ankles.has(side) or not _plants.has(side) or bool(_plants[side].get("releasing",false)):continue
			var previous:Dictionary=_last_ankles[side]
			_last_local_ankles[side]={"point":to_local*(previous.point as Vector3),"rotation":inverse_rotation*(previous.rotation as Quaternion)}
			projected=true
		if projected and _refresh_ready and current_transform!=_refresh_transform:_refresh_reprojections+=1
	_refresh_solves+=1
	if dt<=0:_refresh_zero_solves+=1
	super.update_pose(dt,state)
	_refresh_state=state.duplicate(true)
	_refresh_action=_action.duplicate(true)
	_refresh_transform=skeleton.global_transform
	_refresh_ready=true

func get_pose_refresh_debug()->Dictionary:
	return {"revision":"start_touch_02_batch1","calls":_refresh_calls,"solves":_refresh_solves,"zero_solves":_refresh_zero_solves,"zero_skips":_refresh_zero_skips,"world_reprojections":_refresh_reprojections,"pose_tick":_refresh_state.get("pose_tick",-1),"pose_world_step":_refresh_state.get("pose_world_step",-1),"velocity":_refresh_state.get("velocity",Vector3.ZERO),"control_tier":_refresh_state.get("control_tier","UNSPECIFIED")}

func reset_pose_refresh_counters()->void:
	_refresh_calls=0;_refresh_solves=0;_refresh_zero_solves=0;_refresh_zero_skips=0;_refresh_reprojections=0
