extends Control
const Selection=preload("res://scripts/roster_selection.gd")
const POINTS={"CB":Vector2(.50,.73),"LW":Vector2(.16,.22),"CF":Vector2(.50,.16),"RW":Vector2(.84,.22),"LCM":Vector2(.23,.43),"RCM":Vector2(.77,.43),"DM":Vector2(.50,.55),"LB":Vector2(.12,.73),"LCB":Vector2(.37,.73),"RCB":Vector2(.63,.73),"RB":Vector2(.88,.73),"GK":Vector2(.50,.92),"LF":Vector2(.27,.29),"RF":Vector2(.73,.29),"BACK":Vector2(.50,.72)}
var game:Node
var buttons:Dictionary={}
var last_slot:String=""
var caption:Label
func style(color:Color,border:Color)->StyleBoxFlat:
	var box:=StyleBoxFlat.new();box.bg_color=color;box.border_color=border
	box.set_border_width_all(2);box.set_corner_radius_all(9)
	return box
func _ready()->void:
	size=Vector2(590,542);mouse_filter=Control.MOUSE_FILTER_STOP
	var title:=Label.new();title.text="%dv%d · %s · 点击位置" % [game.team_size,game.team_size,game.formation_label()];title.position=Vector2(28,15);title.add_theme_font_size_override("font_size",21);add_child(title)
	var arrow:=Label.new();arrow.text="↑ 进攻方向";arrow.position=Vector2(428,20);arrow.add_theme_font_size_override("font_size",16);add_child(arrow)
	for row in game.roster_configuration:
		if int(row.team)!=0:continue
		var at:Vector2=Vector2(28,67)+POINTS[row.slot]*Vector2(534,430)
		if row.is_goalkeeper:
			var label:=Label.new();label.text="门将 · AI";label.position=at-Vector2(45,12);label.modulate=Color("8eaeb7");add_child(label);continue
		var button:=Button.new();button.name=row.slot;button.text=Selection.LABELS[row.slot];button.position=at-Vector2(52,25);button.size=Vector2(104,50);button.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
		button.add_theme_font_size_override("font_size",17);button.add_theme_stylebox_override("hover",style(Color("365969"),Color("c7ddd9")));button.add_theme_stylebox_override("focus",style(Color(0,0,0,0),Color("ffffff")))
		var slot:String=row.slot
		button.pressed.connect(func():
			if Selection.choose(game,slot):refresh()
		)
		add_child(button);buttons[slot]=button
	refresh()
func refresh()->void:
	last_slot=String(Selection.human_row(game).get("slot",""))
	for slot in buttons:
		var chosen:bool=slot==last_slot
		buttons[slot].text=("● " if chosen else "")+Selection.LABELS[slot]
		buttons[slot].add_theme_stylebox_override("normal",style(Color("d8c485") if chosen else Color("193b49"),Color("f4dfa0") if chosen else Color("63878b")))
		buttons[slot].add_theme_color_override("font_color",Color("172e38") if chosen else Color("e2eded"))
		buttons[slot].add_theme_stylebox_override("hover",style(Color("e8d496") if chosen else Color("365969"),Color("f4dfa0") if chosen else Color("c7ddd9")))
		buttons[slot].add_theme_color_override("font_hover_color",Color("172e38") if chosen else Color("ffffff"))
	if caption!=null:caption.text=Selection.caption(game)+"\n选好后，点击“开始”确认入场"
func _process(_delta:float)->void:
	if is_visible_in_tree() and Selection.human_row(game).get("slot","")!=last_slot:refresh()
func _draw()->void:
	draw_style_box(style(Color("102630"),Color("304e57")),Rect2(Vector2.ZERO,size))
	var field:=Rect2(28,67,534,430);var line:=Color("65908a")
	draw_rect(field,Color("183c39"));draw_rect(field,line,false,1.5)
	draw_line(Vector2(28,282),Vector2(562,282),line,1.5);draw_arc(Vector2(295,282),47,0,TAU,48,line,1.5,true)
	draw_rect(Rect2(179,67,232,65),line,false,1.5);draw_rect(Rect2(179,432,232,65),line,false,1.5)
	draw_circle(Vector2(295,282),3,line)

