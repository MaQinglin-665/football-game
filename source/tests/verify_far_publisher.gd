extends SceneTree
const Clarity := preload("res://addons/stadium_far_clarity/far_seats.gd")
var checks: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("run")

func check(label: String, passed: bool, detail: Variant = null) -> void:
	checks.append({"check": label, "passed": passed, "detail": detail})
	print("PASS " if passed else "FAIL ", label)

func run() -> void:
	AudioServer.set_bus_mute(0, true)
	var game: Node3D = load("res://scenes/match.tscn").instantiate()
	game.test_mode = true
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.physics_world.set_physics_process(false)
	for actor in game.players:
		actor.set_physics_process(false)
	var stadium: Node3D = game.stadium
	check("0.6.10 startup applies far-only candidate", stadium.has_meta("far_clarity_report"))
	Clarity.set_enabled(stadium, false)
	var near_mid := seat_signature(stadium)
	var before := proxy_signature(stadium)
	var node_count := stadium.find_children("*", "Node", true, false).size()
	var msaa := root.msaa_3d
	var layout: Dictionary = stadium.get_layout().duplicate(true)
	var collision := collision_signature(stadium)
	var env: Environment = game.get_node("MatchEnvironment").environment
	var sun: DirectionalLight3D = game.get_node("MatchSun")
	var lighting := [env.get_instance_id(), env.ambient_light_energy, sun.rotation, sun.light_energy]
	var report := Clarity.install(stadium)
	check("all authored far proxies are supported", report.changed_proxies == stadium.find_children("FarSeats_*", "MeshInstance3D", true, false).size() and report.skipped_proxies.is_empty(), report)
	check("coarse bands reduce geometry by over 75 percent", report.new_proxy_triangles < report.old_proxy_triangles * 0.25, report)
	check("near mid meshes transforms and instance counts remain identical", seat_signature(stadium) == near_mid)
	check("shared far materials keep existing blue colours without textures", report.shared_materials == 2 and stadium.find_children("FarSeats_*", "MeshInstance3D", true, false).all(func(node): return node.material_override.albedo_texture == null and node.material_override.metallic_specular == 0.0))
	check("each far proxy still uses one material surface", stadium.find_children("FarSeats_*", "MeshInstance3D", true, false).all(func(node): return node.mesh.get_surface_count() == 1))
	check("new far sheets stay within authored bounds", proxy_bounds_valid(stadium), report)
	check("layout physics and node count remain intact", stadium.get_layout() == layout and collision_signature(stadium) == collision and stadium.find_children("*", "Node", true, false).size() == node_count)
	check("lighting AA and physics ticks stay unchanged", root.msaa_3d == msaa and lighting == [env.get_instance_id(), env.ambient_light_energy, sun.rotation, sun.light_energy] and ProjectSettings.get_setting("physics/common/physics_ticks_per_second") == 120)
	var samples: Array[Dictionary] = []
	for camera in [Vector3(0, 1.65, 0), Vector3(0, 1.65, 45), Vector3(40, 18, 45), Vector3(0, 1.65, -45)]:
		stadium.update_detail_for_camera(camera)
		check("LOD remains exclusive at " + str(camera), lod_exclusive(stadium))
		samples.append({"camera": camera, "stats": stadium.get_detail_stats()})
	var after := proxy_signature(stadium)
	Clarity.install(stadium)
	check("repeated install reuses mesh and material objects", proxy_signature(stadium) == after)
	Clarity.set_enabled(stadium, false)
	check("rollback restores every original proxy mesh and material", proxy_signature(stadium) == before)
	Clarity.set_enabled(stadium, true)
	check("re-enable reuses candidate resources", proxy_signature(stadium) == after)
	check("world scoreboard remains absent", stadium.get_node_or_null("WorldScoreboards") == null)
	var result := {"engine": Engine.get_version_info(), "display_server": DisplayServer.get_name(), "checks": checks,
		"passed": checks.all(func(entry): return entry.passed), "geometry": report, "lod_samples": samples,
		"scope": "Headless geometry, LOD exclusivity, rollback and preservation checks. Not native clarity, shimmer, z-fighting or FPS evidence."}
	FileAccess.open(ProjectSettings.globalize_path("res://../verification/far_checks.json"), FileAccess.WRITE).store_string(JSON.stringify(result, "\t") + "\n")
	game.shutdown_audio()
	await create_timer(0.12).timeout
	game.queue_free()
	await process_frame
	await process_frame
	quit(0 if result.passed else 1)

func seat_signature(stadium: Node3D) -> Dictionary:
	var result := {}
	for node in stadium.find_children("Seats_*", "MultiMeshInstance3D", true, false):
		result[String(stadium.get_path_to(node))] = [node.multimesh.get_instance_id(), node.multimesh.instance_count, node.transform]
	return result

func proxy_signature(stadium: Node3D) -> Dictionary:
	var result := {}
	for node in stadium.find_children("FarSeats_*", "MeshInstance3D", true, false):
		result[String(stadium.get_path_to(node))] = [node.mesh.get_instance_id(), node.material_override.get_instance_id() if node.material_override else 0]
	return result

func collision_signature(stadium: Node3D) -> Dictionary:
	var result := {}
	for node in stadium.find_children("*", "CollisionObject3D", true, false):
		result[String(stadium.get_path_to(node))] = [node.collision_layer, node.collision_mask, node.get_shape_owners().size()]
	return result

func proxy_bounds_valid(stadium: Node3D) -> bool:
	for row in stadium.get_meta("far_clarity_state"):
		var old_bounds: AABB = row.old_mesh.get_aabb().grow(0.002)
		var new_bounds: AABB = row.new_mesh.get_aabb()
		if not old_bounds.encloses(new_bounds):
			return false
	return true

func lod_exclusive(stadium: Node3D) -> bool:
	for node in stadium.find_children("Seats_*", "MultiMeshInstance3D", true, false):
		var proxy: Node = node.get_parent().get_node_or_null("Far" + String(node.name))
		if proxy and node.visible and proxy.visible:
			return false
	return true
