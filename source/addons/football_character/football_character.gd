extends "res://addons/football_character/football_character_base.gd"
## Common low-control/monocolour hotfix for both main A and future B.
## Visuals only: no actor collision, ball force, or contact-window ownership.

var _profiles := {}
var _support_points := {}
var _plants := {}
var _last_contacts := {}
var _last_ankles := {}
var _blend_from: Array = []
var _blend_time := 0.0
var _blend_duration := .14
var _blend_key := ""
var _base_clip := ""
var _ground_y := 0.0
var _grounded := true
var _plant_releases := 0
var _cadence := 0.0
const NORMAL_CONTROL_KINDS := ["CARRY", "CLOSE", "SHIELD", "TURN", "SPRINT"]
const COLOR_PRESETS := {"BLUE": "628FB1", "YELLOW": "D8BC66", "RED": "C26961"}
var _preset := "BLUE"
static var _shared_team_finishes:Dictionary={}
var _tint_cache := {}
var _guard_reason := ""
var _action_layer := ""
var _pose_delta := 0.0
var _last_local_ankles := {}
var _control_handover := 0.0
var _control_stance := Vector3.ZERO
var _stance_rejected := false
# Eligibility metadata only: no sampled poses or per-miss bone capture.
var _single_bone_animations050:Dictionary={}
var _single_ready_player050:AnimationPlayer
var _single_invalidate050:Callable=func():
	_single_bone_animations050.clear()
	_single_ready_player050=null
const GAIT_FOOT_SPEED:=6.5
const LATERAL_TOUCH_FOOT_SPEED:=9.0

func setup(team: int, jersey: int, first_person: bool) -> void:
	ensure_loaded()
	_team = team
	_jersey = jersey
	set_meta("jersey", jersey)
	for node in mesh_nodes: node.visible = not (first_person and String(node.name) in ["Head", "BodyCore"])
	set_color_preset("BLUE" if team == 0 else "YELLOW" if team == 1 else "RED" if team == 2 else "BLUE")

func set_color_preset(preset: String) -> void:
	ensure_loaded()
	_preset = preset.to_upper() if COLOR_PRESETS.has(preset.to_upper()) else "BLUE"
	if not _tint_cache.has(_preset): _tint_cache[_preset] = {}
	var cache: Dictionary = _tint_cache[_preset]
	for node in mesh_nodes:
		for surface in node.mesh.get_surface_count():
			var source: StandardMaterial3D = node.mesh.surface_get_material(surface)
			var name := str(node.name)+":"+source.resource_name
			if not cache.has(name):
				var shared_key:String=_preset+":"+str(node.name)+":"+str(source.get_instance_id())
				if not _shared_team_finishes.has(shared_key):_shared_team_finishes[shared_key]=_finished_material(source, Color(COLOR_PRESETS[_preset]), str(node.name))
				cache[name]=_shared_team_finishes[shared_key]
			var finish:Material=cache[name]
			if String(node.name)=="BodyCore":
				finish=finish.duplicate()
				finish.set_shader_parameter("jersey_number",_jersey)
				finish.set_shader_parameter("jersey_digits",preload("res://assets/art_sample/jersey_digits.png"))
			node.set_surface_override_material(surface,finish)

# Visual prototype: shared rest-space textile/skin/leather, no rig or geometry writes.
func _finished_material(source: StandardMaterial3D, team_color: Color, mesh_name:String) -> Material:
	var material:=ShaderMaterial.new()
	material.shader=preload("res://assets/art_sample/kit.gdshader")
	material.set_shader_parameter("team",team_color)
	material.set_shader_parameter("authored_rest",source.resource_name.begins_with("Broadcast"))
	var part:=0
	if mesh_name.begins_with("RobotArm"):part=1
	elif mesh_name.begins_with("RobotLeg"):part=2
	elif mesh_name=="Head":part=3
	elif mesh_name.begins_with("Boot"):
		part={"BootUpper":4,"BootSole":5,"BootStuds":6,"BootLaces":7,"BootAccent":8}.get(source.resource_name,4)
	material.set_shader_parameter("part",part)
	material.set_shader_parameter("inset",source.resource_name in ["CoreGraphite","JointGraphite"])
	return material

