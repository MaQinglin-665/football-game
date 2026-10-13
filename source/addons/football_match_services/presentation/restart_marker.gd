class_name FBMatchRestartMarker
extends Node3D

var _ring: MeshInstance3D
var _label: Label3D

func _ready() -> void:
	_ring = MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = .47
	mesh.outer_radius = .51
	mesh.rings = 40
	mesh.ring_segments = 6
	_ring.mesh = mesh
	_ring.scale.y = .20
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("e2bf55")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring.material_override = material
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_label = Label3D.new()
	_label.font_size = 26
	_label.pixel_size = .006
	_label.outline_size = 3
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position.y = 1.45
	add_child(_label)
	visible = false

func update_snapshot(status: Dictionary) -> void:
	var phase: String = str(status.get("state", ""))
	var restart: Dictionary = status.get("restart", {})
	visible = phase in ["RESTART_SETUP", "RESTART_READY"] and restart.has("point")
	if not visible or _label == null:
		return
	global_position = restart["point"] + Vector3.UP * .025
	var progress: Dictionary = status.get("restart_progress", {})
	var jersey: int = int(progress.get("taker_jersey", -1))
	var name_text := "#%d" % jersey if jersey >= 0 else str(progress.get("taker_name", "指定球员"))
	_label.text = "%s · %s\n%s" % ["蓝队" if int(restart.get("team", 0)) == 0 else "珊瑚队", name_text,
		"可执行" if phase == "RESTART_READY" else "走到重启点"]
