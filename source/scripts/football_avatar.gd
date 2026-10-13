class_name FootballAvatar
extends RefCounted

# Original, articulated low-poly geometry; no external model or rig dependency.
static func build(parent: Node3D, team: int, jersey: int) -> Dictionary:
	var kit := Color("20adb9") if team == 0 else Color("ed725a")
	var dark := Color("153c49") if team == 0 else Color("703743")
	var skin_tones := [Color("ddb08d"), Color("b98159"), Color("855a40")]
	var skin: Color = skin_tones[jersey % skin_tones.size()]
	var root := Node3D.new()
	parent.add_child(root)
	_cylinder(root, 0.33, 0.27, 0.64, Vector3(0, 0.22, 0), kit, 6)
	_cylinder(root, 0.29, 0.30, 0.22, Vector3(0, -0.20, 0), dark, 8)
	_cylinder(root, 0.105, 0.10, 0.13, Vector3(0, 0.58, 0), skin)
	_cylinder(root, 0.13, 0.16, 0.045, Vector3(0, 0.54, 0), dark)
	_sphere(root, 0.215, 0.43, Vector3(0, 0.79, 0), skin)
	_sphere(root, 0.222, 0.18, Vector3(0, 0.94, 0.01), Color("30313a"))
	for x in [-0.07, 0.07]:
		_box(root, Vector3(0.033, 0.025, 0.018), Vector3(x, 0.82, -0.20), Color("2c302f"))
	_box(root, Vector3(0.07, 0.04, 0.045), Vector3(0, 0.77, -0.218), skin.lightened(0.08))
	var arms: Array[Node3D] = []
	var legs: Array[Node3D] = []
	var knees: Array[Node3D] = []
	for side in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(side * 0.34, 0.44, 0)
		arm.rotation.z = side * 0.12
		root.add_child(arm)
		_cylinder(arm, 0.105, 0.09, 0.26, Vector3(0, -0.13, 0), kit)
		var forearm := Node3D.new()
		forearm.position.y = -0.26
		forearm.rotation.x = -0.20
		arm.add_child(forearm)
		_cylinder(forearm, 0.08, 0.064, 0.28, Vector3(0, -0.14, 0), skin)
		_sphere(forearm, 0.071, 0.16, Vector3(0, -0.32, 0), skin)
		arms.append(arm)
	var leg_rows := FootballLegRig.create(parent,kit,skin,dark)
	for row in leg_rows:
		legs.append(row.upper)
		knees.append(row.lower)
	for z in [-0.345, 0.345]:
		var number := Label3D.new()
		number.text = str(jersey)
		number.font_size = 52
		number.pixel_size = 0.0038
		number.modulate = Color("fff8e5")
		number.outline_size = 0
		number.position = Vector3(0, 0.25, z)
		if z < 0:
			number.rotation.y = PI
		root.add_child(number)
	return {"root": root, "arms": arms, "legs": legs, "knees": knees, "leg_rows": leg_rows}

static func _cylinder(parent: Node3D, top: float, bottom: float, height: float, at: Vector3, color: Color, segments := 8) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = segments
	_mesh(parent, mesh, at, color)

static func _sphere(parent: Node3D, radius: float, height: float, at: Vector3, color: Color) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 5
	_mesh(parent, mesh, at, color)

static func _box(parent: Node3D, size: Vector3, at: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_mesh(parent, mesh, at, color)

static func _mesh(parent: Node3D, mesh: Mesh, at: Vector3, color: Color) -> void:
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	visual.material_override = material
	parent.add_child(visual)