func ensure_loaded() -> void:
	if visual != null: return
	super.ensure_loaded()
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	_profiles = manifest["motion_profiles"]
	for side in ["L", "R"]:
		var cloud := PackedVector3Array()
		for p in manifest["boot_support_points"][side]: cloud.append(Vector3(p[0], p[1], p[2]))
		_support_points[side] = cloud

func _save_pose() -> Array:
	var result := []
	for i in skeleton.get_bone_count():
		result.append({"position": skeleton.get_bone_pose_position(i), "rotation": skeleton.get_bone_pose_rotation(i)})
	return result

func _sample(clip: String, seconds: float) -> void:
	var animation:Animation=animation_player.get_animation(clip)
	if not animation.changed.is_connected(_single_invalidate050):animation.changed.connect(_single_invalidate050)
	if not _single_bone_animations050.has(animation):
		var pure:=animation.get_track_count()>0
		var root:Node=animation_player.get_node(animation_player.root_node)
		for track in animation.get_track_count():
			var path:NodePath=animation.track_get_path(track)
			if not animation.track_get_type(track) in [Animation.TYPE_POSITION_3D,Animation.TYPE_ROTATION_3D,Animation.TYPE_SCALE_3D] or path.get_subname_count()!=1:
				pure=false;break
			if root.get_node_or_null(NodePath(path.get_concatenated_names()))!=skeleton:
				pure=false;break
		_single_bone_animations050[animation]=pure
	# The paused player's seek(true) still samples the exact requested time.
	# Original play() also sets started, causing seek() to first sample the
	# old/start time. Bone-only clips need only the final target-time pass.
	var safe:bool=bool(_single_bone_animations050[animation]) and not animation_player.is_playing() and not animation_player.has_section() and animation_player.get_script()==null and animation_player.root_motion_track.is_empty() and animation.loop_mode!=Animation.LOOP_PINGPONG and animation_player.playback_default_blend_time==0 and animation_player.get_blend_time(animation_player.assigned_animation,clip)==0 and animation_player.get_blend_time("*",clip)==0 and animation_player.get_blend_time(animation_player.assigned_animation,"*")==0
	# Preserve observable native event counts/timing via the original path.
	for signal_name in ["animation_started","animation_finished","current_animation_changed","mixer_applied","caches_cleared"]:
		if not animation_player.get_signal_connection_list(signal_name).is_empty():safe=false;break
	# Sparse glTF tracks still start at current rest on EVERY sample.
	skeleton.reset_bone_poses()
	if safe and _single_ready_player050==animation_player:
		if animation_player.assigned_animation!=clip or not animation_player.is_animation_active():animation_player.assigned_animation=clip
	else:
		animation_player.play(clip)
	animation_player.seek(seconds, true)
	animation_player.pause()
	_single_ready_player050=animation_player if safe else null
	_shape_sampled_gait(clip)

func _shape_sampled_gait(_clip_name: String) -> void:
	pass

func _gait_cadence(base: String, speed: float, duration: float) -> float:
	return 1.0/duration if base == "Idle" else speed*float(_profiles[base]["stance_fraction"])/float(_profiles[base]["stance_distance"])

func _restart_gait_phase(base: String) -> void:
	_phase = float(_profiles[base]["stance_fraction"])*.5

func _select_gait_base(base: String) -> String:
	return base

func _gait_direction_sign(mode: String) -> float:
	return -1.0 if mode == "retreat" else 1.0

func _align_transition_gait_phase(phase:float)->float:
	return phase

func _action_clip() -> String:
	var suffix := side_suffix(int(_action.get("side", 1)))
	var surface := String(_action.get("surface", "INSTEP")).to_upper()
	var kind := String(_action.get("kind", "")).to_upper()
	if kind in NORMAL_CONTROL_KINDS: return "ControlTap_"+suffix
	var stem := "TouchInstep_"
	if surface == "INSIDE": stem = "TouchInside_"
	elif surface == "OUTSIDE": stem = "TouchOutside_"
	elif surface == "SOLE": stem = "SolePull_" if kind in ["PULL", "SOLE_PULL", "DRAG", "DRAG_BACK"] else "SoleStop_"
	return stem+suffix

