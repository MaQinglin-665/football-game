extends RefCounted
## Five existing named material slots only. No geometry, mesh, LOD or textures change.
const COLORS := {"SeatNavy": "3e5869", "SeatBlue": "527184", "Concrete": "969b9d", "Metal": "b7bdc0", "Roof": "c1c5c4"}

static func apply(stadium: Node3D, library: RefCounted = null) -> Dictionary:
	if stadium.has_meta("daylight_palette_result"):
		return stadium.get_meta("daylight_palette_result").duplicate(true)
	var sources := {}
	for node in stadium.find_children("*", "GeometryInstance3D", true, false):
		var slot := String(node.get_meta("material_slot", ""))
		if not COLORS.has(slot) or sources.has(slot):
			continue
		var material: Material = node.material_override
		if material == null:
			var mesh: Mesh = node.mesh if node is MeshInstance3D else node.multimesh.mesh if node is MultiMeshInstance3D else null
			if mesh and mesh.get_surface_count() > 0:
				material = mesh.surface_get_material(0)
		if material is StandardMaterial3D:
			sources[slot] = material
	var result := {}
	for slot in sources:
		var material := sources[slot].duplicate() as StandardMaterial3D
		material.albedo_color = Color(COLORS[slot])
		material.roughness = 0.95
		material.metallic = 0.0
		material.metallic_specular = 0.10
		result[slot] = stadium.call("replace_material", slot, material)
		if library != null:
			var slots: Dictionary = library.get("slots")
			var library_slot: String = {"SeatNavy": "seat_navy", "SeatBlue": "seat_blue", "Concrete": "stand_concrete"}.get(slot, "")
			if not library_slot.is_empty():
				slots[library_slot] = material
	stadium.set_meta("daylight_palette_result", result.duplicate(true))
	return result
