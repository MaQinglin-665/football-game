extends Node3D
## Isolated visual adapter. Applies no ball forces and owns no actor collision.
## Mount at an actor's ground origin. Call update_pose once per physics tick.

const MODEL := preload("res://addons/football_character/assets/footballer.glb")
const MANIFEST := "res://addons/football_character/assets/rig_manifest.json"
const SURFACES := {"INSIDE": "inner", "OUTSIDE": "outer", "INSTEP": "instep", "SOLE": "sole", "TOE": "toe", "HEEL":"heel"}

var visual: Node3D
var skeleton: Skeleton3D
var _bone_ids_perf:Dictionary={}
func cached_bone_id(bone_name:String)->int:
	if not _bone_ids_perf.has(bone_name):_bone_ids_perf[bone_name]=skeleton.find_bone(bone_name)
	return int(_bone_ids_perf[bone_name])
var animation_player: AnimationPlayer
var mesh_nodes: Array[MeshInstance3D] = []
var _action := {}
var _phase := 0.0
var _clip := ""
var _unreachable := false
var _reach_error := 0.0
var _socket_normals := {}
var _team := 0
var _jersey := 0
const SurfaceJoint08 := preload("res://addons/football_character/surface_joint_08.gd")
var _surface08 = SurfaceJoint08.new()

func _ready() -> void:
	ensure_loaded()

func collect(node: Node) -> void:
	if node is Skeleton3D: skeleton = node
	if node is AnimationPlayer: animation_player = node
	if node is MeshInstance3D: mesh_nodes.append(node)
	for child in node.get_children(): collect(child)

func ensure_loaded() -> void:
	if visual != null: return
	visual = MODEL.instantiate()
	add_child(visual)
	collect(visual)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	for bone in manifest.get("bones", []):
		if bone.has("surface_normal"):
			var n: Array = bone["surface_normal"]
			_socket_normals[bone["name"]] = Vector3(n[0], n[1], n[2])

func setup(team: int, jersey: int, first_person: bool) -> void:
	ensure_loaded()
	_team = team
	_jersey = jersey
	set_meta("jersey", jersey)
	var palette := {"TeamPrimary": Color("229CAC") if team == 0 else Color("DB775E"), "TeamSecondary": Color("163A4D") if team == 0 else Color("563C48")}
	for mesh_node in mesh_nodes:
		mesh_node.visible = not (first_person and String(mesh_node.name) in ["Head", "BodyCore"])
		for surface in mesh_node.mesh.get_surface_count():
			var original: StandardMaterial3D = mesh_node.mesh.surface_get_material(surface)
			if original.resource_name in palette:
				var material: StandardMaterial3D = original.duplicate()
				material.albedo_color = palette[original.resource_name]
				mesh_node.set_surface_override_material(surface, material)

func set_foot_action(action: Dictionary) -> void:
	_action = action.duplicate(true)
	_unreachable = false
	_reach_error = 0.0

func clear_foot_action() -> void:
	_action.clear()
	_unreachable = false
	_reach_error = 0.0

func side_suffix(side: int) -> String:
	return "L" if side <= 0 else "R"

func update_pose(delta: float, state: Dictionary) -> void:
	ensure_loaded()
	var forward: Vector3 = state.get("forward", -global_basis.z)
	forward.y = 0
	if forward.length_squared() > 0.0001:
		visual.global_rotation = Vector3(0, atan2(-forward.x, -forward.z), 0)
	var velocity: Vector3 = state.get("velocity", Vector3.ZERO)
	var speed := Vector2(velocity.x, velocity.z).length()
	var locomotion := String(state.get("locomotion", "idle" if speed < .08 else "walk")).to_lower()
	var clip := "Idle"
	if locomotion in ["run", "sprint"]: clip = "Run"
	elif locomotion == "dribble": clip = "Dribble"
	elif speed > .08 or locomotion in ["walk", "shield", "jockey", "start", "stop", "retreat"]: clip = "Walk"
	var playback := clampf(speed/(4.4 if clip == "Run" else 2.0 if clip == "Dribble" else 1.4), .45, 1.8) if clip != "Idle" else 1.0
	var base_duration: float = animation_player.get_animation(clip).length
	_phase = fposmod(_phase + maxf(delta, 0)*playback/base_duration, 1.0)
	if locomotion == "retreat": _phase = fposmod(_phase - 2*maxf(delta, 0)*playback/base_duration, 1.0)
	var seconds := _phase*base_duration
	if not _action.is_empty():
		var side := side_suffix(int(_action.get("side", 1)))
		var surface := String(_action.get("surface", "INSTEP")).to_upper()
		clip = ("SoleStop_" if surface == "SOLE" else "TouchInside_" if surface in ["INSIDE", "OUTSIDE"] else "TouchInstep_") + side
		seconds = clampf(float(_action.get("normalized_time", .5)), 0, 1)*animation_player.get_animation(clip).length
	animation_player.play(clip)
	animation_player.seek(seconds, true)
	animation_player.advance(0)
	animation_player.pause()
	_clip = clip
	skeleton.force_update_all_bone_transforms()
	if _action.has("world_target") and _action["world_target"] is Vector3:
		apply_foot_target(int(_action.get("side", 1)), String(_action.get("surface", "INSTEP")).to_upper(), _action["world_target"], _action.get("direction", forward))

