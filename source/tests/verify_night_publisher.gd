extends SceneTree
const Night := preload("res://addons/stadium_night/night_profile.gd")
const FIELD_LIGHT_LAYER := 1 << 19
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
	var world: WorldEnvironment = game.get_node("MatchEnvironment")
	var main: DirectionalLight3D = game.get_node("MatchSun")
	var rig: Node3D = stadium.get_node_or_null("NightFixtureRig")
	var library: RefCounted = game.services.materials
	check("ordinary publisher0.6.12 startup selects night low", rig != null and world.get_meta("stadium_lighting_mode", "") == "night" and world.get_meta("stadium_night_quality", "") == "low")
	check("low startup adds zero realtime lights", active_lights(game).size() == 1 and game.find_children("*", "Light3D", true, false).size() == 1)
	check("rolled back world scoreboard stays absent", stadium.get_node_or_null("WorldScoreboards") == null and not FileAccess.file_exists("res://addons/stadium_presentation/scoreboard_install.gd"))
	Night.apply(stadium, world, main, "daylight", "low", root, library, false)
	var objects := object_ids(world, main)
	var geometry := geometry_signature(stadium)
	var collisions := collision_signature(stadium)
	var layers := all_layers(game)
	var layout: Dictionary = stadium.get_layout().duplicate(true)
	var rules_before: Dictionary = game.services.rules.snapshot().duplicate(true)
	var strip: MeshInstance3D = stadium.get_node("Roof/FloodlightStrips")
	var strip_original := strip.material_override
	var materials := material_signature(stadium)
	var original_mask := main.light_cull_mask
	var original_sky_mode := main.sky_mode
	var low := Night.apply(stadium, world, main, "night", "low", root, library, false)
	check("existing environment sky material and main light are reused", object_ids(world, main) == objects and game.find_children("*", "WorldEnvironment", true, false).size() == 1)
	check("deep indigo sky has no procedural sun", world.environment.sky.sky_material.sky_top_color.is_equal_approx(Color("040815")) and main.sky_mode == DirectionalLight3D.SKY_MODE_LIGHT_ONLY)
	check("ambient floor and main energy protect field readability controls", world.environment.ambient_light_energy >= 0.22 and main.light_energy >= 0.90 and world.environment.tonemap_exposure == 1.0)
	check("neutral main lighting avoids strong blue team tint", absf(main.light_color.r - main.light_color.b) < 0.04 and main.light_color.is_equal_approx(Color("fffdfa")))
	check("field ball and all 22 actors receive the main light", field_targets_lit(game, main.light_cull_mask), {"actors": game.players.size(), "adapted_geometries": rig.field_mesh_count})
	check("stands retain original visibility layers and ambient lighting", stadium.get_node("Bowl/Tier3/Seats_00").layers == int(layers[String(stadium.get_node("Bowl/Tier3/Seats_00").get_path())]) and (stadium.get_node("Bowl/Tier3/Seats_00").layers & main.light_cull_mask) == 0)
	check("original layer bits remain visible to the camera", layers_preserved(game, layers) and (game.player.camera.cull_mask & FIELD_LIGHT_LAYER) != 0)
	check("low keeps one shadowed main and a 2048 two split budget", active_shadowed(game) == 1 and main.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS and main.directional_shadow_max_distance == 60.0 and low.shadow_atlas == 2048)
	check("low AA grass and LOD remain bounded", root.msaa_3d == Viewport.MSAA_DISABLED and library.get("slots").pitch_grass.get_shader_parameter("close_detail_enabled") == false and stadium.seat_lod_near_distance == 55.0 and stadium.seat_lod_mid_distance == 80.0)
	check("GI fog glow and PCSS remain disabled", not world.environment.sdfgi_enabled and not world.environment.ssao_enabled and not world.environment.ssil_enabled and not world.environment.ssr_enabled and not world.environment.glow_enabled and not world.environment.fog_enabled and not world.environment.volumetric_fog_enabled and main.light_angular_distance == 0.0)
	check("lamp faces reuse original roof strips", strip.material_override == rig.lamp_material and rig.lamp_material.emission_enabled and not strip.cast_shadow)
	check("eight roof banks and warm accents have exactly the stated geometry budget", rig.bank_positions.size() == 8 and rig.find_children("*", "GeometryInstance3D", true, false).size() == 2 and rig_triangles(rig) == 356 and rig_surfaces(rig) == 3, low.fixtures)
	check("new fixtures cast no shadow and stay above goal sightlines", rig.find_children("*", "GeometryInstance3D", true, false).all(func(node): return node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF) and rig.bank_positions.all(func(pos): return pos.y > game.goal_height + 25.0))
	check("original stadium meshes instance counts and collisions are unchanged", geometry_signature(stadium) == geometry and collision_signature(stadium) == collisions and stadium.get_layout() == layout)
	check("turf stand and goal material objects are unchanged", material_signature(stadium) == materials)
	var mesh_ids := fixture_mesh_ids(rig)
	Night.apply(stadium, world, main, "night", "low", root, library, false)
	check("repeated install reuses cached fixtures without frame work", fixture_mesh_ids(rig) == mesh_ids and not rig.is_processing() and not rig.is_physics_processing() and rig.find_children("*", "SubViewport", true, false).is_empty())
	var balanced := Night.apply(stadium, world, main, "night", "balanced", root, library, false)
	check("balanced adds just one shadowless spot fill", active_lights(game).size() == 2 and active_shadowed(game) == 1 and balanced.new_active_lights == 1 and rig.fill != null and not rig.fill.shadow_enabled)
	check("balanced fill stays limited to the field with no specular glare", rig.fill.light_cull_mask == FIELD_LIGHT_LAYER and rig.fill.light_specular == 0.0 and rig.fill.spot_range <= 95.0 and is_equal_approx(rig.fill.light_energy, 0.18))
	check("balanced shadow atlas stays 2048 and quality is optional", balanced.shadow_atlas == 2048 and main.directional_shadow_max_distance == 70.0 and root.msaa_3d == Viewport.MSAA_2X)
	Night.apply(stadium, world, main, "night", "low", root, library, false)
	check("returning to low hides fill and keeps the same fixture meshes", active_lights(game).size() == 1 and not rig.fill.is_visible_in_tree() and fixture_mesh_ids(rig) == mesh_ids)
	check("invalid quality safely falls back to low", Night.apply(stadium, world, main, "night", "invalid", root, library, false).quality == "low")
	check("invalid lighting mode leaves existing state unchanged", Night.apply(stadium, world, main, "unknown", "low", root, library, false).has("error") and world.get_meta("stadium_lighting_mode") == "night")
	Night.apply(stadium, world, main, "daylight", "low", root, library, false)
	check("daylight restores layers light mask sky mode and roof strip material", all_layers(game) == layers and main.light_cull_mask == original_mask and main.sky_mode == original_sky_mode and strip.material_override == strip_original)
	check("daylight hides all added visuals and optional light", not rig.is_visible_in_tree() and active_lights(game).size() == 1 and world.environment.sky.sky_material.sky_top_color.is_equal_approx(Color("4288cc")))
	check("quality switches do not replace sky or mutate rules and physics rate", object_ids(world, main) == objects and game.services.rules.snapshot() == rules_before and ProjectSettings.get_setting("physics/common/physics_ticks_per_second") == 120)
	var result := {"engine": Engine.get_version_info(), "display_server": DisplayServer.get_name(), "checks": checks,
		"passed": checks.all(func(entry): return entry.passed), "low": low, "balanced": balanced,
		"native_visual_and_frame_time_verified": false,
		"scope": "Headless code, state, light/layer/material budget and fallback checks. Not rendered exposure/colour/readability or dynamic FPS evidence."}
	FileAccess.open(ProjectSettings.globalize_path("res://../verification/night_checks.json"), FileAccess.WRITE).store_string(JSON.stringify(result, "\t") + "\n")
	game.shutdown_audio()
	await create_timer(0.12).timeout
	game.queue_free()
	await process_frame
	await process_frame
	quit(0 if result.passed else 1)

