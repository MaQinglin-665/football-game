extends SceneTree
## Narrow current-host checks adapted from the module's environment validation.
const Daylight := preload("res://addons/stadium_presentation/daylight_profile.gd")
const Palette := preload("res://addons/stadium_presentation/appearance_palette.gd")
var checks: Array[Dictionary] = []
var output := ""

func _initialize() -> void:
	output = ProjectSettings.globalize_path("res://../verification/daylight_checks.json")
	call_deferred("run")

func check(name: String, passed: bool, details: Variant = null) -> void:
	checks.append({"check":name,"passed":passed,"details":details})
	print("PASS " if passed else "FAIL ",name)

func objects(game: Node3D) -> Array:
	var world: WorldEnvironment = game.get_node("MatchEnvironment")
	return [world.get_instance_id(),game.get_node("MatchSun").get_instance_id(),world.environment.get_instance_id(),world.environment.sky.get_instance_id(),world.environment.sky.sky_material.get_instance_id()]

func geometry(stadium: Node3D) -> Dictionary:
	var result := {}
	for node in stadium.find_children("*","GeometryInstance3D",true,false):
		if node is MeshInstance3D:
			result[String(stadium.get_path_to(node))] = [node.mesh.get_instance_id(),node.mesh.get_surface_count()]
		elif node is MultiMeshInstance3D:
			result[String(stadium.get_path_to(node))] = [node.multimesh.get_instance_id(),node.multimesh.mesh.get_instance_id(),node.multimesh.instance_count]
	return result

func collisions(stadium: Node3D) -> Dictionary:
	var result := {}
	for node in stadium.find_children("*","CollisionObject3D",true,false):
		result[String(stadium.get_path_to(node))] = [node.collision_layer,node.collision_mask,node.get_shape_owners().size()]
	return result

func run() -> void:
	AudioServer.set_bus_mute(0,true)
	# Construct the exact previous rendering branch, then apply components.
	root.set_meta("release_perf_active",true)
	root.set_meta("release_visual_baseline",true)
	var game: Node3D = load("res://scenes/match.tscn").instantiate()
	game.test_mode = true
	root.add_child(game)
	game.set_process(false)
	var world: WorldEnvironment = game.get_node("MatchEnvironment")
	var sun: DirectionalLight3D = game.get_node("MatchSun")
	var ids := objects(game)
	var layout: Dictionary = game.stadium.get_layout().duplicate(true)
	var mesh_signature := geometry(game.stadium)
	var collision_signature := collisions(game.stadium)
	var turf: Material = game.services.materials.slots.pitch_grass
	var ball_material: Material = game.ball.visual.get_surface_override_material(0)
	var net_material: Material = game.stadium.get_node("Goals/North/Net").material_override
	check("baseline branch preserves original balanced AA and shadows",root.msaa_3d==Viewport.MSAA_2X and sun.directional_shadow_max_distance==95.0)
	var palette := Palette.apply(game.stadium,game.services.materials)
	var low := Daylight.apply(game.stadium,world,sun,"low",root,game.services.materials)
	check("same original environment sun sky and sky material",objects(game)==ids)
	check("exactly one environment and one light",game.find_children("*","WorldEnvironment",true,false).size()==1 and game.find_children("*","Light3D",true,false).size()==1)
	check("five existing named material slots recolored",palette.size()==5 and palette.values().all(func(count):return int(count)>0),palette)
	check("pitch ball and goal net materials keep identity",game.services.materials.slots.pitch_grass==turf and game.ball.visual.get_surface_override_material(0)==ball_material and game.stadium.get_node("Goals/North/Net").material_override==net_material)
	check("mesh resources and multi-mesh instance counts retained",geometry(game.stadium)==mesh_signature)
	check("physics shapes and collision layers retained",collisions(game.stadium)==collision_signature)
	check("field dimensions and stadium anchors retained",game.stadium.get_layout()==layout)
	check("clear blue sky and neutral horizon",world.environment.sky.sky_material.sky_top_color.is_equal_approx(Color("4288cc")) and world.environment.sky.sky_material.sky_horizon_color.is_equal_approx(Color("d4e7f5")))
	check("white sun uses C reference direction",sun.rotation_degrees.is_equal_approx(Vector3(-54,-28,0)) and sun.light_color.is_equal_approx(Color("fffdf7")))
	check("low turns off AA and bounds shadow settings",root.msaa_3d==Viewport.MSAA_DISABLED and sun.directional_shadow_max_distance==70.0 and low.shadow_atlas==2048 and sun.directional_shadow_mode==DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS)
	check("low uses cheaper existing LOD distances",game.stadium.seat_lod_near_distance==55.0 and game.stadium.seat_lod_mid_distance==80.0 and game.stadium.net_lod_distance==24.0)
	check("low disables grass close detail",turf.get_shader_parameter("close_detail_enabled")==false)
	check("no new GI fog glow or PCSS",not world.environment.sdfgi_enabled and not world.environment.ssao_enabled and not world.environment.ssil_enabled and not world.environment.ssr_enabled and not world.environment.glow_enabled and not world.environment.volumetric_fog_enabled and not world.environment.fog_enabled and sun.light_angular_distance==0.0)
	var roof_material: Material = game.stadium.get_node("Roof/Canopy").material_override
	Palette.apply(game.stadium,game.services.materials)
	check("repeat palette install keeps allocated material",game.stadium.get_node("Roof/Canopy").material_override==roof_material)
	Daylight.apply(game.stadium,world,sun,"low",root,game.services.materials)
	check("repeat daylight install creates no new objects",objects(game)==ids and geometry(game.stadium)==mesh_signature)
	check("no world scoreboard bridge or labels installed",game.stadium.get_node_or_null("WorldScoreboards")==null)
	check("original two scoreboard visuals remain visible",game.stadium.get_node("Roof/NorthDisplay").visible and game.stadium.get_node("Roof/SouthDisplay").visible and game.stadium.get_node("Roof/DisplayHousings").visible)
	game.shutdown_audio()
	game.queue_free()
	await process_frame
	root.remove_meta("release_visual_baseline")
	root.remove_meta("release_perf_active")
	# Verify the actual ordinary-startup branch rather than only helper calls.
	game = load("res://scenes/match.tscn").instantiate()
	game.test_mode = true
	root.add_child(game)
	world = game.get_node("MatchEnvironment")
	sun = game.get_node("MatchSun")
	check("ordinary startup actually selects low",world.get_meta("daylight_profile","")=="low" and root.msaa_3d==Viewport.MSAA_DISABLED and sun.directional_shadow_max_distance==70.0)
	check("ordinary startup keeps no world scoreboard",game.stadium.get_node_or_null("WorldScoreboards")==null)
	check("full roster and physics frequency retained",game.players.size()==22 and game.agents.size()==21 and Engine.physics_ticks_per_second==120 and game.physics_world.actors.size()==22)
	check("ordinary grass close detail remains disabled",game.services.materials.slots.pitch_grass.get_shader_parameter("close_detail_enabled")==false)
	var result := {"engine":Engine.get_version_info(),"display_server":DisplayServer.get_name(),"checks":checks,"passed":checks.all(func(item):return item.passed),"low":low,"scope":"Headless current-host environment identity, geometry/collision preservation and real default-startup checks. No rendered visuals, dynamic FPS, full-match or human-feel acceptance."}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t")+"\n")
	game.shutdown_audio()
	game.queue_free()
	await process_frame
	call_deferred("finish",0 if result.passed else 1)

func finish(code: int) -> void:
	quit(code)