func update_pose(delta: float, state: Dictionary) -> void:
	ensure_loaded()
	_guard_reason = ""
	var dt := maxf(0.0, delta)
	_pose_delta = dt
	_ground_y = float(state.get("ground_y", global_position.y))
	_grounded = bool(state.get("grounded", true))
	var forward: Vector3 = state.get("forward", -global_basis.z)
	forward.y = 0
	if forward.length_squared() < .0001: forward = Vector3.FORWARD
	forward = forward.normalized()
	var yaw := atan2(-forward.x, -forward.z)
	visual.global_rotation = Vector3(0, lerp_angle(visual.global_rotation.y, yaw, 1.0-exp(-18.0*dt)) if _base_clip != "" else yaw, 0)
	var velocity: Vector3 = state.get("velocity", Vector3.ZERO)
	var speed := Vector2(velocity.x, velocity.z).length()
	var mode := String(state.get("locomotion", "idle" if speed < .08 else "walk")).to_lower()
	var base := "Idle"
	if speed >= .08:
		base = "Run" if mode in ["run", "sprint"] else "Dribble" if mode == "dribble" else "Walk"
		if mode == "dribble" and (speed > 2.10 or (_base_clip == "DribbleJog" and speed > 1.85)): base = "DribbleJog"
	base = _select_gait_base(base)
	if base != _base_clip and _base_clip in ["", "Idle"] and base != "Idle":
		_restart_gait_phase(base)
	var has_action := not _action.is_empty()
	var ordinary: bool = has_action and String(_action.get("kind", "")).to_upper() in NORMAL_CONTROL_KINDS
	var selected_action := _action_clip() if has_action else ""
	var selected_key := base+"/"+selected_action if has_action and not ordinary else base
	var old_pose: Array = _save_pose() if selected_key != _blend_key and _blend_key != "" else []
	# The locomotion blend owns its authored pelvis position. The live control
	# transfer is added once below; retaining it in the blend source doubled
	# that translation on a moving->idle transition.
	if not old_pose.is_empty() and _control_stance.length_squared()>0:
		var hips_id:=cached_bone_id("hips")
		old_pose[hips_id]["position"]=(old_pose[hips_id]["position"] as Vector3)-_control_stance
	var duration: float = animation_player.get_animation(base).length
	_cadence = _gait_cadence(base, speed, duration)
	var direction_sign := _gait_direction_sign(mode)
	_phase = fposmod(_phase+dt*_cadence*direction_sign, 1.0)
	_phase = _align_transition_gait_phase(_phase)
	_sample(base, _phase*duration)
	var pass_recovery:float=smoothstep(.70,1.0,float(_action.get("normalized_time",0))) if _action.get("kind","")=="PASS" and _action.get("phase","")=="RECOVER" else 0.0
	var return_point:=Vector3.ZERO
	if pass_recovery>0:
		var suffix:String=side_suffix(int(_action.side))
		var surface:String=String(_action.surface)
		var socket:int=cached_bone_id("foot."+suffix if surface=="HEEL" else "contact_"+String(SURFACES[surface])+"."+suffix)
		var pose:Transform3D=skeleton.get_bone_global_pose(socket)
		return_point=skeleton.to_global(pose*Vector3(0,-.035,.045) if surface=="HEEL" else pose.origin)
	var key := base
	_clip = base
	_action_layer = ""
	if has_action:
		var gait_pose: Array = [] if ordinary and _action.has("world_target") else _save_pose()
		_action_layer = selected_action
		if not ordinary:
			_clip = _action_layer
			key += "/"+_clip
		var normalized := clampf(float(_action.get("normalized_time", .5)), 0, 1)
		# Ordinary control with a real target keeps the sampled gait completely;
		# only the active leg is modified by the fixed-length IK below. Repeated
		# 40ms windups must never restart/freeze the whole locomotion blend.
		if not ordinary or not _action.has("world_target"):
			_sample(_action_layer, normalized*animation_player.get_animation(_action_layer).length)
		if (not ordinary or not _action.has("world_target")) and (speed > .35 or ordinary):
			# A moving contact preserves the opposite leg and arm locomotion.
			var active := side_suffix(int(_action.get("side", 1)))
			for i in skeleton.get_bone_count():
				var name := String(skeleton.get_bone_name(i))
				if not (name in ["thigh."+active, "shin."+active, "foot."+active, "toe."+active]):
					skeleton.set_bone_pose_position(i, gait_pose[i]["position"])
					skeleton.set_bone_pose_rotation(i, gait_pose[i]["rotation"])
	if key != _blend_key:
		_blend_from = old_pose if _blend_key != "" else []
		_blend_time = 0.0
		_blend_duration = .10 if base == "Run" else .16
		_blend_key = key
	_blend_time += dt
	if not _blend_from.is_empty() and _blend_time < _blend_duration:
		var weight := smoothstep(0.0, _blend_duration, _blend_time)
		for i in skeleton.get_bone_count():
			skeleton.set_bone_pose_position(i, (_blend_from[i]["position"] as Vector3).lerp(skeleton.get_bone_pose_position(i), weight))
			skeleton.set_bone_pose_rotation(i, (_blend_from[i]["rotation"] as Quaternion).slerp(skeleton.get_bone_pose_rotation(i), weight))
	_base_clip = base
	_update_control_stance(dt,forward)
	_update_support(dt, base, speed, forward)
	if _action.has("world_target") and _action["world_target"] is Vector3:
		var target:Vector3=_action.world_target
		if pass_recovery>0:target=target.lerp(return_point,pass_recovery)
		apply_foot_target(int(_action.get("side", 1)), String(_action.get("surface", "INSTEP")).to_upper(), target, _action.get("direction", forward))
	if base in ["Walk", "Run", "Dribble", "DribbleJog"] or String(_action.get("kind", "")).to_upper() in NORMAL_CONTROL_KINDS: _control_handover = .10
	else: _control_handover = maxf(0.0, _control_handover-dt)
	if _grounded and _control_handover > 0.0 and (_action.is_empty() or String(_action.get("kind", "")).to_upper() in NORMAL_CONTROL_KINDS):
		# Keep the same limit through action->gait handovers on either leg.
		# Otherwise the first frame with no action could undo the target servo.
		for side in ["L", "R"]: _bound_control_motion(side, forward)
	if _grounded:
		for side in ["L", "R"]: _correct_floor(side, forward)
	for side in [-1, 1]:
		var suffix := side_suffix(side)
		_last_contacts[suffix] = skeleton.to_global(skeleton.get_bone_global_pose(cached_bone_id("contact_sole."+suffix)).origin)
		var foot_world := skeleton.global_transform*skeleton.get_bone_global_pose(cached_bone_id("foot."+suffix))
		_last_ankles[suffix] = {"point": foot_world.origin, "rotation": foot_world.basis.get_rotation_quaternion()}
		var local_pose := skeleton.get_bone_global_pose(cached_bone_id("foot."+suffix))
		_last_local_ankles[suffix] = {"point": local_pose.origin, "rotation": local_pose.basis.get_rotation_quaternion()}

