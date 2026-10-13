extends CanvasLayer
const MeterScript := preload("res://scripts/integration_meter.gd")
var match_controller: Node
var root: Control
var menu: Panel
var pause_panel: Panel
var result_panel: Panel
var scoreboard: Panel
var score_label: Label
var clock_label: Label
var banner: Label
var hint: Label
var carrier_label: Label
var crosshair: Label
var charge: Control
var charge_caption: Label
var stamina: Control
var pass_marker: Label
var ball_indicator: Label
var help: Panel
var help_body: Label
var credits: Panel
var result_title: Label
var result_score: Label
var result_stats: Label

func _ready() -> void:
	root = Control.new()
	root.name = "HUDRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI","Microsoft YaHei","Segoe UI"])
	theme.default_font = font
	theme.default_font_size = 18
	root.theme = theme
	add_child(root)
	scoreboard = panel(Vector2(455,18),Vector2(370,77))
	label("蓝队",Vector2(20,15),70,16,scoreboard).modulate = Color("5aa4ff")
	label("红队",Vector2(279,15),82,16,scoreboard).modulate = Color("ed5962")
	score_label = label("0 : 0",Vector2(109,4),150,33,scoreboard)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clock_label = label("",Vector2(75,46),220,14,scoreboard)
	clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	carrier_label = label("蓝队 #10",Vector2(28,25),396,16)
	label("阵型 %s · 双方短传 · 中位防守" % match_controller.formation_label(),Vector2(28,49),420,12)
	hint = label("",Vector2(28,67),404,15)
	hint.size.y = 112
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_constant_override("outline_size",2)
	hint.add_theme_color_override("font_outline_color",Color("163432"))
	banner = label("",Vector2(314,161),652,24)
	banner.size.y = 96
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner.add_theme_constant_override("outline_size",4)
	banner.add_theme_color_override("font_outline_color",Color("163432"))
	crosshair = label("·",Vector2(628,337),24,30)
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stamina = progress(Vector2(585,107),Vector2(110,5),Color("62cdbc"))
	charge = progress(Vector2(571,406),Vector2(138,7),Color("f4cf76"))
	charge_caption = label("",Vector2(459,425),362,14)
	charge_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pass_marker = label("",Vector2.ZERO,210,14)
	pass_marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pass_marker.modulate = Color("7ce7e1")
	pass_marker.add_theme_constant_override("outline_size",3)
	pass_marker.add_theme_color_override("font_outline_color",Color("153830"))
	ball_indicator = label("",Vector2(485,611),310,15)
	ball_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label("FIRST PERSON FOOTBALL  /  %d v %d" % [match_controller.team_size,match_controller.team_size],Vector2(28,688),430,12)
	label("Esc 暂停    F1 操作    F3 设置    F11 全屏",Vector2(906,688),352,12)
	build_menu()
	build_pause()
	build_result()
	build_help()
	build_credits()

func build_menu() -> void:
	menu = panel(Vector2(63,91),Vector2(491,542))
	menu.mouse_filter = Control.MOUSE_FILTER_STOP
	label("ON THE PITCH  /  039 · 空间推进与阵容图",Vector2(32,29),421,12,menu).modulate = Color("78d6ca")
	label("第一人称足球",Vector2(29,74),429,48,menu)
	label("赛前选择位置 · AI 填补其余位置",Vector2(33,151),426,17,menu)
	preload("res://scripts/roster_selection.gd").menu(self)
	button("开始比赛  →",Vector2(32,252),Vector2(427,58),func(): match_controller.start_match(false),menu,true).name = "StartMatch"
	button("操作说明  /  F1",Vector2(32,325),Vector2(427,43),func(): toggle_help(),menu)
	label("WASD 移动 · Shift 切换加速 · Ctrl 慢走 / 短带\n按住 右键传球，左键射门，松开出脚\nSpace 停球 / 接球 / 抢球 · C 护球 / 逼抢\nQ 扣球 · F 高球 · G / X 弧线 · 滚轮调整高度 · E 要球",Vector2(34,393),422,14,menu).size.y = 118
	button("开源与素材许可",Vector2(315,498),Vector2(144,30),func(): show_credits(),menu)
	button("退出",Vector2(1130,27),Vector2(105,40),func(): match_controller.quit_game())

func build_pause() -> void:
	pause_panel = panel(Vector2(420,125),Vector2(440,490))
	pause_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	label("比赛暂停",Vector2(30,24),375,32,pause_panel)
	button("继续比赛",Vector2(30,86),Vector2(380,47),func(): match_controller.resume_match(),pause_panel,true)
	button("设置 · 画面 / 操作 / 声音  F3",Vector2(30,157),Vector2(380,47),func(): match_controller.settings_menu.open_menu(),pause_panel)
	label("设置支持应用保存和恢复默认。",Vector2(31,225),380,16,pause_panel)
	button("重新开始",Vector2(30,357),Vector2(380,44),func(): match_controller.restart_current(),pause_panel)
	button("返回主菜单",Vector2(30,419),Vector2(380,44),func(): match_controller.show_menu(),pause_panel)

