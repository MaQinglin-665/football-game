extends RefCounted
## Mutate the host's existing environment/light only. Creates no lights or post FX.
const PROFILES = {
	"low":{"seat_near":55.0,"seat_mid":80.0,"net_near":24.0,"shadow_distance":75.0,"shadow_atlas":2048,"msaa":1,"ssao":false,"glow":true,"taa":false,"ssao_radius":0.0},
	"balanced":{"seat_near":70.0,"seat_mid":90.0,"net_near":32.0,"shadow_distance":95.0,"shadow_atlas":4096,"msaa":1,"ssao":true,"glow":true,"taa":false,"ssao_radius":0.8},
	"high":{"seat_near":85.0,"seat_mid":110.0,"net_near":40.0,"shadow_distance":100.0,"shadow_atlas":4096,"msaa":1,"ssao":true,"glow":true,"taa":true,"ssao_radius":1.0}
}
## R004 Forward+ post: msaa 1 = 2x. TAA only on high; FSR2 (settings) replaces both.

static func apply(stadium: Node3D, environment: Environment, sun: DirectionalLight3D, quality: String = "balanced", viewport: Viewport = null, set_global_atlas: bool = true) -> Dictionary:
	var selected: String=quality if PROFILES.has(quality) else "balanced"
	var settings: Dictionary=PROFILES[selected].duplicate(true)
	stadium.seat_lod_near_distance=settings.seat_near
	stadium.seat_lod_mid_distance=settings.seat_mid
	stadium.net_lod_distance=settings.net_near
	# Lift roof-shaded stands while retaining a single directional source.
	environment.ambient_light_energy=0.46
	sun.light_energy=0.72
	sun.shadow_enabled=true
	sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_split_1=0.35
	sun.directional_shadow_max_distance=settings.shadow_distance
	sun.shadow_blur=1.0
	# Atlas/MSAA are global viewport resources; only the host should opt in.
	if set_global_atlas: RenderingServer.directional_shadow_atlas_set_size(settings.shadow_atlas,true)
	if viewport: viewport.msaa_3d=settings.msaa
	settings["quality"]=selected
	settings["ambient_energy"]=0.46
	settings["sun_energy"]=0.72
	settings["shadow_cascades"]=2
	return settings