func _sole_offset(side: String) -> Vector3:
	return skeleton.get_bone_global_rest(cached_bone_id("contact_sole."+side)).origin-skeleton.get_bone_global_rest(cached_bone_id("foot."+side)).origin

func _update_control_stance(dt: float, forward: Vector3) -> void:
	# A forward ground ball can be outside the standing leg's reach even with
	# the correct shoe heading. Move the pelvis over the support base only as
	# needed, with bounded forward/side transfer and a small knee-flex drop.
	# The foot still has to reach the real target; no actor/ball displacement,
	# bone scaling, extra zero-delta movement or forced valid contact is used.
	var wanted := Vector3.ZERO
	_stance_rejected=false
	var ordinary: bool = _grounded and String(_action.get("kind","")).to_upper() in NORMAL_CONTROL_KINDS
	if ordinary and _action.get("world_target") is Vector3:
		var target: Vector3 = _action.world_target
		var surface := String(_action.get("surface","INSTEP")).to_upper()
		if SURFACES.has(surface) and surface!="SOLE" and target.y-_ground_y >= -.004 and target.y-_ground_y <= .16:
			var side := side_suffix(int(_action.get("side",1)))
			var direction: Vector3 = skeleton.global_basis.inverse()*(_action.get("direction",forward) as Vector3)
			direction.y=0
			if direction.length_squared()<.00001:direction=Vector3.FORWARD
			var rotation:=_surface08.rotation(self,-1 if side=="L" else 1,surface,target,_action.get("direction",forward))
			var socket:=cached_bone_id("contact_"+String(SURFACES[surface])+"."+side)
			var foot:=cached_bone_id("foot."+side)
			var offset:=skeleton.get_bone_global_rest(socket).origin-skeleton.get_bone_global_rest(foot).origin
			var ankle:=skeleton.to_local(target)-rotation*offset
			var ankle_world:=skeleton.to_global(ankle)
			ankle_world.y=maxf(ankle_world.y,_ground_y+.005-_minimum_offset(side,skeleton.global_basis.get_rotation_quaternion()*rotation))
			ankle=skeleton.to_local(ankle_world)
			var hip:=skeleton.get_bone_global_pose(cached_bone_id("thigh."+side)).origin
			var maximum:=skeleton.get_bone_rest(cached_bone_id("shin."+side)).origin.length()+skeleton.get_bone_rest(foot).origin.length()-_surface08.knee_margin(self,side,surface)
			var vector:=ankle-hip
			if vector.length()>maximum:
				wanted.x=clampf(vector.x*.18,-.065,.065)
				var z_allow:=sqrt(maxf(0,maximum*maximum-vector.y*vector.y-pow(vector.x-wanted.x,2)))
				wanted.z=clampf(vector.z-signf(vector.z)*minf(absf(vector.z),z_allow),-.210,.080)
				var y_allow:=sqrt(maxf(0,maximum*maximum-pow(vector.x-wanted.x,2)-pow(vector.z-wanted.z,2)))
				wanted.y=clampf(vector.y+minf(absf(vector.y),y_allow),-.080,0)
				if (vector-wanted).length()>maximum+.0001:
					_stance_rejected=true
					# Keep the bounded transfer while a moving ball approaches the
					# reach edge; dropping it to zero would make the foot retreat.
					# Truly distant targets do not pull the whole body after them.
					if Vector2(ankle.x,ankle.z).length()>.85:wanted=Vector3.ZERO
	_control_stance=_control_stance.move_toward(wanted,(4.5 if ordinary else 2.5)*dt)
	if _control_stance.length_squared()<.00000001:return
	var id:=cached_bone_id("hips")
	skeleton.set_bone_pose_position(id,skeleton.get_bone_pose_position(id)+_control_stance)

