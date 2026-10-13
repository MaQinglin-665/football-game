extends RefCounted
## Reconfigure the host's single existing sky/environment/sun, never create another.
const StadiumQuality := preload("res://addons/modern_stadium/stadium_quality.gd")
const PROFILES := {
	"low": {"shadow_distance": 70.0, "shadow_atlas": 2048, "msaa": Viewport.MSAA_DISABLED, "shadow_blur": 1.0},
	"balanced": {"shadow_distance": 85.0, "shadow_atlas": 4096, "msaa": Viewport.MSAA_2X, "shadow_blur": 1.2}
}

static func apply(stadium: Node3D, world: WorldEnvironment, sun: DirectionalLight3D, quality: String = "balanced", viewport: Viewport = null, library: RefCounted = null, set_global_atlas: bool = true) -> Dictionary:
	if not is_instance_valid(stadium) or not is_instance_valid(world) or not is_instance_valid(sun) or world.environment == null:
		return {"error": "Supply the existing stadium, WorldEnvironment and DirectionalLight3D. No fallback lights are created."}
	var environment := world.environment
	if environment.sky == null or not environment.sky.sky_material is ProceduralSkyMaterial:
		return {"error": "Existing sky is not ProceduralSkyMaterial; preserve it and adapt the host explicitly."}
	var selected := quality if PROFILES.has(quality) else "balanced"
	var profile: Dictionary = PROFILES[selected]
	# Keep the already-integrated stand patch's own LOD implementation and thresholds.
	var report := StadiumQuality.apply(stadium, environment, sun, selected, viewport, set_global_atlas)
	var sky_material := environment.sky.sky_material as ProceduralSkyMaterial
	sky_material.sky_top_color = Color("7195b2")
	sky_material.sky_horizon_color = Color("d1dce2")
	sky_material.ground_horizon_color = Color("d1dce2")
	sky_material.ground_bottom_color = Color("839485")
	sky_material.sky_curve = 0.18
	sky_material.ground_curve = 0.08
	sky_material.energy_multiplier = 1.0
	sky_material.sky_energy_multiplier = 1.0
	sky_material.ground_energy_multiplier = 1.0
	sky_material.sun_angle_max = 5.0
	sky_material.sun_curve = 0.12
	sky_material.use_debanding = true
	# Fixed color ambient avoids adding GI or an expensive moving-sky irradiance job.
	environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("dae8f2")
	environment.ambient_light_energy = 0.48
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.tonemap_exposure = 1.0
	environment.ssao_enabled = false
	environment.ssil_enabled = false
	environment.sdfgi_enabled = false
	environment.ssr_enabled = false
	environment.glow_enabled = false
	environment.fog_enabled = false
	environment.volumetric_fog_enabled = false
	sun.rotation_degrees = Vector3(-54.0, -28.0, 0.0)
	sun.light_color = Color("fffdf7")
	sun.light_energy = 0.76
	sun.light_angular_distance = 0.0 # PCSS is Forward+ only, not a Compatibility feature.
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 0.65
	sun.shadow_opacity = 0.88
	sun.shadow_blur = profile.shadow_blur
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_split_1 = 0.25
	sun.directional_shadow_max_distance = profile.shadow_distance
	sun.directional_shadow_fade_start = 0.78
	sun.directional_shadow_blend_splits = false
	if viewport:
		viewport.msaa_3d = profile.msaa
	var grass_detail_changed := false
	if library != null:
		var slots: Dictionary = library.get("slots")
		var turf := slots.get("pitch_grass") as ShaderMaterial
		if turf and turf.shader:
			for uniform in turf.shader.get_shader_uniform_list():
				if uniform.name == "close_detail_enabled":
					turf.set_shader_parameter("close_detail_enabled", selected != "low")
					grass_detail_changed = true
	report.merge(profile, true)
	report.merge({"ambient_energy": 0.48, "sun_energy": 0.76, "sun_rotation_degrees": sun.rotation_degrees,
		"sky_top": sky_material.sky_top_color, "sky_horizon": sky_material.sky_horizon_color,
		"shadow_cascades": 2, "new_environment_nodes": 0, "new_lights": 0, "gi": false,
		"ssao": false, "glow": false, "pcss": false, "grass_detail_changed": grass_detail_changed,
		"native_visual_and_frame_time_verified": false}, true)
	world.set_meta("daylight_profile", selected)
	ForwardPlusFx.reapply(environment) # R004: keep the Forward+ tier across day/night switches
	return report
