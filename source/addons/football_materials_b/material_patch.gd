class_name FootballMaterialsBPatch
extends RefCounted

const TurfMaterial = preload("materials/turf_filtered.tres")
const LeatherShader = preload("res://scripts/ball_leather.gdshader")

static func install(stadium: Node3D, library: RefCounted, ball_visual: MeshInstance3D = null,
		correct_stand_palette: bool = true, material_quality: String = "balanced") -> Dictionary:
	var changed: Dictionary = {}
	var slots: Dictionary = {}
	if library != null:
		var existing = library.get("slots")
		if existing is Dictionary:
			slots = existing
	if stadium == null or not stadium.has_method("replace_material"):
		return {"error": "stadium must provide named replace_material"}
	var turf: ShaderMaterial = TurfMaterial.duplicate()
	set_turf_quality(turf, material_quality)
	if stadium.has_method("get_layout"):
		var layout: Dictionary = stadium.call("get_layout")
		turf.set_shader_parameter("mowing_band_m", float(layout.get("field_half_length", 52.5)) * 2.0 / 14.0)
	slots["pitch_grass"] = turf
	changed["Turf"] = stadium.call("replace_material", "Turf", turf)
	if correct_stand_palette:
		# Keep the two authored seat colours distinct. Full instance tints are an optional cost.
		var instance_tints: bool = material_quality == "detail"
		var blue := _standard(Color(0.192157, 0.435294, 0.607843), instance_tints)
		var navy := _standard(Color(0.086275, 0.223529, 0.345098), instance_tints)
		var concrete := _standard(Color(0.482353, 0.521569, 0.556863), instance_tints)
		for entry in [["SeatBlue", blue], ["SeatNavy", navy], ["Concrete", concrete]]:
			changed[entry[0]] = stadium.call("replace_material", entry[0], entry[1])
		slots["seat_blue"] = blue
		slots["seat_navy"] = navy
		slots["stand_concrete"] = concrete
	if ball_visual != null and ball_visual.mesh != null and ball_visual.mesh.get_surface_count() >= 2:
		ball_visual.material_override = null
		var dark := _leather(Color("17252b"), .58)
		var white := _leather(Color("dfe3d7"), .59)
		ball_visual.set_surface_override_material(0, dark)
		ball_visual.set_surface_override_material(1, white)
		slots["ball_dark"] = dark
		slots["ball_white"] = white
		changed["ball_surfaces"] = 2
	preload("res://scripts/stadium_finish.gd").apply(stadium,material_quality)
	return changed

static func set_turf_quality(turf: ShaderMaterial, quality: String = "balanced") -> void:
	# Low: no texture fetch. Balanced: blade + rotated macro fetch of one 512px texture.
	# Detail: also restore instance tints and keep blade normals visible further out.
	turf.set_shader_parameter("close_detail_enabled", quality != "low")
	turf.set_shader_parameter("detail_strength", .20)
	turf.set_shader_parameter("detail_fade_end_m", 80.0 if quality == "detail" else 55.0)

static func _standard(color: Color, instance_tints: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .94
	material.metallic_specular = .10
	material.vertex_color_use_as_albedo = instance_tints
	return material

static func _leather(color: Color, roughness: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = LeatherShader
	material.set_shader_parameter("panel_color", color)
	material.set_shader_parameter("roughness_value", roughness)
	return material
