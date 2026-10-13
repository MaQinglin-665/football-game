extends Node
## One shared physical profile, two user-visible comparisons. No ball state writes.
var game: Node
var mode := "B"
var mode_label: Label

func _ready() -> void:
	game = get_parent()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--turf-roll="): mode = arg.trim_prefix("--turf-roll=").to_upper()
	assert(mode in ["A", "B"])
	call_deferred("install")

func install() -> void:
	assert(is_instance_valid(game.physics_profile))
	assert(game.ball.profile == game.physics_profile and game.physics_world.profile == game.physics_profile)
	mode_label = game.hud.label("", Vector2(28,650), 850, 14)
	mode_label.modulate = Color("efd197")
	apply_mode(mode, false)

func apply_mode(next: String, notify: bool = true) -> void:
	assert(next in ["A", "B"])
	mode = next
	game.physics_profile.low_speed_roll_extra_mps2 = 0.0 if mode == "A" else 0.75
	mode_label.text = "滚阻 %s · %s   / F7 切换 · R 重置对照" % [mode, "原版" if mode == "A" else "低速辅助"]
	if notify: game.message(mode_label.text, 3.0)
	print("TURF_ROLL_AB_MODE ", mode, " extra=", game.physics_profile.low_speed_roll_extra_mps2)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F7 and is_instance_valid(mode_label):
		apply_mode("B" if mode == "A" else "A")
		get_viewport().set_input_as_handled()
