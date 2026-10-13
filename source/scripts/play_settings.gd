extends CanvasLayer
# One persistent presentation owner. No physics/rules parameters exposed.
const Quality=preload("res://scripts/render_quality.gd")
const Night=preload("res://addons/stadium_night/night_profile.gd")
const DEFAULTS={"quality":1,"aa":1,"upscale":0,"shadows":1,"grass":1,"lighting":1,"fov":90.0,"sensitivity":1.6,"volume":85.0,"assist":true,"low_pressure":false,"effects":1,"camera_bob":true,"fps_limit":0,"inertia":0}
var game:Node
var lighting_fx:Node
var values:Dictionary=DEFAULTS.duplicate()
var widgets:Dictionary={}
var opened:=false
var prior_phase:int=0
var panel:Control
var entry:Button
var note:Label
var config_path:="user://fc_latest_art_motion.cfg"
func _ready()->void:
	layer=100
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--settings-file="):config_path=arg.trim_prefix("--settings-file=")
	load_values()
	_build()
	lighting_fx=preload("res://scripts/play_lighting.gd").new()
	lighting_fx.game=game
	game.add_child(lighting_fx)
	apply_values(false)
func load_values()->void:
	values=DEFAULTS.duplicate()
	var cfg:=ConfigFile.new()
	var loaded:int=cfg.load(config_path)
	if loaded!=OK and config_path=="user://play_settings_body_inertia.cfg":loaded=cfg.load("user://play_settings_motion_clarity.cfg")
	if loaded!=OK and config_path=="user://play_settings_body_inertia.cfg":loaded=cfg.load("user://play_settings_ball_pass.cfg")
	if loaded!=OK and config_path=="user://play_settings_body_inertia.cfg":loaded=cfg.load("user://play_settings_team_plans.cfg")
	if loaded!=OK and config_path=="user://play_settings_body_inertia.cfg":loaded=cfg.load("user://play_settings_pressure_team.cfg")
	if loaded==OK:
		for key in DEFAULTS:values[key]=cfg.get_value("play",key,DEFAULTS[key])
	for key in ["quality","aa","shadows","grass","lighting","effects"]:
		values[key]=clampi(int(values[key]),0,2 if key in ["quality","shadows","grass","effects"] else 1) # R006: 3 tiers; aa = off/tier
	values.upscale=clampi(int(values.upscale),0,2)
	values.inertia=clampi(int(values.inertia),0,1)
	values.fps_limit=clampi(int(values.fps_limit),0,2)
	values.fov=clampf(float(values.fov),76,104)
	values.sensitivity=clampf(float(values.sensitivity),.6,3)
	values.volume=clampf(float(values.volume),0,100)