func apply_foot_target(side: int, surface: String, world_target: Vector3, world_direction: Vector3) -> bool:
	var suffix := side_suffix(side)
	if not SURFACES.has(surface): return false
	var thigh_id := cached_bone_id("thigh."+suffix)
	var shin_id := cached_bone_id("shin."+suffix)
	var foot_id := cached_bone_id("foot."+suffix)
	var socket_id := foot_id if surface=="HEEL" else cached_bone_id("contact_"+String(SURFACES[surface])+"."+suffix)
	var hip := skeleton.get_bone_global_pose(thigh_id).origin
	var rest_upper := skeleton.get_bone_rest(shin_id).origin
	var rest_lower := skeleton.get_bone_rest(foot_id).origin
	var a := rest_upper.length()
	var b := rest_lower.length()
	var direction := skeleton.global_basis.inverse()*world_direction
	direction.y = 0
	if direction.length_squared() < .00001: direction = Vector3.FORWARD
	var foot_rotation := _surface08.rotation(self,side,surface,world_target,world_direction)
	var offset := Vector3(0,-.035,.045) if surface=="HEEL" else skeleton.get_bone_global_rest(socket_id).origin - skeleton.get_bone_global_rest(foot_id).origin
	var ankle := skeleton.to_local(world_target) - foot_rotation*offset
	var vector := ankle-hip
	var distance := vector.length()
	_reach_error = maxf(0, distance-(a+b))
	_unreachable = distance > a+b-.0001 or distance < absf(a-b)+.025
	if _unreachable:
		return false
	var axis := vector.normalized()
	var forward := _surface08.pole_direction(self,suffix,foot_rotation,direction).normalized()
	var pole := forward-axis*forward.dot(axis)
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
	skeleton.set_bone_pose_rotation(cached_bone_id("toe."+suffix), Quaternion.IDENTITY)
	skeleton.force_update_all_bone_transforms()
	return true

func get_foot_contact(side: int, surface: String) -> Dictionary:
	var actor39:Node=get_parent()
	if actor39!=null and actor39.has_method("ensure_contact_pose_current"):actor39.ensure_contact_pose_current()
	ensure_loaded()
	surface = surface.to_upper()
	if not SURFACES.has(surface): return {"valid": false, "surface": surface, "reach_error": INF}
	var suffix := side_suffix(side)
	var socket_name := "contact_"+String(SURFACES[surface])+"."+suffix
	var socket_id := cached_bone_id("foot."+suffix) if surface=="HEEL" else cached_bone_id(socket_name)
	var pose := skeleton.get_bone_global_pose(socket_id)
	var point := skeleton.to_global(pose*Vector3(0,-.035,.045) if surface=="HEEL" else pose.origin)
	var source_normal: Vector3 = Vector3.BACK if surface=="HEEL" else _socket_normals.get(socket_name, Vector3.FORWARD)
	var normal := (skeleton.global_basis*pose.basis*source_normal).normalized()
	var foot_pose := skeleton.get_bone_global_pose(cached_bone_id("foot."+suffix))
	var boot_center := skeleton.to_global(foot_pose.origin + foot_pose.basis*Vector3(0, -.050, -.080))
	var active_side := int(_action.get("side", side))
	var target_error := _reach_error
	var valid := true
	if not _action.is_empty() and side_suffix(active_side) == suffix:
		valid = not _unreachable
		if _action.has("world_target"):
			target_error = maxf(target_error, point.distance_to(_action["world_target"]))
			valid = valid and target_error <= .035
	return {"valid": valid, "point": point, "normal": normal, "boot_center": boot_center, "surface": surface, "reach_error": target_error}

func get_control_joint_state()->Dictionary:
	var actor39:Node=get_parent()
	if actor39!=null and actor39.has_method("ensure_contact_pose_current"):actor39.ensure_contact_pose_current()
	return _surface08.snapshot(self)

func set_joint_pose_mode(selected:String)->void:
	selected=selected.to_upper()
	if not selected in ["A","B"] or selected==_surface08.mode:return
	_surface08.mode=selected
	if has_method("invalidate_pose_snapshot"):call("invalidate_pose_snapshot")

func get_joint_pose_mode()->String:return _surface08.mode