func _minimum_offset(side: String, world_rotation: Quaternion) -> float:
	var axis := world_rotation.inverse()*Vector3.UP
	var minimum := INF
	for vertex in _support_points[side]: minimum = minf(minimum, axis.dot(vertex))
	return minimum

func _update_support(dt: float, base: String, speed: float, forward: Vector3) -> void:
	if not _grounded:
		_plants.clear()
		return
	# A planted standing turn releases one shoe at a time before knees twist.
	if speed<.50 and _action.is_empty() and dt>0:
		var releasing:bool=false
		for plant_side in _plants:
			if bool(_plants[plant_side].get("releasing",false)):releasing=true
		if not releasing:
			for plant_side in ["L","R"]:
				if _plants.has(plant_side) and absf(angle_difference(float(_plants[plant_side].yaw),visual.global_rotation.y))>.35:
					_plants[plant_side]["pivot"]=true
					_begin_release(plant_side,skeleton.get_bone_global_pose(cached_bone_id("foot."+plant_side)))
					break
	for side in ["L", "R"]:
		var p := fposmod(_phase+(.5 if side == "R" else 0.0), 1.0)
		var wanted := base == "Idle" or p < float(_profiles[base]["stance_fraction"])
		if not _action.is_empty():
			if side == side_suffix(int(_action.get("side", 1))): wanted = false
			elif speed <= .35:
				wanted = true
		var foot_id := cached_bone_id("foot."+side)
		var pose := skeleton.get_bone_global_pose(foot_id)
		var world_rotation := (skeleton.global_basis*pose.basis).get_rotation_quaternion()
		if _plants.has(side) and not wanted: _begin_release(side, pose)
		if not _plants.has(side):
			if not wanted: continue
			var socket_world := skeleton.to_global(pose.origin+pose.basis*_sole_offset(side))
			var anchor: Vector3 = _last_contacts.get(side, socket_world)
			_plants[side] = {"point": anchor, "rotation": world_rotation, "age": 0.0, "yaw": visual.global_rotation.y, "releasing": false}
		var plant: Dictionary = _plants[side]
		if plant["releasing"]:
			_release_support(side, dt, pose, forward)
			continue
		plant["age"] += dt
		var flat := Quaternion(Vector3.UP, float(plant["yaw"]))
		world_rotation = (plant["rotation"] as Quaternion).slerp(flat, smoothstep(0.0, .065, float(plant["age"])))
		var anchor: Vector3 = plant["point"]
		anchor.y = _ground_y+.005-_minimum_offset(side, world_rotation)+(world_rotation*_sole_offset(side)).y
		plant["point"] = anchor
		var local_rotation := skeleton.global_basis.get_rotation_quaternion().inverse()*world_rotation
		var ankle := skeleton.to_local(anchor)-local_rotation*_sole_offset(side)
		if not _solve_leg(side, ankle, local_rotation, skeleton.global_basis.inverse()*forward):
			_plant_releases += 1
			if skeleton.to_global(ankle).distance_to(skeleton.to_global(pose.origin)) > .6:
				# A teleport is a discontinuity in the actor itself, so reset safely.
				_plants.erase(side)
			else:
				_begin_release(side, pose)
				_release_support(side, dt, pose, forward)

