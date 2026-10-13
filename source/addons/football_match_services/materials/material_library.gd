class_name FBMatchMaterialLibrary
extends RefCounted

const GrassShader = preload("grass.gdshader")
const LeatherShader = preload("leather.gdshader")
const NetShader = preload("net_grid.gdshader")
var slots: Dictionary = {}

func _init(overrides: Dictionary = {}) -> void:
	var grass := ShaderMaterial.new()
	grass.shader = GrassShader
	slots["pitch_grass"] = grass
	slots["pitch_line"] = _standard(Color("edf0df"), 0.94)
	slots["runoff"] = _standard(Color("626d64"), 0.99)
	slots["ball_white"] = _leather(Color("dfe3d7"), 0.59)
	slots["ball_dark"] = _leather(Color("17252b"), 0.58)
	slots["goal_frame"] = _standard(Color("edf1ed"), 0.32, 0.16)
	slots["goal_net"] = _standard(Color("c1cdca"), 0.85)
	var net := ShaderMaterial.new()
	net.shader = NetShader
	slots["goal_net_grid"] = net
	slots["stand_concrete"] = _standard(Color("89918a"), 0.98)
	slots["seat_blue"] = _standard(Color("24687a"), 0.68)
	slots["seat_coral"] = _standard(Color("b85b44"), 0.68)
	slots["referee_shirt"] = _standard(Color("decb50"), 0.92)
	for key in overrides:
		if overrides[key] is Material:
			slots[str(key)] = overrides[key]

func get_slot(slot: String) -> Material:
	return slots.get(slot)

func apply_modern_stadium(stadium: Node) -> Dictionary:
	# Align the separate stadium task's named slots without editing its meshes/paths.
	var mapping := {"Turf": "pitch_grass", "LinesWhite": "pitch_line", "GoalFrame": "goal_frame",
		"GoalNet": "goal_net", "Concrete": "stand_concrete", "SeatBlue": "seat_blue", "SeatNavy": "seat_blue"}
	var applied: Dictionary = {}
	if stadium.has_method("replace_material"):
		for stadium_slot in mapping:
			stadium.call("replace_material", stadium_slot, get_slot(mapping[stadium_slot]))
			applied[stadium_slot] = mapping[stadium_slot]
	return applied

func apply_named_slots(root: Node) -> Dictionary:
	var counts: Dictionary = {}
	_apply_tree(root, counts)
	return counts

func bind_ball_surfaces(mesh_instance: MeshInstance3D, dark_surface: int = 0, white_surface: int = 1) -> bool:
	if mesh_instance.mesh == null or mesh_instance.mesh.get_surface_count() <= maxi(dark_surface, white_surface):
		return false
	mesh_instance.material_override = null
	mesh_instance.set_surface_override_material(dark_surface, get_slot("ball_dark"))
	mesh_instance.set_surface_override_material(white_surface, get_slot("ball_white"))
	return true

func _apply_tree(node: Node, counts: Dictionary) -> void:
	if node is MeshInstance3D and node.has_meta("football_material_slot"):
		var slot := str(node.get_meta("football_material_slot"))
		var material := get_slot(slot)
		if material != null:
			node.material_override = material
			counts[slot] = int(counts.get(slot, 0)) + 1
	for child in node.get_children():
		_apply_tree(child, counts)

func _standard(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material

func _leather(color: Color, roughness: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = LeatherShader
	material.set_shader_parameter("panel_color", color)
	material.set_shader_parameter("roughness_value", roughness)
	return material