func build_result() -> void:
	result_panel = panel(Vector2(412,147),Vector2(456,419))
	result_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	label("FULL TIME  /  全场结束",Vector2(32,26),392,14,result_panel)
	result_title = label("",Vector2(32,69),392,31,result_panel)
	result_score = label("",Vector2(32,128),392,47,result_panel)
	result_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_stats = label("",Vector2(32,208),392,16,result_panel)
	button("再踢一场  /  R",Vector2(32,275),Vector2(392,46),func(): match_controller.restart_current(),result_panel,true)
	button("返回主菜单",Vector2(32,337),Vector2(392,44),func(): match_controller.show_menu(),result_panel)

func build_help() -> void:
	help = panel(Vector2(29,91),Vector2(610,580))
	help.mouse_filter = Control.MOUSE_FILTER_STOP
	label("操作说明  ·  F1 / Esc 关闭",Vector2(22,18),555,23,help)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(22,65)
	scroll.size = Vector2(565,488)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	help.add_child(scroll)
	help_body = Label.new()
	help_body.custom_minimum_size = Vector2(547,850)
	help_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_body.add_theme_font_size_override("font_size",16)
	scroll.add_child(help_body)
	help.hide()

func build_credits() -> void:
	credits = panel(Vector2(230,65),Vector2(820,590))
	credits.mouse_filter = Control.MOUSE_FILTER_STOP
	label("开源与素材许可",Vector2(27,19),725,28,credits)
	var body := RichTextLabel.new()
	body.name = "Notices"
	body.position = Vector2(28,74)
	body.size = Vector2(762,435)
	body.add_theme_font_size_override("normal_font_size",14)
	credits.add_child(body)
	button("关闭 / Esc",Vector2(607,532),Vector2(184,35),func(): credits.hide(); match_controller.sync_input_context(),credits)
	credits.hide()

func _process(_delta: float) -> void:
	var m := match_controller
	if not is_instance_valid(m) or not is_instance_valid(m.ball): return
	var on_field: bool = m.phase not in [m.Phase.MENU,m.Phase.PAUSED,m.Phase.FINISHED]
	menu.visible = m.phase==m.Phase.MENU
	pause_panel.visible = m.phase==m.Phase.PAUSED
	result_panel.visible = m.phase==m.Phase.FINISHED
	scoreboard.visible = m.phase!=m.Phase.MENU
	for widget in [hint,carrier_label,crosshair,stamina,ball_indicator]: widget.visible = on_field
	for child in root.get_children():
		if child is Button: child.visible = m.phase==m.Phase.MENU
	score_label.text = "%d  :  %d" % [m.scores[0],m.scores[1]]
	var seconds := int(ceil(m.time_left))
	clock_label.text = "%s · %02d:%02d" % ["上半场" if m.services.rules.half==1 else "下半场",seconds/60,seconds%60]
	stamina.value = m.player.stamina
	stamina.modulate = Color("ffb087") if m.player.sprint_locked else Color.WHITE
	var preview: Dictionary = m.input_bridge.charge_preview if is_instance_valid(m.input_bridge) else {}
	charge.visible = on_field and not preview.is_empty()
	charge_caption.visible = charge.visible
	if charge.visible:
		charge.value = float(preview.power)*100
		charge_caption.text = "%s %d%%  ·  高度 %d°" % ["传球" if String(preview.action).begins_with("pass_") else "射门",int(round(float(preview.power)*100)),int(preview.elevation_deg)]
	if help.visible and is_instance_valid(m.input_bridge): help_body.text = m.input_bridge.help_text()
	banner.visible = on_field and m.phase in [m.Phase.COUNTDOWN,m.Phase.RESTART,m.Phase.GOAL]
	banner.text = m.restart_message if m.phase==m.Phase.GOAL else m.restart_hint()
	if m.phase==m.Phase.FINISHED:
		result_title.text = "蓝队获胜" if m.scores[0]>m.scores[1] else "比赛平局" if m.scores[0]==m.scores[1] else "红队获胜"
		result_score.text = "%d  :  %d" % [m.scores[0],m.scores[1]]
		result_stats.text = "你的传球 %d  ·  射门 %d  ·  抢球 %d" % [m.stats.passes,m.stats.shots,m.stats.tackles]
	var carrier: Node3D = m.ball.carrier
	carrier_label.text = m.Selection.caption(m)
	if carrier==m.player: carrier_label.text = "你在控球 · Ctrl 短带 / Space 脚底停球"
	elif is_instance_valid(carrier): carrier_label.text = ("蓝队" if carrier.team==0 else "红队")+" #%d 控球" % carrier.jersey
	hint.text = m.input_bridge.hint_text() if is_instance_valid(m.input_bridge) else ""
	if m.status_timer>0: hint.text += "\n"+m.status_message
	if m.services.rules.state in [m.Rules.State.RESTART_SETUP,m.Rules.State.RESTART_READY] and m.constrained_human_intent(Vector3.ZERO).length()>.1: hint.text += "\n裁判要求让出规定距离，仍可自由转头。"
	_update_markers(on_field)