func _begin_release(side: String, pose: Transform3D) -> void:
	var plant: Dictionary = _plants[side]
	if plant["releasing"]: return
	var world_pose := skeleton.global_transform*pose
	var previous: Dictionary = _last_ankles.get(side, {"point": world_pose.origin, "rotation": world_pose.basis.get_rotation_quaternion()})
	plant["releasing"] = true
	plant["release_age"] = 0.0
	plant["release_from"] = previous

func _release_support(side: String, dt: float, target_pose: Transform3D, forward: Vector3) -> void:
	var plant: Dictionary = _plants[side]
	plant["release_age"] += dt
	var pivot:bool=bool(plant.get("pivot",false))
	var weight := smoothstep(0.0, .14 if pivot else .08, float(plant["release_age"]))
	var previous: Dictionary = plant["release_from"]
	var world_pose := skeleton.global_transform*target_pose
	var ankle_world := (previous["point"] as Vector3).lerp(world_pose.origin, weight)
	if pivot:ankle_world.y+=sin(PI*weight)*.035
	var world_rotation := (previous["rotation"] as Quaternion).slerp(world_pose.basis.get_rotation_quaternion(), weight)
	var ankle := skeleton.to_local(ankle_world)
	var hip := skeleton.get_bone_global_pose(cached_bone_id("thigh."+side)).origin
	var maximum := skeleton.get_bone_rest(cached_bone_id("shin."+side)).origin.length()+skeleton.get_bone_rest(cached_bone_id("foot."+side)).origin.length()-.001
	var vector := ankle-hip
	if vector.length() > maximum: ankle = hip+vector.normalized()*maximum
	_solve_leg(side, ankle, skeleton.global_basis.get_rotation_quaternion().inverse()*world_rotation, skeleton.global_basis.inverse()*forward)
	if weight >= 1.0: _plants.erase(side)

