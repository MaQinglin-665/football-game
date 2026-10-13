extends RefCounted
## Replace far-only row geometry with broad, low-contrast bands. Near/mid stay intact.
const Batch := preload("res://addons/modern_stadium/geometry_batch.gd")
const SEGMENTS_PER_SECTOR := 8
const VERTICES_PER_ROW := 64

static func install(stadium: Node3D, rows_per_band: int = 4) -> Dictionary:
	if stadium.has_meta("far_clarity_state"):
		set_enabled(stadium, true)
		return stadium.get_meta("far_clarity_report").duplicate(true)
	var rows: Array[Dictionary] = []
	var material_cache := {}
	var old_triangles := 0
	var new_triangles := 0
	var skipped: Array[String] = []
	for node in stadium.find_children("FarSeats_*", "MeshInstance3D", true, false):
		var old_mesh: Mesh = node.mesh
		if old_mesh == null or old_mesh.get_surface_count() != 1:
			skipped.append(String(node.name))
			continue
		var arrays := old_mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if vertices.is_empty() or vertices.size() % VERTICES_PER_ROW != 0:
			skipped.append(String(node.name))
			continue
		var source: Material = node.material_override
		if source == null:
			source = old_mesh.surface_get_material(0)
		if not source is StandardMaterial3D:
			skipped.append(String(node.name))
			continue
		var key := source.get_instance_id()
		if not material_cache.has(key):
			var material := source.duplicate() as StandardMaterial3D
			material.vertex_color_use_as_albedo = true
			material.roughness = 1.0
			material.metallic_specular = 0.0
			material_cache[key] = material
		var batch := Batch.new()
		var row_count := int(vertices.size() / VERTICES_PER_ROW)
		var span := maxi(3, rows_per_band)
		var band := 0
		for first in range(0, row_count, span):
			var next := mini(first + span, row_count)
			var tint := Color(0.965, 0.965, 0.965) if band % 2 == 0 else Color.WHITE
			for segment in SEGMENTS_PER_SECTOR:
				var lower: int = first * VERTICES_PER_ROW + segment * 8
				# Raise the continuous sheet to the authored seat-back top, above the
				# concrete treads. Its outer edge uses exact old-mesh vertices.
				var p := vertices[lower] + Vector3.UP * 0.385
				var q := vertices[lower + 1] + Vector3.UP * 0.385
				var outer_p: Vector3
				var outer_q: Vector3
				if next < row_count:
					var upper: int = next * VERTICES_PER_ROW + segment * 8
					outer_p = vertices[upper] + Vector3.UP * 0.385
					outer_q = vertices[upper + 1] + Vector3.UP * 0.385
				else:
					var upper: int = (row_count - 1) * VERTICES_PER_ROW + segment * 8
					outer_p = vertices[upper + 7]
					outer_q = vertices[upper + 6]
				batch.quad(p, q, outer_q, outer_p, Vector2.ONE, tint)
			band += 1
		var new_mesh: ArrayMesh = batch.mesh()
		rows.append({"node": node, "old_mesh": old_mesh, "old_material": node.material_override,
			"new_mesh": new_mesh, "new_material": material_cache[key]})
		old_triangles += int(arrays[Mesh.ARRAY_INDEX].size() / 3)
		new_triangles += int(new_mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() / 3)
	stadium.set_meta("far_clarity_state", rows)
	var report := {"changed_proxies": rows.size(), "skipped_proxies": skipped, "old_proxy_triangles": old_triangles,
		"new_proxy_triangles": new_triangles, "shared_materials": material_cache.size(), "rows_per_band": maxi(3, rows_per_band),
		"new_nodes": 0, "new_surfaces_per_proxy": 1, "textures_added": 0, "aa_changed": false,
		"near_mid_meshes_changed": false, "native_visual_and_frame_time_verified": false}
	stadium.set_meta("far_clarity_report", report)
	set_enabled(stadium, true)
	return report.duplicate(true)

static func set_enabled(stadium: Node3D, enabled: bool) -> void:
	var rows: Array = stadium.get_meta("far_clarity_state", [])
	for row in rows:
		var node: MeshInstance3D = row.node
		if is_instance_valid(node):
			node.mesh = row.new_mesh if enabled else row.old_mesh
			node.material_override = row.new_material if enabled else row.old_material
	stadium.set_meta("far_clarity_enabled", enabled)