func object_ids(world: WorldEnvironment, main: DirectionalLight3D) -> Array:
	return [world.get_instance_id(), world.environment.get_instance_id(), world.environment.sky.get_instance_id(), world.environment.sky.sky_material.get_instance_id(), main.get_instance_id()]

func active_lights(game: Node) -> Array:
	return game.find_children("*", "Light3D", true, false).filter(func(light): return light.is_visible_in_tree() and light.light_energy > 0.0)

func active_shadowed(game: Node) -> int:
	return active_lights(game).filter(func(light): return light.shadow_enabled).size()

func all_layers(game: Node) -> Dictionary:
	var result := {}
	for node in game.find_children("*", "GeometryInstance3D", true, false):
		if "NightFixtureRig" not in String(node.get_path()):
			result[String(node.get_path())] = node.layers
	return result

func layers_preserved(game: Node, before: Dictionary) -> bool:
	var after := all_layers(game)
	for key in before:
		if (int(after[key]) & int(before[key])) != int(before[key]):
			return false
	return true

func field_targets_lit(game: Node3D, mask: int) -> bool:
	if game.players.size() != 22 or (game.ball.visual.layers & mask) == 0:
		return false
	for actor in game.players:
		var geometries: Array = actor.find_children("*", "GeometryInstance3D", true, false)
		if geometries.is_empty() or not geometries.all(func(node): return (node.layers & mask) != 0):
			return false
	var field: Node = game.stadium.get_node("Pitch")
	return field.find_children("*", "GeometryInstance3D", true, false).all(func(node): return (node.layers & mask) != 0)

func geometry_signature(stadium: Node3D) -> Dictionary:
	var result := {}
	for node in stadium.find_children("*", "GeometryInstance3D", true, false):
		var path := String(stadium.get_path_to(node))
		if path.begins_with("NightFixtureRig"):
			continue
		if node is MeshInstance3D:
			result[path] = [node.mesh.get_instance_id(), node.cast_shadow]
		elif node is MultiMeshInstance3D:
			result[path] = [node.multimesh.get_instance_id(), node.multimesh.instance_count, node.cast_shadow]
	return result

func collision_signature(stadium: Node3D) -> Dictionary:
	var result := {}
	for node in stadium.find_children("*", "CollisionObject3D", true, false):
		result[String(stadium.get_path_to(node))] = [node.collision_layer, node.collision_mask, node.get_shape_owners().size()]
	return result

func material_signature(stadium: Node3D) -> Dictionary:
	var result := {}
	for node in stadium.find_children("*", "GeometryInstance3D", true, false):
		var path := String(stadium.get_path_to(node))
		if path.begins_with("NightFixtureRig") or path == "Roof/FloodlightStrips":
			continue
		result[path] = node.material_override.get_instance_id() if node.material_override != null else 0
	return result

func fixture_mesh_ids(rig: Node3D) -> Array:
	return rig.find_children("*", "MeshInstance3D", true, false).map(func(node): return node.mesh.get_instance_id())

func rig_triangles(rig: Node3D) -> int:
	var result := 0
	for node in rig.find_children("*", "MeshInstance3D", true, false):
		for surface in node.mesh.get_surface_count():
			result += node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX].size() / 3
	return result

func rig_surfaces(rig: Node3D) -> int:
	var result := 0
	for node in rig.find_children("*", "MeshInstance3D", true, false):
		result += node.mesh.get_surface_count()
	return result
