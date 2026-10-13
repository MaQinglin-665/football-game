extends Node
var game: Node
var mode := "B"
var badge: Label
func _ready() -> void:
 game = get_parent()
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--impact-audio="): mode = arg.trim_prefix("--impact-audio=").to_upper()
 call_deferred("install")
func install() -> void:
 badge = game.hud.label("",Vector2(28,625),950,14)
 badge.modulate = Color("efd197")
 apply_mode(mode)
func apply_mode(next: String) -> void:
 assert(next in ["A","B"])
 mode = next
 game.services.audio.recorded_impacts_enabled = mode == "B"
 badge.text = "音效 %s：%s / F8 原音-实录切换" % [mode,"原音" if mode == "A" else "实录候选"]
 print("IMPACT_AUDIO_AB ",mode)
func _input(event: InputEvent) -> void:
 if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F8 and is_instance_valid(badge):
  apply_mode("B" if mode == "A" else "A")
  get_viewport().set_input_as_handled()
