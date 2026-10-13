extends RefCounted
## Original simple padded shells. Explicitly follow hand.L/R after the final pose.
## No new bones, no changes to the C mesh/materials, no collisions.

var skeleton: Skeleton3D
var anchors: Array[Node3D] = []
var meshes: Array[MeshInstance3D] = []
var enabled := false
var first_person := false
var team := 0
var _palm: StandardMaterial3D
var _cuff: StandardMaterial3D

func bind(rig: Skeleton3D, team_id: int, local_first_person: bool) -> void:
	skeleton = rig
	team = team_id
	first_person = local_first_person
	_palm = StandardMaterial3D.new()
	_palm.albedo_color = Color("e9edf0")
	_palm.roughness = .92
	_cuff = StandardMaterial3D.new()
	_cuff.albedo_color = Color("1d5fff" if team == 0 else "ffdd00" if team == 1 else "ef2532")
	_cuff.roughness = .85

func _build() -> void:
	for side in ["L", "R"]:
		var anchor := Node3D.new()
		anchor.name = "RoleKeeperGlove." + side
		skeleton.add_child(anchor)
		anchors.append(anchor)
		var sign_side := -1.0 if side == "L" else 1.0
		# Covers the C hand's rest-space bounds, with 3–8 mm padding.
		_box(anchor, Vector3(.098, .134, .078), Vector3(sign_side * .004, -.061, -.009), _palm)
		_box(anchor, Vector3(.104, .033, .082), Vector3(0, .014, -.002), _cuff)
		_box(anchor, Vector3(.037, .070, .042), Vector3(-sign_side * .040, -.051, -.008), _palm)
	refresh()

func _box(parent: Node3D, size: Vector3, offset: Vector3, material: StandardMaterial3D) -> void:
	var node := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	node.mesh = box
	node.material_override = material
	node.position = offset
	parent.add_child(node)
	meshes.append(node)

func configure(is_keeper: bool, local_first_person: bool) -> void:
	enabled = is_keeper
	first_person = local_first_person
	if enabled and anchors.is_empty():
		_build()
	refresh()

func refresh() -> void:
	if not is_instance_valid(skeleton):
		return
	for i in anchors.size():
		var side := "L" if i == 0 else "R"
		anchors[i].transform = skeleton.get_bone_global_pose(skeleton.find_bone("hand." + side))
		# C hides both RobotArm meshes for the local wearer; do not show floating
		# gloves beside that camera. Other players keep their visible gloves.
		anchors[i].visible = enabled and not first_person

func detach() -> void:
	for anchor in anchors:
		if is_instance_valid(anchor):
			anchor.free()
	anchors.clear()
	meshes.clear()

func get_geometry() -> Dictionary:
	if not enabled or not is_instance_valid(skeleton):
		return {}
	var hands := {}
	for side in ["L", "R"]:
		var sign_side := -1.0 if side == "L" else 1.0
		var bone := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("hand." + side))
		var centre := Vector3(sign_side * .004, -.061, -.009)
		hands[side] = {"bone_world": bone, "palm_point": bone * (centre + Vector3.FORWARD * .039), "palm_normal": (bone.basis * Vector3.FORWARD).normalized(), "padded_box_transform": bone * Transform3D(Basis.IDENTITY, centre), "padded_box_size_m": Vector3(.098, .134, .078)}
	return {"space": "world", "units": "metres", "hands": hands, "authority": "geometry_only; host owns legal hand control/contact/ball state", "shapes_created": false}
