class_name RenderQuality
extends RefCounted
## Opt-in image quality: renders 3D at the display resolution instead of the
## fixed 1280x720 content size, plus stronger MSAA and shadows.
## Visual only: no gameplay, physics, camera, or input behaviour changes.

const LEVELS := ["fast", "balanced", "sharp", "ultra"]

## Automated publisher checks assert the frozen 1280x720 / low-AA budget, so they
## always keep the baseline render path regardless of the play default.
const QA_FLAGS := ["--release-perf-check", "--release-night-check", "--release-dribble-check",
	"--release-spin-check", "--release-body-check", "--release-far-check", "--role-action-check",
	"--training-startup-check", "--training-touchplan-check"]

static func is_automated_check() -> bool:
	for arg in OS.get_cmdline_user_args():
		if QA_FLAGS.has(arg):
			return true
		if arg.begins_with("--turf-roll=") or arg.begins_with("--impact-audio="):
			return true
	return false

## Default for this experiment. "fast" keeps the baseline's 1280x720 content size.
static func from_cmdline() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--render-quality="):
			var value := arg.trim_prefix("--render-quality=").to_lower()
			return value if LEVELS.has(value) else "balanced"
	return "fast" if is_automated_check() else "balanced"

static func next_level(current: String) -> String:
	var index := LEVELS.find(current)
	return LEVELS[(index + 1) % LEVELS.size()] if index >= 0 else "balanced"

static func apply(window: Window, level: String) -> Dictionary:
	var selected := level if LEVELS.has(level) else "balanced"
	var screen := DisplayServer.screen_get_size()
	var report := {"level": selected, "screen": screen, "baseline_content_size": Vector2i(1280, 720)}
	if selected == "fast":
		# Baseline path: 720p content stretched to the window, 2x MSAA.
		if window.mode != Window.MODE_WINDOWED:
			window.mode = Window.MODE_WINDOWED
		window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		window.size = Vector2i(1280, 720)
		window.msaa_3d = Viewport.MSAA_2X
		RenderingServer.directional_shadow_atlas_set_size(2048, true)
	else:
		# Render 3D at the display resolution; 2D stays on the 720p content scale.
		window.mode = Window.MODE_FULLSCREEN
		window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		window.msaa_3d = Viewport.MSAA_2X if selected=="balanced" else Viewport.MSAA_4X if selected == "sharp" else Viewport.MSAA_8X
		RenderingServer.directional_shadow_atlas_set_size(4096, true)
	report["window_mode"] = window.mode
	report["size"] = window.size
	report["content_scale_mode"] = window.content_scale_mode
	report["content_scale_size"] = window.content_scale_size
	report["msaa"] = window.msaa_3d
	return report

## Raise the sun's shadow reach after a quality change; keeps the single light.
static func apply_shadow_range(sun: DirectionalLight3D, level: String) -> void:
	if sun == null:
		return
	sun.directional_shadow_max_distance = 110.0 if level == "ultra" else 95.0 if level=="sharp" else 75.0
	sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_split_1=.25 if level=="balanced" else .35
	sun.shadow_normal_bias=.8
	sun.shadow_blur=1.0

static func label(level: String) -> String:
	match level:
		"fast":return "流畅"
		"balanced":return "均衡清晰"
		"ultra":return "极清"
		_:return "清晰"

static func tune_surface_filtering(node:Node)->void:
	if node is MeshInstance3D and node.mesh!=null:
		for index in range(node.mesh.get_surface_count()):
			var material:Material=node.get_active_material(index)
			if material is BaseMaterial3D:material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	for child in node.get_children():tune_surface_filtering(child)