func _build()->void:
	var font:=SystemFont.new()
	font.font_names=PackedStringArray(["Microsoft YaHei UI","Microsoft YaHei","Segoe UI"])
	var theme:=Theme.new();theme.default_font=font;theme.default_font_size=18
	entry=Button.new();entry.text="设置  F3";entry.position=Vector2(980,26);entry.size=Vector2(130,40);entry.theme=theme
	entry.pressed.connect(open_menu);add_child(entry)
	panel=Control.new();panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);panel.theme=theme;add_child(panel)
	var dim:=ColorRect.new();dim.color=Color(0.015,0.025,0.04,.87);dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);panel.add_child(dim)
	var box:=PanelContainer.new();box.position=Vector2(330,22);box.size=Vector2(620,670);panel.add_child(box)
	var margin:=MarginContainer.new();margin.add_theme_constant_override("margin_left",24);margin.add_theme_constant_override("margin_right",24);margin.add_theme_constant_override("margin_top",16);margin.add_theme_constant_override("margin_bottom",16);box.add_child(margin)
	var stack:=VBoxContainer.new();margin.add_child(stack)
	var scroll:=ScrollContainer.new();scroll.custom_minimum_size=Vector2(570,550);scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;stack.add_child(scroll)
	var column:=VBoxContainer.new();column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;column.add_theme_constant_override("separation",9);scroll.add_child(column)
	var title:=Label.new();title.text="游戏设置";title.add_theme_font_size_override("font_size",28);column.add_child(title)
	_option(column,"quality","画质 / 显示",["流畅 · 720p 窗口","均衡 · 原生全屏","高画质 · 原生全屏"])
	_option(column,"fps_limit","帧率上限",["60 FPS · 稳定优先","120 FPS · 需要性能余量","不限制"])
	_option(column,"aa","边缘抗锯齿",["关闭","随画质 · 流畅 FXAA / 均衡 2x MSAA / 高 TAA"])
	_option(column,"upscale","超分辨率",["原生 · 默认","FSR 2 · 质量","FSR 2 · 均衡"])
	_option(column,"shadows","人物 / 场地阴影",["关闭","标准 · 75 米","精细 · 100 米"])
	_option(column,"grass","草地细节",["简洁","标准 · 近景草叶","精细 · 更远细节"])
	_option(column,"effects","光影效果",["关闭 · 原有光照","标准 · 立体补光 / 接触阴影","增强 · 环境光 / 接触层次"])
	_option(column,"lighting","光照",["日场","夜场"])
	_slider(column,"fov","视野",76,104,1)
	_slider(column,"sensitivity","鼠标灵敏度",.6,3,.1)
	_slider(column,"volume","总音量",0,100,1)
	_check(column,"assist","轻微传球目标辅助")
	_option(column,"inertia","运动惯性",["轻 · 默认","中 · 转向需更多提前量"])
	_check(column,"camera_bob","轻微跑动视角起伏")
	if is_instance_valid(game.training_mode):_check(column,"low_pressure","3v3 低防守压力（开启后对手减速）")
	note=Label.new();note.text="修改后点击应用。增强光影 / 高抗锯齿会增加显卡负担。";note.add_theme_font_size_override("font_size",14);column.add_child(note)
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",12);stack.add_child(row)
	for item in [["应用并保存",_commit],["恢复默认",_defaults],["返回  Esc",close_menu]]:
		var button:=Button.new();button.text=item[0];button.custom_minimum_size=Vector2(170,40);button.pressed.connect(item[1]);row.add_child(button)
	widgets.quality.item_selected.connect(func(index:int):
		widgets.shadows.select(1 if index<2 else 2)
		widgets.grass.select(0 if index==0 else 2 if index==2 else 1))
	panel.hide()
func _row(parent:Node,text:String)->HBoxContainer:
	var row:=HBoxContainer.new();parent.add_child(row)
	var label:=Label.new();label.text=text;label.custom_minimum_size.x=215;row.add_child(label)
	return row
func _option(parent:Node,key:String,text:String,options:Array)->void:
	var row:=_row(parent,text);var option:=OptionButton.new();option.custom_minimum_size=Vector2(340,34)
	for item in options:option.add_item(item)
	row.add_child(option);widgets[key]=option
func _slider(parent:Node,key:String,text:String,low:float,high:float,step_size:float)->void:
	var row:=_row(parent,text);var slider:=HSlider.new();slider.min_value=low;slider.max_value=high;slider.step=step_size;slider.custom_minimum_size=Vector2(265,32);row.add_child(slider)
	var number:=Label.new();number.custom_minimum_size.x=64;row.add_child(number)
	slider.value_changed.connect(func(value:float):number.text="%.1f"%value if step_size<1 else str(int(value)))
	widgets[key]=slider
func _check(parent:Node,key:String,text:String)->void:
	var check:=CheckBox.new();check.text=text;parent.add_child(check);widgets[key]=check
func _sync()->void:
	for key in widgets:
		var widget:Control=widgets[key]
		if widget is OptionButton:widget.select(int(values[key]))
		elif widget is HSlider:widget.value=float(values[key])
		elif widget is CheckBox:widget.button_pressed=bool(values[key])
func _commit()->void:
	for key in widgets:
		var widget:Control=widgets[key]
		values[key]=widget.selected if widget is OptionButton else widget.value if widget is HSlider else widget.button_pressed
	apply_values(true)
func _defaults()->void:
	var applied:Dictionary=values
	values=DEFAULTS.duplicate();_sync();values=applied
	note.text="已载入默认值；点击应用并保存后生效。"
