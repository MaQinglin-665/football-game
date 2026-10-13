extends RefCounted
## Reuse the existing daylight environment/light and offer reversible night settings.
const Daylight := preload("res://addons/stadium_presentation/daylight_profile.gd")
const Rig := preload("night_rig.gd")
const PROFILES := {
	"low": {"shadow_distance": 60.0, "shadow_atlas": 2048, "msaa": Viewport.MSAA_DISABLED},
	"balanced": {"shadow_distance": 70.0, "shadow_atlas": 2048, "msaa": Viewport.MSAA_2X}
}

static func apply(stadium: Node3D, world: WorldEnvironment, main: DirectionalLight3D, mode: String = "night", quality: String = "low", viewport: Viewport = null, library: RefCounted = null, set_global_atlas: bool = true) -> Dictionary:
	if not is_instance_valid(stadium) or not is_instance_valid(world) or not is_instance_valid(main) or world.environment == null:
		return {"error": "Supply the existing stadium, WorldEnvironment and main light."}
	if world.environment.sky == null or not world.environment.sky.sky_material is ProceduralSkyMaterial:
		return {"error": "Preserve the existing sky; no replacement environment is created."}
	if mode not in ["night", "daylight"]:
		return {"error": "Select night or daylight explicitly."}
	var selected := quality if PROFILES.has(quality) else "low"
	var rig := stadium.get_node_or_null("NightFixtureRig")
	if mode == "daylight":
		if rig:
			rig.call("deactivate")
		var day := Daylight.apply(stadium, world, main, selected, viewport, library, set_global_atlas)
		world.set_meta("stadium_lighting_mode", "daylight")
		day["mode"] = "daylight"
		return day
	# Reuse the established LOD/grass adapter, suppress its global-atlas allocation.
	var report := Daylight.apply(stadium, world, main, selected, viewport, library, false)
	if report.has("error"):
		return report
	if rig == null:
		rig = Rig.new()
		rig.name = "NightFixtureRig"
		stadium.add_child(rig)
		rig.call("build", stadium, main)
	rig.call("activate", stadium, main, selected == "balanced")
	var environment := world.environment
	var sky := environment.sky.sky_material as ProceduralSkyMaterial
	sky.sky_top_color = Color("040815")
	sky.sky_horizon_color = Color("13233c")
	sky.ground_horizon_color = Color("13233c")
	sky.ground_bottom_color = Color("101820")
	sky.sky_energy_multiplier = 1.0
	sky.ground_energy_multiplier = 1.0
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d0d3d9")
	environment.ambient_light_energy = 0.25
	environment.tonemap_exposure = 1.0
	main.rotation_degrees = Vector3(-72.0, -22.0, 0.0)
	main.light_color = Color("fffdfa")
	main.light_energy = 0.94
	main.light_angular_distance = 0.0
	main.light_volumetric_fog_energy = 0.0
	main.shadow_opacity = 0.78
	main.shadow_normal_bias = 0.55
	main.directional_shadow_max_distance = float(PROFILES[selected].shadow_distance)
	main.directional_shadow_fade_start = 0.72
	main.shadow_blur = 1.0
	if set_global_atlas:
		RenderingServer.directional_shadow_atlas_set_size(int(PROFILES[selected].shadow_atlas), true)
	if viewport:
		viewport.msaa_3d = int(PROFILES[selected].msaa)
	report.merge(PROFILES[selected], true)
	report.merge({"mode": "night", "ambient_energy": 0.25, "sun_energy": 0.94, "sun_rotation_degrees": main.rotation_degrees,
		"sky_top": sky.sky_top_color, "sky_horizon": sky.sky_horizon_color, "new_environment_nodes": 0,
		"new_shadowed_lights": 0, "shadowed_lights_total": 1, "new_lights": rig.find_children("*", "Light3D", true, false).size(), "new_active_lights": 1 if selected == "balanced" else 0,
		"fixtures": rig.call("cost_contract"), "reference_night_lamp_positions": "User adaptation, not measured from video",
		"native_visual_and_frame_time_verified": false}, true)
	world.set_meta("stadium_lighting_mode", "night")
	world.set_meta("stadium_night_quality", selected)
	return report