func _solve_leg(side: String, ankle: Vector3, foot_rotation: Quaternion, direction: Vector3) -> bool:
	var thigh_id := cached_bone_id("thigh."+side)
	var shin_id := cached_bone_id("shin."+side)
	var foot_id := cached_bone_id("foot."+side)
	var hip := skeleton.get_bone_global_pose(thigh_id).origin
	var rest_upper := skeleton.get_bone_rest(shin_id).origin
	var rest_lower := skeleton.get_bone_rest(foot_id).origin
	var a := rest_upper.length()
	var b := rest_lower.length()
	var vector := ankle-hip
	var distance := vector.length()
	if distance > a+b-.00001 or distance < absf(a-b)+.025: return false
	var axis := vector/distance
	direction = _surface08.pole_direction(self,side,foot_rotation,direction)
	direction.y = 0
	if direction.length_squared() < .00001: direction = Vector3.FORWARD
	direction = direction.normalized()
	var pole := direction-axis*direction.dot(axis)
	if pole.length_squared() < .00001: pole = Vector3.FORWARD-axis*Vector3.FORWARD.dot(axis)
	pole = pole.normalized()
	var along := (a*a-b*b+distance*distance)/(2*distance)
	var height := sqrt(maxf(0, a*a-along*along))
	var knee := hip+axis*along+pole*height
	var upper_rotation := Quaternion(rest_upper.normalized(), (knee-hip).normalized())
	var lower_rotation := Quaternion(rest_lower.normalized(), (ankle-knee).normalized())
	var parent_rotation := skeleton.get_bone_global_pose(skeleton.get_bone_parent(thigh_id)).basis.get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(thigh_id, parent_rotation.inverse()*upper_rotation)
	skeleton.set_bone_pose_rotation(shin_id, upper_rotation.inverse()*lower_rotation)
	skeleton.set_bone_pose_rotation(foot_id, lower_rotation.inverse()*foot_rotation)
	skeleton.set_bone_pose_rotation(cached_bone_id("toe."+side), Quaternion.IDENTITY)

	return true

func _correct_floor(side: String, forward: Vector3) -> void:
	var pose := skeleton.get_bone_global_pose(cached_bone_id("foot."+side))
	var rotation := pose.basis.get_rotation_quaternion()
	var world_rotation := skeleton.global_basis.get_rotation_quaternion()*rotation
	var ankle_world := skeleton.to_global(pose.origin)
	var minimum := ankle_world.y+_minimum_offset(side, world_rotation)
	if minimum < _ground_y+.005:
		ankle_world.y += _ground_y+.005-minimum
		_solve_leg(side, skeleton.to_local(ankle_world), rotation, skeleton.global_basis.inverse()*forward)

func _bound_control_motion(side: String, forward: Vector3) -> void:
	if not _last_local_ankles.has(side): return
	var goal := skeleton.get_bone_global_pose(cached_bone_id("foot."+side))
	var last: Dictionary = _last_local_ankles[side]
	var point := (last["point"] as Vector3)+(goal.origin-(last["point"] as Vector3)).limit_length(_foot_speed_limit(side)*_pose_delta)
	var old_rotation: Quaternion = last["rotation"]
	var rotation := goal.basis.get_rotation_quaternion()
	var angle := old_rotation.angle_to(rotation)
	if angle > .000001: rotation = old_rotation.slerp(rotation,minf(1.0,12.0*_pose_delta/angle))
	_solve_leg(side,point,rotation,skeleton.global_basis.inverse()*forward)

func _foot_speed_limit(side:String)->float:
	# A deliberate lateral touch must cover its swing within the host's short
	# window even when this foot was at the rear of the preceding dribble.
	# Keep gait and the opposite support leg at their existing travel limit.
	return LATERAL_TOUCH_FOOT_SPEED if String(_action.get("kind","")).to_upper()=="TURN" and side==side_suffix(int(_action.get("side",1))) else GAIT_FOOT_SPEED

