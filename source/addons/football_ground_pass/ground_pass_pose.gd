extends RefCounted
## Original full-body action data. No clock, input, ball force or gait edits.
const STYLE := "ground_compact_r_01"
const DATA := "res://addons/football_ground_pass/compact_pass_r_01.json"
var skeleton: Skeleton3D
var ids: Dictionary = {}
var neutral: Dictionary = {}
var clip: Dictionary = {}
var samples := 0
var debug: Dictionary = {}
var bind_error := ""
var _compiled_keys: Array[Dictionary] = []
var _bone_ids: Array[int] = []
var _neutral_rotations: Array[Quaternion] = []
var _cached_rotations: Array[Quaternion] = []
var _cached_time := -1.0
var _cached_shift := Vector3.ZERO

func bind(rig: Skeleton3D) -> bool:
	if rig == null or rig.get_bone_count() != 32:
		bind_error = "Requires the shared 32-bone rig"
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	if not parsed is Dictionary: return false
	clip = parsed
	if clip.is_empty() or bool(clip.get("loop", true)) or clip.get("rig_contract",[]).size()!=32: return false
	for bone: Dictionary in clip.rig_contract:
		var id := rig.find_bone(bone.name)
		if id < 0:
			bind_error = "Missing shared bone: "+String(bone.name)
			return false
		var parent := rig.get_bone_parent(id)
		var parent_name := "" if parent<0 else rig.get_bone_name(parent)
		var xyz: Array = bone.translation
		var rest := rig.get_bone_rest(id)
		if parent_name!=String(bone.parent_name) or rest.origin.distance_to(Vector3(xyz[0],xyz[1],xyz[2]))>.00001 or not rest.basis.is_equal_approx(Basis.IDENTITY):
			bind_error = "Incompatible shared rest/socket: "+String(bone.name)
			return false
	skeleton = rig
	for name: String in clip.mask:
		var id := rig.find_bone(name)
		if id < 0: return false
		ids[name] = id
		neutral[name] = {"rotation":rig.get_bone_pose_rotation(id),"position":rig.get_bone_pose_position(id)}
	# Fixed key data is converted once, after the shared rig has been validated.
	# Cache only local pose mathematics; actual IK/contact remains fresh.
	_compiled_keys.clear()
	_bone_ids.clear()
	_neutral_rotations.clear()
	_cached_rotations.clear()
	_cached_time = -1.0
	for name: String in ids:
		_bone_ids.append(ids[name])
		_neutral_rotations.append(neutral[name].rotation)
	for key: Dictionary in clip.keyframes:
		var rotations: Array[Quaternion] = []
		for name: String in ids:
			var degrees: Array = key.rotation_delta_degrees[name]
			rotations.append(Quaternion.from_euler(Vector3(deg_to_rad(degrees[0]),deg_to_rad(degrees[1]),deg_to_rad(degrees[2]))))
		var shift: Array = key.hips_delta_m
		_compiled_keys.append({"time":float(key.time),"rotations":rotations,"shift":Vector3(shift[0],shift[1],shift[2])})
	return true

func _calculate_pose(t: float) -> void:
	var keys := _compiled_keys
	var a: Dictionary = keys[0]
	var b: Dictionary = keys[-1]
	for i in keys.size()-1:
		if t >= float(keys[i].time) and t <= float(keys[i+1].time):
			a = keys[i]
			b = keys[i+1]
			break
	var u := smoothstep(0.0, 1.0, clampf((t-float(a.time))/maxf(.00001,float(b.time)-float(a.time)),0.0,1.0))
	_cached_rotations.clear()
	for i in _bone_ids.size():
		var aq: Quaternion = a.rotations[i]
		var bq: Quaternion = b.rotations[i]
		_cached_rotations.append(_neutral_rotations[i]*aq.slerp(bq,u))
	_cached_shift = (a.shift as Vector3).lerp(b.shift,u)
	_cached_time = t

func sample(rig: Skeleton3D, _source_clip: String, action: Dictionary, state: Dictionary, _delta: float) -> void:
	if rig != skeleton or String(action.get("kind", "")) != "PASS" or String(action.get("pass_style", "")) != STYLE: return
	var t := clampf(float(action.get("normalized_time", 0.0)), 0.0, 1.0)
	if t!=_cached_time: _calculate_pose(t)
	# A fresh base sample resets the bones even at the same action time.
	# Reapply every rotation; never reuse world transforms or solved sockets.
	for i in _bone_ids.size():
		skeleton.set_bone_pose_rotation(_bone_ids[i],_cached_rotations[i])
	skeleton.set_bone_pose_position(ids.hips,(neutral.hips.position as Vector3)+_cached_shift)
	skeleton.force_update_all_bone_transforms()
	samples += 1
	debug = {"style":STYLE,"phase":action.get("phase",""),"normalized_time":t,"hips_delta":_cached_shift,"sample_count":samples,"shared_velocity":state.get("velocity",Vector3.ZERO),"shared_accel":state.get("accel",state.get("acceleration",Vector3.ZERO)),"shared_body_yaw":state.get("body_yaw",0.0),"shared_support_phase":state.get("support_phase","UNKNOWN"),"shared_turn_intent":state.get("turn_intent",0.0)}
