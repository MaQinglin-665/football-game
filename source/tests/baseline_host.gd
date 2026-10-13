extends "res://addons/football_motion/fp_visibility_03.gd"
## B host stance adapter. The motion addon owns normal gait/support/contacts.
## Dedicated kick/sole/tackle stance is retained only until actual regression.
var planted_support: Dictionary = {}
var active_socket: Dictionary = {}
var weight_shift := Vector3.ZERO
const TEAM_COLOR_PRESETS := {"blue":Color("1d5fff"),"yellow":Color("ffdd00"),"red":Color("ef2532")}
var color_preset := "blue"
const ShotMotion := preload("res://scripts/shooting_motion.gd")
var shooting_motion := ShotMotion.new()
var _shot_body_sampled := false

func setup(team: int, jersey: int, first_person: bool) -> void:
	super.setup(team,jersey,first_person)
	if not action_pose_sampled.is_connected(_sample_shot_body): action_pose_sampled.connect(_sample_shot_body)
	if has_method("set_upper_body_overlay_enabled"): call("set_upper_body_overlay_enabled",false)

func _sample_shot_body(sk: Skeleton3D, _clip: String, action: Dictionary, _state: Dictionary, _delta: float) -> void:
	if String(action.get("kind",""))!="SHOT": return
	shooting_motion.sample_body(sk,action)
	_shot_body_sampled = true

func set_color_preset(preset: String) -> void:
	var normalized := preset.to_lower()
	if not TEAM_COLOR_PRESETS.has(normalized): return
	color_preset = normalized
	super.set_color_preset(normalized.to_upper())

func clear_foot_action() -> void:
	super.clear_foot_action()
	active_socket.clear()
	planted_support.clear()
	shooting_motion.reset()

func get_foot_contact(side: int, surface: String) -> Dictionary:
	if not active_socket.is_empty() and not _action.is_empty() and side_suffix(side)==side_suffix(int(_action.get("side",1))) and surface.to_upper()==String(_action.get("surface","INSTEP")).to_upper(): return active_socket.duplicate()
	return super.get_foot_contact(side,surface)

func update_pose(delta: float, state: Dictionary) -> void:
	ensure_loaded()
	visual.position = Vector3.ZERO
	active_socket.clear()
	planted_support.clear()
	if String(_action.get("kind",""))=="SHOT":
		_shot_body_sampled = false
		shooting_motion.prepare(self,_action,state)
		# ShotMotion owns additional bone writes after the base sample.
		invalidate_pose_snapshot()
		super.update_pose(delta,state)
		shooting_motion.apply(self,delta,state,_action,_shot_body_sampled)
		active_socket = shooting_motion.active_contact.duplicate()
		planted_support = shooting_motion.support_contact.duplicate()
		weight_shift = shooting_motion.shift
		# Locomotion resumes from the actual completed shot pose.
		for foot_side in [-1,1]:
			var suffix := side_suffix(foot_side)
			var pose := skeleton.get_bone_global_pose(skeleton.find_bone("foot."+suffix))
			var world := skeleton.global_transform*pose
			_last_contacts[suffix] = skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone("contact_sole."+suffix)).origin)
			_last_ankles[suffix] = {"point":world.origin,"rotation":world.basis.get_rotation_quaternion()}
			_last_local_ankles[suffix] = {"point":pose.origin,"rotation":pose.basis.get_rotation_quaternion()}
		return
	shooting_motion.reset()
	super.update_pose(delta,state)
	if _action.is_empty() or String(_action.get("kind","")).to_upper() in ["CARRY","CLOSE","SHIELD","TURN","SPRINT"]:
		weight_shift = Vector3.ZERO
		return
	var side := int(_action.get("side",1))
	var surface := String(_action.get("surface","INSTEP")).to_upper()
	var support := super.get_foot_contact(-side,"SOLE")
	var support_target: Vector3 = support.point
	support_target.y = global_position.y+.006
	var forward: Vector3 = state.get("forward",Vector3.FORWARD)
	forward.y = 0
	forward = forward.normalized()
	var t := float(_action.get("normalized_time",.5))
	var weight := smoothstep(0,1,t/.5) if t<.5 else 1.0-smoothstep(0,1,(t-.65)/.35) if t>.65 else 1.0
	var tackle := String(_action.get("kind",""))=="TACKLE"
	var kick := String(_action.get("kind","")) in ["PASS","SHOT"]
	var sole := surface=="SOLE"
	var lateral_touch := String(_action.get("kind",""))=="TURN"
	# Ordinary repeated touches must not receive a full-shot crouch every .2s.
	# The source clip already lowers the hips; an extra 75mm caused deep flexion.
	weight_shift = forward*(.24 if tackle else .10 if lateral_touch else .085 if kick or sole else .035)*weight+Vector3.DOWN*(.12 if tackle else .075 if kick else .040 if sole else .020 if lateral_touch else .012)*weight
	visual.position = global_basis.inverse()*weight_shift
	super.update_pose(0,state)
	# Capture active validity before independently solving the other leg. The
	# frozen wrapper's per-query reach state must not let the support solve turn
	# an unreachable active foot into an accepted contact.
	active_socket = super.get_foot_contact(side,surface).duplicate()
	var support_ok := apply_foot_target(-side,"SOLE",support_target,forward)
	planted_support = super.get_foot_contact(-side,"SOLE")
	planted_support["valid"] = support_ok and planted_support.point.distance_to(support_target)<.035
	planted_support["target"] = support_target
