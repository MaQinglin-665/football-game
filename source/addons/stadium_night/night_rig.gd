extends Node3D
## Static fixtures and reversible rendering-layer adapter. No frame callbacks.
const Batch := preload("res://addons/modern_stadium/geometry_batch.gd")
const FIELD_LIGHT_LAYER := 1 << 19
var layer_rows: Array[Dictionary] = []
var light_rows: Dictionary = {}
var strip: MeshInstance3D
var strip_material: Material
var lamp_material: StandardMaterial3D
var fill: SpotLight3D
var bank_positions: Array[Vector3] = []
var field_mesh_count := 0

func build(stadium: Node3D, main: DirectionalLight3D) -> void:
	process_mode = Node.PROCESS_MODE_DISABLED
	light_rows = {"main": main, "cull_mask": main.light_cull_mask, "sky_mode": main.sky_mode, "specular": main.light_specular, "volumetric_energy": main.light_volumetric_fog_energy}
	strip = stadium.get_node_or_null("Roof/FloodlightStrips") as MeshInstance3D
	if strip:
		strip_material = strip.material_override
	var layout: Dictionary = stadium.call("get_layout")
	var half_width := float(layout.get("field_half_width", 34.0))
	var half_length := float(layout.get("field_half_length", 52.5))
	var lamp_y := 34.9
	if strip and strip.mesh:
		var centre := stadium.global_transform.affine_inverse() * (strip.global_transform * strip.get_aabb().get_center())
		lamp_y = centre.y - 0.45
	for side in [-1.0, 1.0]:
		for z in [-24.0, 24.0]:
			bank_positions.append(Vector3(side * (half_width + 7.5), lamp_y, z))
		for end in [-1.0, 1.0]:
			bank_positions.append(Vector3(side * (half_width + 6.0), lamp_y, end * (half_length + 7.5)))
	var cases := Batch.new()
	var lenses := Batch.new()
	for bank_position in bank_positions:
		var direction := Vector3(0.0, 1.0, 0.0) - bank_position
		var orientation := Basis.looking_at(direction.normalized(), Vector3.UP)
		cases.box(Vector3(5.8, 1.15, 0.38), bank_position, orientation)
		for x in [-2.35, 2.35]:
			cases.box(Vector3(0.12, 1.9, 0.14), bank_position + orientation * Vector3(x, 0.6, 0.05), orientation)
		for x in [-1.95, -0.65, 0.65, 1.95]:
			var lens := bank_position + orientation * Vector3(x, 0.0, -0.201)
			lenses.quad(lens + orientation * Vector3(-0.49, -0.36, 0), lens + orientation * Vector3(-0.49, 0.36, 0), lens + orientation * Vector3(0.49, 0.36, 0), lens + orientation * Vector3(0.49, -0.36, 0))
	var housing_material := StandardMaterial3D.new()
	housing_material.albedo_color = Color("627586")
	housing_material.roughness = 0.96
	housing_material.metallic_specular = 0.08
	_make_mesh("BatchedRoofHousings", cases.mesh(housing_material))
	lamp_material = _emissive(Color("f1f4fc"), 0.94)
	var faces: ArrayMesh = lenses.mesh(lamp_material)
	var warm := Batch.new()
	for side in [-1.0, 1.0]:
		var x: float = float(side) * (half_width + 15.2 - 1.02)
		# The two warm accents sit at existing player-tunnel mouths, facing inward.
		if side > 0:
			warm.quad(Vector3(x, 2.76, -2.1), Vector3(x, 2.96, -2.1), Vector3(x, 2.96, 2.1), Vector3(x, 2.76, 2.1))
		else:
			warm.quad(Vector3(x, 2.76, 2.1), Vector3(x, 2.96, 2.1), Vector3(x, 2.96, -2.1), Vector3(x, 2.76, -2.1))
	var warm_mesh: ArrayMesh = warm.mesh()
	faces.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, warm_mesh.surface_get_arrays(0))
	faces.surface_set_material(1, _emissive(Color("ffc88a"), 0.72))
	_make_mesh("BatchedLampFacesAndTunnelAccents", faces)
	visible = false

func _make_mesh(node_name: String, mesh: ArrayMesh) -> void:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.layers = FIELD_LIGHT_LAYER
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)

func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Compatibility unshaded renders albedo; keep lamp faces visibly coloured.
	material.albedo_color = Color(color.r * energy, color.g * energy, color.b * energy, 1.0)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

func activate(stadium: Node3D, main: DirectionalLight3D, balanced: bool) -> void:
	if layer_rows.is_empty():
		var host := stadium.get_parent()
		for branch_name in ["Pitch", "Goals"]:
			var branch := stadium.get_node_or_null(branch_name)
			if branch:
				_capture_branch(branch)
		var actors: Array = host.get("players")
		for actor in actors:
			if is_instance_valid(actor):
				_capture_branch(actor)
		var ball: Node = host.get("ball")
		if is_instance_valid(ball):
			_capture_branch(ball)
	for row in layer_rows:
		var node: GeometryInstance3D = row.node
		if is_instance_valid(node):
			node.layers = int(row.layers) | FIELD_LIGHT_LAYER
	main.light_cull_mask = FIELD_LIGHT_LAYER
	main.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	main.light_specular = 0.18
	if strip:
		strip.material_override = lamp_material
	visible = true
	if balanced and not is_instance_valid(fill):
		fill = SpotLight3D.new()
		fill.name = "OptionalShadowlessFill"
		fill.position = bank_positions[0]
		add_child(fill)
		fill.look_at(stadium.to_global(Vector3(0.0, 1.0, 0.0)), Vector3.UP)
		fill.light_color = Color("fffdfa")
		fill.light_energy = 0.18
		fill.light_specular = 0.0
		fill.light_cull_mask = FIELD_LIGHT_LAYER
		fill.shadow_enabled = false
		fill.spot_range = 95.0
		fill.spot_angle = 65.0
		fill.spot_attenuation = 0.8
		fill.light_volumetric_fog_energy = 0.0
	if is_instance_valid(fill):
		fill.visible = balanced

func _capture_branch(branch: Node) -> void:
	for node in branch.find_children("*", "GeometryInstance3D", true, false):
		layer_rows.append({"node": node, "layers": node.layers})
		field_mesh_count += 1

func deactivate() -> void:
	visible = false
	for row in layer_rows:
		if is_instance_valid(row.node):
			var node: GeometryInstance3D = row.node
			node.layers = int(row.layers)
	var main = light_rows.get("main")
	if is_instance_valid(main):
		main.light_cull_mask = int(light_rows.cull_mask)
		main.sky_mode = int(light_rows.sky_mode)
		main.light_specular = float(light_rows.specular)
		main.light_volumetric_fog_energy = float(light_rows.volumetric_energy)
	if is_instance_valid(strip):
		strip.material_override = strip_material
	if is_instance_valid(fill):
		fill.visible = false

func cost_contract() -> Dictionary:
	return {"roof_banks": bank_positions.size(), "cool_lenses": 32, "warm_accents": 2, "geometry_instances": 2, "surfaces": 3, "triangles": 356,
		"shadowless_fill_active": is_instance_valid(fill) and fill.is_visible_in_tree(), "adapted_geometry_layers": field_mesh_count,
		"frame_callbacks": false, "beam_meshes": 0, "subviewports": 0, "native_visual_and_frame_time_verified": false}

func _exit_tree() -> void:
	deactivate()