func _update_markers(on_field: bool) -> void:
	var m := match_controller
	var camera: Camera3D = m.player.camera
	pass_marker.hide()
	if on_field and (m.ball.carrier==m.player or m.is_restart_taker(m.player)):
		var target: Node3D = m.get_pass_target(m.player)
		if is_instance_valid(target) and not camera.is_position_behind(target.position+Vector3.UP*1.3):
			var screen := camera.unproject_position(target.position+Vector3.UP*1.3)
			if screen.x>100 and screen.x<1160 and screen.y>110 and screen.y<580:
				pass_marker.position = screen-Vector2(105,20)
				pass_marker.text = "Q  传给 #%d" % target.jersey
				pass_marker.show()
	ball_indicator.text = ""
	if not on_field: return
	var screen := camera.unproject_position(m.ball.position)
	if camera.is_position_behind(m.ball.position) or screen.x<80 or screen.x>1200 or screen.y>665 or screen.y<100:
		var relative: Vector3 = m.player.global_basis.inverse()*(m.ball.position-m.player.position)
		ball_indicator.text = "%s  足球 %.1f m" % ["←" if relative.x<-.3 else "→" if relative.x>.3 else "↓" if relative.z>0 else "↑",m.flat_distance(m.player.position,m.ball.position)]

func toggle_help() -> void:
	help.visible = not help.visible
	match_controller.sync_input_context()

func show_credits() -> void:
	var text := "第一人称足球 11v11 · Version B v0.6 开发版\nGodot 4.6.3 官方标准版 / Jolt\n\n第一人称镜头基于 Whimfoome / Dimitar Dimitrov，MIT。\n足球 AI 参考 Nicolas Bize soccer-course，MIT。\n冻结版本及所有许可随完整源码附带。\n\n本版人物、球场和音频为本项目原创。\n人物球衣号码目前为数据标识，不含号码纹理。\n\n"
	for path in ["res://licenses/Whimfoome-MIT.txt","res://licenses/NicolasBize-MIT.txt","res://licenses/OriginalFootballCharacter.txt","res://addons/modern_stadium/LICENSE.md","res://addons/football_match_services/LICENSE","res://addons/football_materials_b/LICENSE","res://addons/football_materials_b/textures/LICENSE.txt","res://licenses/Godot-and-components.txt"]:
		if FileAccess.file_exists(path): text += FileAccess.get_file_as_string(path)+"\n\n"
	credits.get_node("Notices").text = text
	credits.show()
	match_controller.sync_input_context()

func label(text: String, at: Vector2, width: float, size: int, parent: Control = null) -> Label:
	var node := Label.new()
	node.text = text
	node.position = at
	node.size = Vector2(width,size*1.65)
	node.add_theme_font_size_override("font_size",size)
	node.add_theme_color_override("font_color",Color("f2edda"))
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent!=null else root).add_child(node)
	return node

func panel(at: Vector2, size: Vector2) -> Panel:
	var node := Panel.new()
	node.position = at
	node.size = size
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_theme_stylebox_override("panel",style(Color(.035,.105,.135,.96),10))
	root.add_child(node)
	return node

func button(text: String, at: Vector2, size: Vector2, action: Callable, parent: Control = null, primary := false) -> Button:
	var node := Button.new()
	node.text = text
	node.position = at
	node.size = size
	node.add_theme_font_size_override("font_size",17)
	var fill := Color("7bd4c0") if primary else Color("244853")
	for state in ["normal","hover","pressed","focus"]: node.add_theme_stylebox_override(state,style(fill.lightened(.1) if state in ["hover","focus"] else fill.darkened(.1) if state=="pressed" else fill,7))
	node.add_theme_color_override("font_color",Color("153a3e") if primary else Color("edf0df"))
	node.pressed.connect(action)
	(parent if parent!=null else root).add_child(node)
	return node

func progress(at: Vector2, size: Vector2, color: Color) -> Control:
	var node: Control = MeterScript.new()
	node.position = at
	node.size = size
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.fill_color = color
	root.add_child(node)
	return node

func style(color: Color, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	return box


