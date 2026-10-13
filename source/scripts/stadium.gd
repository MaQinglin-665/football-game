class_name SmallStadium
extends RefCounted

static func build(parent: Node3D, width: float, length: float) -> void:
	var arena := Node3D.new()
	arena.name = "Stadium"
	parent.add_child(arena)
	box(arena, Vector3(120, 0.4, 120), Vector3(0, -0.20, 0), Color("c2baa2"), true)
	box(arena, Vector3(width * 2 + 0.6, 0.08, length * 2 + 0.6), Vector3(0, -0.025, 0), Color("457763"))
	for i in range(10):
		box(arena, Vector3(width * 2, 0.01, length * 0.2), Vector3(0, 0.023, -length + length * 0.1 + i * length * 0.2), Color("4b8167") if i % 2 else Color("47795e"))
	var white := Color("eee8cd")
	for x in [-width, width]:
		box(arena, Vector3(0.09, 0.016, length * 2), Vector3(x, 0.039, 0), white)
	for z in [-length, 0.0, length]:
		box(arena, Vector3(width * 2, 0.016, 0.09), Vector3(0, 0.039, z), white)
	var circle := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 3.92
	ring.outer_radius = 4.0
	ring.rings = 64
	ring.ring_segments = 6
	circle.mesh = ring
	circle.scale.y = 0.13
	circle.position.y = 0.044
	circle.material_override = material(white)
	arena.add_child(circle)
	for side in [-1.0, 1.0]:
		for x in [-8.0, 8.0]:
			box(arena, Vector3(0.09, 0.017, 8.0), Vector3(x, 0.039, side * (length - 4.0)), white)
		box(arena, Vector3(16.0, 0.017, 0.09), Vector3(0, 0.039, side * (length - 8.0)), white)
		goal(arena, side, length)
		for x in [-width, width]:
			box(arena, Vector3(0.08, 1.0, 0.08), Vector3(x, 0.5, side * length), Color("ead5a2"))
			box(arena, Vector3(0.35, 0.23, 0.035), Vector3(x + 0.15, 0.87, side * length), Color("ed7755"))
	# Low perimeter boards leave generous, readable space around the pitch.
	for x in [-width - 3.7, width + 3.7]:
		box(arena, Vector3(0.3, 1.0, length * 2 + 10), Vector3(x, 0.5, 0), Color("234957"))
		box(arena, Vector3(0.35, 0.10, length * 2 + 10), Vector3(x, 1.04, 0), Color("e8d9b6"))
		for z in [-length, -length * 0.6, -length * 0.2, length * 0.2, length * 0.6, length]:
			box(arena, Vector3(0.13, 3.2, 0.13), Vector3(x, 2.7, z), Color("31454c"))
		for y in [1.65, 2.3, 2.95, 3.6, 4.25]:
			box(arena, Vector3(0.02, 0.012, length * 2 + 10), Vector3(x, y, 0), Color("7f8d86"))
	for z in [-length - 5.0, length + 5.0]:
		box(arena, Vector3(width * 2 + 8, 1.0, 0.3), Vector3(0, 0.5, z), Color("234957"))
		box(arena, Vector3(width * 2 + 8, 0.10, 0.35), Vector3(0, 1.04, z), Color("e8d9b6"))
	for x in [-width - 9.0, width + 9.0]:
		for z in [-18.0, 18.0]:
			box(arena, Vector3(0.20, 8, 0.20), Vector3(x, 4, z), Color("3b5355"))
			box(arena, Vector3(1.8, 0.4, 0.7), Vector3(x, 8.1, z), Color("fff3d0"))
	# A restrained backdrop of trees and small buildings, all original geometry.
	for i in range(14):
		var x := (-1 if i % 2 == 0 else 1) * (width + 11.0 + float(i % 3) * 3)
		var z := -length - 10.0 + float(i / 2) * 13
		box(arena, Vector3(0.55, 2.5, 0.55), Vector3(x, 1.25, z), Color("78634d"))
		var crown := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 2.2
		mesh.height = 5.2
		mesh.radial_segments = 7
		mesh.rings = 4
		crown.mesh = mesh
		crown.position = Vector3(x, 4.2, z)
		crown.material_override = material(Color("567863"))
		arena.add_child(crown)
	for i in range(7):
		box(arena, Vector3(7, 5 + i % 3 * 2, 5), Vector3(-28 + i * 9, 2.5 + i % 3, -length - 12), Color("afad99") if i % 2 else Color("8d9a96"))
	var sign := Label3D.new()
	sign.text = "SMALL SIDE    /    %d v %d" % [parent.team_size, parent.team_size]
	sign.font_size = 92
	sign.pixel_size = 0.008
	sign.outline_size = 0
	sign.modulate = Color("efdfb9")
	sign.position = Vector3(0, 2.3, -length - 5.1)
	arena.add_child(sign)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("5d91aa")
	sky_material.sky_horizon_color = Color("d6d7bb")
	sky_material.ground_horizon_color = Color("d6d7bb")
	sky_material.ground_bottom_color = Color("a1a791")
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d7e7e7")
	environment.ambient_light_energy = 0.28
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	world.environment = environment
	parent.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.light_color = Color("fff0cc")
	sun.light_energy = 0.62
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 100
	parent.add_child(sun)

static func goal(parent: Node3D, side: float, length: float) -> void:
	var color := Color("ef8166") if side < 0 else Color("31b7c0")
	for x in [-3.0, 3.0]:
		box(parent, Vector3(0.14, 2.45, 0.14), Vector3(x, 1.225, side * length), Color("fff4d6"), true)
		box(parent, Vector3(0.10, 2.3, 0.10), Vector3(x, 1.15, side * (length + 2.2)), color)
		box(parent, Vector3(0.08, 0.08, 2.2), Vector3(x, 2.35, side * (length + 1.1)), color)
	box(parent, Vector3(6.14, 0.14, 0.14), Vector3(0, 2.45, side * length), Color("fff4d6"), true)
	box(parent, Vector3(6.0, 0.08, 0.08), Vector3(0, 2.35, side * (length + 2.2)), color)
	for x in range(13):
		box(parent, Vector3(0.025, 2.3, 0.025), Vector3(-3 + x * 0.5, 1.17, side * (length + 2.2)), Color("a8c2b4"))
	for y in range(6):
		box(parent, Vector3(6, 0.025, 0.025), Vector3(0, 0.07 + y * 0.45, side * (length + 2.2)), Color("a8c2b4"))
	box(parent, Vector3(6, 0.015, 2.2), Vector3(0, 0.032, side * (length + 1.1)), color.darkened(0.2))

static func material(color: Color) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.94
	return result

static func box(parent: Node3D, size: Vector3, at: Vector3, color: Color, solid := false) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.position = at
	visual.material_override = material(color)
	parent.add_child(visual)
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 6
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		body.add_child(collision)
		visual.add_child(body)
	return visual