func apply_foot_target(side: int, surface: String, world_target: Vector3, world_direction: Vector3) -> bool:
	# Preserve exact CONTACT-phase alignment. Prepare/recover blend toward the
	# same fixed-length target without moving the hidden actor or scaling bones.
	_guard_reason = ""
	if String(_action.get("kind", "")).to_upper() in NORMAL_CONTROL_KINDS and side_suffix(side) == side_suffix(int(_action.get("side", 1))):
		var height := world_target.y-_ground_y
		var ceiling:float=.25 if String(_action.get("phase",""))=="RECOVER" else .16
		if height > ceiling or height < -.004 or surface == "SOLE":
			_guard_reason = "ordinary_control_requires_low_side_or_instep_target"
			_unreachable = true
			_reach_error = maxf(.036, height-.16)
			return false
	var previous:Dictionary={}
	for name in ["thigh.","shin.","foot.","toe."]:
		var id:int=cached_bone_id(name+side_suffix(side))
		previous[id]=skeleton.get_bone_pose_rotation(id)
	var solved := super.apply_foot_target(side, surface, world_target, world_direction)
	if not solved:
		# A moving pelvis may make the requested target reachable a few ticks
		# later. Pursue the nearest fixed-length pose meanwhile instead of
		# freezing the leg for those ticks. Preserve the true reach failure.
		if not String(_action.get("kind", "")).to_upper() in NORMAL_CONTROL_KINDS or not SURFACES.has(surface) or surface == "SOLE":return false
		var pursuit_side:=side_suffix(side)
		var foot_id:=cached_bone_id("foot."+pursuit_side)
		var hip:=skeleton.get_bone_global_pose(cached_bone_id("thigh."+pursuit_side)).origin
		var direction:=skeleton.global_basis.inverse()*world_direction
		direction.y=0
		if direction.length_squared()<.00001:direction=Vector3.FORWARD
		var rotation:=_surface08.rotation(self,side,surface,world_target,world_direction)
		var socket_id:=cached_bone_id("contact_"+String(SURFACES[surface])+"."+pursuit_side)
		var offset:=skeleton.get_bone_global_rest(socket_id).origin-skeleton.get_bone_global_rest(foot_id).origin
		var ankle:=skeleton.to_local(world_target)-rotation*offset
		var maximum:=skeleton.get_bone_rest(cached_bone_id("shin."+pursuit_side)).origin.length()+skeleton.get_bone_rest(foot_id).origin.length()-.012
		var vector:=ankle-hip
		if vector.length()<.04:return false
		ankle=hip+vector.limit_length(maximum)
		if not _solve_leg(pursuit_side,ankle,rotation,direction):return false
	var nt := float(_action.get("normalized_time", .5))
	var recover_start := .65 if String(_action.get("kind", "")).to_upper() in NORMAL_CONTROL_KINDS else .73
	var weight := smoothstep(0.0, .28, nt)*(1.0-smoothstep(recover_start, 1.0, nt))
	# The host already interpolates an ordinary world_target for PREPARE and
	# RECOVER. Applying another pose envelope delayed a 40ms windup twice.
	# Its explicit target owns the path; the real-foot servo still bounds travel.
	if String(_action.get("kind", "")).to_upper() in NORMAL_CONTROL_KINDS and _action.has("world_target"):weight=1.0
	if String(_action.get("phase", "")).to_upper() == "CONTACT": weight = 1.0
	var suffix := side_suffix(side)
	for name in ["thigh.", "shin.", "foot.", "toe."]:
		var i := cached_bone_id(name+suffix)
		skeleton.set_bone_pose_rotation(i, (previous[i] as Quaternion).slerp(skeleton.get_bone_pose_rotation(i), weight))
	if String(_action.get("kind", "")).to_upper() in NORMAL_CONTROL_KINDS and _last_local_ankles.has(suffix):
		# World targets can jump when the host alternates a foot with a 40ms
		# windup. Bound real local foot travel; contact stays invalid until the
		# actual skinned socket reaches it, rather than snapping at CONTACT.
		var goal := skeleton.get_bone_global_pose(cached_bone_id("foot."+suffix))
		var last: Dictionary = _last_local_ankles[suffix]
		var point := (last["point"] as Vector3)+(goal.origin-(last["point"] as Vector3)).limit_length(_foot_speed_limit(suffix)*_pose_delta)
		var old_rotation: Quaternion = last["rotation"]
		var rotation := goal.basis.get_rotation_quaternion()
		var angle := old_rotation.angle_to(rotation)
		if angle > .000001: rotation = old_rotation.slerp(rotation,minf(1.0,12.0*_pose_delta/angle))
		_solve_leg(suffix,point,rotation,skeleton.global_basis.inverse()*world_direction)
	return true

func get_motion_debug() -> Dictionary:
	return {"clip": _clip, "base_clip": _base_clip, "action_layer": _action_layer, "phase": _phase, "cadence_cycles_per_second": _cadence, "plants": _plants.duplicate(true), "plant_releases": _plant_releases, "blend_progress": minf(1.0, _blend_time/_blend_duration), "color_preset": _preset, "guard_reason": _guard_reason, "control_stance":_control_stance,"stance_rejected":_stance_rejected,"revision": "common_hotfix/foot_contact_03"}
