class_name ForwardPlusFx
extends RefCounted
## R004: Forward+ environment/AA tier. Reads StadiumQuality.PROFILES; Compatibility
## renderer (fallback) keeps the previous linear/no-glow look untouched.
const TONEMAP_EXPOSURE := 1.10   # AgX is darker than linear at 1.0
const TONEMAP_WHITE := 12.0
const GLOW_INTENSITY := 0.35
const GLOW_STRENGTH := 0.8
const GLOW_BLOOM := 0.02
const GLOW_HDR_THRESHOLD := 1.2  # only bright highlights (floodlights, sun specular)
const SSAO_INTENSITY := 1.2
const SSAO_POWER := 1.5
const SSAO_DETAIL := 0.0  # R006: fine-detail AO turned dense seat rows into grain (was 0.4)
const SHADOW_FILTER := {"low": RenderingServer.SHADOW_QUALITY_SOFT_LOW, "balanced": RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, "high": RenderingServer.SHADOW_QUALITY_SOFT_HIGH}

static var last_tier := ""
static var last_viewport: Viewport
static var last_effects := true
static func reapply(environment: Environment) -> void:
	if last_tier != "": apply(environment, last_viewport, last_tier, last_effects)

static func is_forward_plus() -> bool:
	return RenderingServer.get_current_rendering_method() == "forward_plus"

static func apply(environment: Environment, viewport: Viewport, tier: String, effects_on: bool = true) -> Dictionary:
	var profiles: Dictionary = preload("res://addons/modern_stadium/stadium_quality.gd").PROFILES
	var p: Dictionary = profiles.get(tier, profiles.balanced)
	last_tier = tier; last_viewport = viewport; last_effects = effects_on
	var report := {"tier": tier, "forward_plus": is_forward_plus()}
	if not report.forward_plus or environment == null: return report
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.tonemap_exposure = TONEMAP_EXPOSURE
	environment.tonemap_white = TONEMAP_WHITE
	environment.glow_enabled = effects_on and bool(p.get("glow", false))
	environment.glow_intensity = GLOW_INTENSITY
	environment.glow_strength = GLOW_STRENGTH
	environment.glow_bloom = GLOW_BLOOM
	environment.glow_hdr_threshold = GLOW_HDR_THRESHOLD
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	environment.ssao_enabled = effects_on and bool(p.get("ssao", false))
	environment.ssao_radius = float(p.get("ssao_radius", 1.0))
	environment.ssao_intensity = SSAO_INTENSITY
	environment.ssao_power = SSAO_POWER
	environment.ssao_detail = SSAO_DETAIL
	RenderingServer.directional_soft_shadow_filter_set_quality(SHADOW_FILTER.get(tier, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM))
	if viewport != null:
		var fsr: bool = viewport.scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR2
		# R006: AA comes from RenderQuality.TIER_AA (one method per tier); no stacking here.
		viewport.use_taa = bool(viewport.get_meta("r006_taa", p.get("taa", false))) and not fsr and viewport.msaa_3d == Viewport.MSAA_DISABLED
		report["taa"] = viewport.use_taa
		report["fsr2"] = fsr
	report["ssao"] = environment.ssao_enabled
	report["glow"] = environment.glow_enabled
	return report
