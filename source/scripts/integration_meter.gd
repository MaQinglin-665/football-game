extends Control
var value := 100.0
var fill_color := Color.WHITE
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
func _process(_delta: float) -> void:
	queue_redraw()
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color(.025,.08,.10,.75))
	draw_rect(Rect2(Vector2.ZERO,Vector2(size.x*clampf(value/100.0,0,1),size.y)),fill_color)
