class_name FBMatchOverlay
extends CanvasLayer

const NAMES := {"kickoff": "开球", "throw_in": "界外球", "corner": "角球", "goal_kick": "球门球",
	"penalty": "点球", "direct_free_kick": "直接任意球", "indirect_free_kick": "间接任意球", "dropped_ball": "坠球"}
var _score: Label
var _message: Label
var _hint: Label
var _status: Dictionary = {}

func _ready() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(24, 20)
	panel.custom_minimum_size = Vector2(500, 108)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.065, 0.075, 0.9)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	_score = Label.new()
	_score.add_theme_font_size_override("font_size", 24)
	column.add_child(_score)
	_message = Label.new()
	_message.add_theme_color_override("font_color", Color("e6cf70"))
	column.add_child(_message)
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 14)
	column.add_child(_hint)

func update_snapshot(status: Dictionary) -> void:
	_status = status
	if _score == null:
		return
	var scores: Array = status.get("scores", [0, 0])
	var seconds := int(status.get("time_remaining", 0.0))
	_score.text = "蓝队 %d : %d 珊瑚队    第 %d 半场  %02d:%02d" % [scores[0], scores[1], status.get("half", 1), seconds / 60, seconds % 60]
	var state: String = str(status.get("state", "IDLE"))
	var restart: Dictionary = status.get("restart", {})
	if state in ["STOPPAGE", "RESTART_SETUP", "RESTART_READY", "RESTART_IN_FLIGHT"]:
		var team_name := "蓝队" if int(restart.get("team", 0)) == 0 else "珊瑚队"
		_message.text = "%s · %s · %s" % [team_name, NAMES.get(restart.get("kind", ""), "重启"), "可执行" if state == "RESTART_READY" else "准备中"]
		var progress: Dictionary = status.get("restart_progress", {})
		var jersey: int = int(progress.get("taker_jersey", -1))
		var taker_name := "#%d" % jersey if jersey >= 0 else str(progress.get("taker_name", "指定球员"))
		var reasons: Dictionary = progress.get("blocking_reasons", {})
		if progress.get("awaiting_field_entry", false):
			_hint.text = "球进入场内后继续比赛 · 可自由观察和移动"
		elif state == "RESTART_READY":
			_hint.text = "%s 执行重启 · 对准方向后触球 · 可自由观察和移动" % taker_name
		elif int(reasons.get("no_taker", 0)) > 0:
			_hint.text = "等待本队开球者 · 可自由观察和移动"
		else:
			var metres: float = maxf(0.0, float(progress.get("taker_distance", 0.0)))
			_hint.text = "%s 距站位 %.1f m · %d 人需调整站位 · 可自由观察和移动" % [taker_name, metres, int(reasons.get("restart_position", 0))]
	elif state == "HALF_TIME":
		_message.text = "半场休息 · 双方交换球门"
		_hint.text = "可自由走动与观察"
	elif state == "FULL_TIME":
		_message.text = "比赛结束"
		_hint.text = "可自由走动与观察"
	elif state == "GOAL_CELEBRATION":
		_message.text = "进球！"
		_hint.text = "随后由失球队中圈开球"
	else:
		_message.text = "比赛进行中" if state == "LIVE" else "准备比赛"
		_hint.text = ""
