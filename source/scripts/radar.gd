extends Control

var match_controller: Node
var font: Font

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(match_controller):
		return
	var pitch := Rect2(10, 28, 130, 172)
	draw_style_box(style(Color(0.06, 0.15, 0.18, 0.83)), Rect2(0, 0, 150, 212))
	var count: int = 1 if match_controller.duel_mode else match_controller.team_size
	draw_string(font, Vector2(13, 19), "%d v %d / RADAR" % [count,count], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("d9dfce"))
	draw_rect(pitch, Color("558372"))
	draw_rect(pitch, Color("bcd0b4"), false, 1)
	draw_line(Vector2(10, 114), Vector2(140, 114), Color("bcd0b4"), 1)
	draw_arc(Vector2(75, 114), 16, 0, TAU, 32, Color("bcd0b4"), 1)
	var blue_attacks_up: bool = match_controller.attack_direction(0)<0
	draw_line(Vector2(61, 27), Vector2(89, 27), Color("ffd529") if blue_attacks_up else Color("167cff"), 4)
	draw_line(Vector2(61, 201), Vector2(89, 201), Color("167cff") if blue_attacks_up else Color("ffd529"), 4)
	for player in match_controller.players:
		if not player.visible:
			continue
		var point := to_radar(player.position)
		draw_circle(point, 4.0, Color("5aa4ff") if player.team == 0 else Color("ffe14e"))
		if player.is_human:
			draw_arc(point, 6.0, 0, TAU, 16, Color("fff5dc"), 1.5)
			draw_line(point, point + Vector2(player.facing.x, player.facing.z) * 10, Color("fff5dc"), 1.5)
	if is_instance_valid(match_controller.ball):
		draw_circle(to_radar(match_controller.ball.position), 3, Color("ffe49b"))

func to_radar(at: Vector3) -> Vector2:
	return Vector2(75 + clampf(at.x, -match_controller.field_half_width, match_controller.field_half_width) / match_controller.field_half_width * 65, 114 + clampf(at.z, -match_controller.field_half_length, match_controller.field_half_length) / match_controller.field_half_length * 86)

func style(color: Color) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = color
	result.set_corner_radius_all(10)
	return result
