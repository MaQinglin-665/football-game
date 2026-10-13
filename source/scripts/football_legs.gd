class_name FootballLegRig
extends RefCounted

static func create(parent: Node3D, kit: Color, skin: Color, boot_color: Color, shadows := true) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for sign_value in [-1.0,1.0]:
		var upper := segment(parent,0.072,skin,shadows)
		var lower := segment(parent,0.055,Color("e6e2d6"),shadows)
		var boot := Node3D.new()
		parent.add_child(boot)
		part(boot,Vector3(0.145,0.075,0.27),Vector3(0,0,0),boot_color,shadows)
		part(boot,Vector3(0.152,0.015,0.282),Vector3(0,-0.04,-0.003),Color("20353c"),shadows)
		var toe := MeshInstance3D.new()
		var rounded := SphereMesh.new()
		rounded.radius = 0.070
		rounded.height = 0.080
		rounded.radial_segments = 14
		rounded.rings = 6
		toe.mesh = rounded
		toe.position = Vector3(0,0.003,-0.080)
		toe.material_override = material(boot_color)
		toe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		boot.add_child(toe)
		for lace_z in [-0.055,-0.022,0.010]:
			part(boot,Vector3(0.084,0.004,0.012),Vector3(0,0.042,lace_z),Color("eff3e6"),shadows)
		for stud_x in [-0.046,0.046]:
			for stud_z in [-0.092,0.065]:
				part(boot,Vector3(0.021,0.019,0.025),Vector3(stud_x,-0.053,stud_z),kit.darkened(0.4),shadows)
		rows.append({"side":sign_value,"upper":upper,"lower":lower,"boot":boot})
	return rows

static func pose(row: Dictionary, hip: Vector3, toe: Vector3, facing: Vector3) -> void:
	var foot := toe-facing*0.115
	foot.y = toe.y
	var difference := foot-hip
	var distance := clampf(difference.length(),0.1,0.878)
	var axis := difference.normalized()
	var bend := facing-axis*facing.dot(axis)
	if bend.length() < 0.01:
		bend = Vector3.FORWARD
	bend = bend.normalized()
	var upper_length := 0.445
	var lower_length := 0.44
	var along := (upper_length*upper_length-lower_length*lower_length+distance*distance)/(2*distance)
	var height := sqrt(maxf(0,upper_length*upper_length-along*along))
	var knee := hip+axis*along+bend*height
	link_segment(row.upper,hip,knee)
	link_segment(row.lower,knee,foot)
	row.boot.global_position = foot
	row.boot.global_rotation = Vector3(0,atan2(-facing.x,-facing.z),0)

static func link_segment(mesh: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	mesh.global_position = (a+b)*0.5
	mesh.global_basis = Basis(Quaternion(Vector3.UP,(b-a).normalized())).scaled(Vector3(1,a.distance_to(b),1))

static func material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	return mat

static func segment(parent: Node3D, radius: float, color: Color, shadows: bool) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius*0.78
	mesh.height = 1
	mesh.radial_segments = 14
	node.mesh = mesh
	node.material_override = material(color)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

static func part(parent: Node3D, size: Vector3, at: Vector3, color: Color, shadows: bool) -> void:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = at
	node.material_override = material(color)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