func apply_values(save:bool)->void:
	var mode:String="daylight" if int(values.lighting)==0 else "night"
	game.render_quality=Quality.LEVELS[int(values.quality)]
	Quality.apply(game.get_window(),game.render_quality)
	var viewport=game.get_window()
	var use_fsr=RenderingServer.get_current_rendering_method()=="forward_plus" and int(values.upscale)>0
	viewport.scaling_3d_mode=Viewport.SCALING_3D_MODE_FSR2 if use_fsr else Viewport.SCALING_3D_MODE_BILINEAR
	viewport.scaling_3d_scale=([1.0,.77,.667][int(values.upscale)]) if use_fsr else 1.0
	viewport.fsr_sharpness=.65
	var lod:Dictionary=preload("res://addons/modern_stadium/stadium_quality.gd").PROFILES["low" if int(values.quality)==0 else "balanced"]
	game.stadium.seat_lod_near_distance=lod.seat_near;game.stadium.seat_lod_mid_distance=lod.seat_mid;game.stadium.net_lod_distance=lod.net_near
	var turf:ShaderMaterial=game.services.materials.slots.pitch_grass
	turf.set_shader_parameter("close_detail_enabled",int(values.grass)>0)
	turf.set_shader_parameter("detail_strength",.32)
	turf.set_shader_parameter("normal_strength",.43)
	turf.set_shader_parameter("detail_tile_m",1.15)
	turf.set_shader_parameter("pitch_half_length",game.field_half_length)
	turf.set_shader_parameter("detail_fade_start_m",9.0)
	turf.set_shader_parameter("detail_fade_end_m",38.0 if int(values.grass)==2 else 23.0)
	preload("res://scripts/stadium_finish.gd").apply(game.stadium,"low" if int(values.quality)==0 else "detail" if int(values.quality)>1 else "balanced")
	lighting_fx.apply(int(values.effects),mode=="night",int(values.shadows)>0,int(values.quality),int(values.shadows))
	Quality.apply_tier_aa(viewport,int(values.quality),int(values.aa)>0) # R006: after FX so it wins
	for actor in game.players:actor.profile.set_meta("movement_inertia",int(values.inertia))
	Engine.max_fps=[60,120,0][int(values.fps_limit)]
	game.player.camera_bob_enabled=bool(values.camera_bob)
	game.player.camera.fov=float(values.fov)
	game.player.base_fov=float(values.fov)
	game.player.head.mouse_sensitivity=float(values.sensitivity)/1000.0
	AudioServer.set_bus_volume_db(0,linear_to_db(maxf(.0001,float(values.volume)/100)))
	AudioServer.set_bus_mute(0,float(values.volume)<=0)
	game.assist=bool(values.assist)
	if is_instance_valid(game.training_mode):
		game.training_mode.low_pressure=bool(values.low_pressure)
	if save:
		var cfg:=ConfigFile.new()
		for key in values:cfg.set_value("play",key,values[key])
		var err:=cfg.save(config_path)
		note.text="已应用并保存。" if err==OK else "已应用，但保存失败：%s"%error_string(err)
	game.quality_change.emit({"level":game.render_quality,"settings":values.duplicate()})
func open_menu()->void:
	if opened:return
	prior_phase=game.phase
	game.pause_match();opened=true
	# Sync quick controls changed since the last menu visit.
	if is_instance_valid(game.training_mode):values.low_pressure=game.training_mode.low_pressure
	_sync();panel.show();entry.hide();Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	game.sync_input_context();widgets.quality.grab_focus()
func close_menu()->void:
	if not opened:return
	opened=false;panel.hide()
	if prior_phase!=game.Phase.PAUSED:game.set_phase(prior_phase)
	game.sync_input_context()
func cycle_quality()->void:
	if opened:return
	values.quality=(int(values.quality)+1)%3
	apply_values(true)
	game.message("画质："+Quality.label(game.render_quality)+" · F3 设置",2.5)
func cycle_lighting()->void:
	if opened:return
	values.lighting=1-int(values.lighting);apply_values(true)
func _process(_delta:float)->void:
	entry.visible=not opened and game.phase in [game.Phase.MENU,game.Phase.PAUSED,game.Phase.FINISHED]
func _input(event:InputEvent)->void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode==KEY_F3 or opened and event.physical_keycode==KEY_ESCAPE:
			if opened:close_menu()
			else:open_menu()
			get_viewport().set_input_as_handled()
