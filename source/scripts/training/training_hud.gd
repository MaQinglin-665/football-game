extends "res://scripts/hud.gd"
var training_caption: Label

func _ready() -> void:
	super._ready()
	for widget in root.get_children():
		if widget is Label and "11 v 11" in widget.text:
			widget.text = "FIRST PERSON FOOTBALL  /  3 v 3 TRAINING"
	training_caption = label("", Vector2(28, 198), 420, 14)
	training_caption.size.y = 50
	var pressure := CheckBox.new()
	pressure.position = Vector2(25, 320)
	pressure.text = "低防守压力（F5 切换）"
	pressure.button_pressed = match_controller.training_mode.low_pressure
	pressure.toggled.connect(func(value): match_controller.training_mode.low_pressure = value)
	pause_panel.add_child(pressure)
	pressure.set_meta("training_pressure", true)

func build_menu() -> void:
	menu = panel(Vector2(63, 91), Vector2(491, 542))
	menu.mouse_filter = Control.MOUSE_FILTER_STOP
	label("TRAINING  /  039 · 空间推进与阵容图", Vector2(32, 29), 421, 12, menu).modulate = Color("78d6ca")
	label("3v3 小场快练", Vector2(29, 74), 429, 44, menu)
	label("赛前选择位置 · AI 填补其余位置",Vector2(33,151),426,17,menu)
	var cfg: Resource = match_controller.training_configuration
	preload("res://scripts/roster_selection.gd").menu(self)
	button("开始训练  →", Vector2(32, 252), Vector2(427, 58), func(): match_controller.start_match(false), menu, true).name = "StartMatch"
	button("操作说明  /  F1", Vector2(32, 325), Vector2(427, 43), func(): toggle_help(), menu)
	label("WASD 移动 · Shift 切换加速 / 双击大趟\nQ 扣球 · 右键传球 · 左键射门 · E 要球\nSpace 停球 / 抢球 · C 护球 / 逼抢\nR 重置本轮 · F5 压力 · F6 切换攻防起点", Vector2(34, 390), 422, 14, menu).size.y = 111
	button("开源与素材许可", Vector2(315, 498), Vector2(144, 30), func(): show_credits(), menu)
	button("退出", Vector2(1130, 27), Vector2(105, 40), func(): match_controller.quit_game())

func _process(delta: float) -> void:
	super._process(delta)
	var mode: Node = match_controller.training_mode
	if not is_instance_valid(mode):
		return
	var elapsed := int(mode.session_seconds)
	clock_label.text = "训练 · %02d:%02d · 第 %d 轮" % [elapsed / 60, elapsed % 60, mode.repetitions]
	training_caption.visible = match_controller.phase != match_controller.Phase.MENU
	training_caption.text = "%s · 黄队压力 %s\nR 重置 · F5 压力 · F6 攻防起点" % [mode.opening_label(), mode.pressure_label()]
	for widget in pause_panel.get_children():
		if widget is CheckBox and widget.has_meta("training_pressure"):
			widget.set_pressed_no_signal(mode.low_pressure)
	if banner.visible:
		if match_controller.phase == match_controller.Phase.GOAL:
			banner.text = ("蓝队进球" if mode.last_goal_team == 0 else "黄队进球") + " · 快速重置"
		else:
			banner.text = "本轮结束 · 快速重置"

