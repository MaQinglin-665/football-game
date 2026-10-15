extends SceneTree
# Natural opening. No ball fixture, screenshots, file writes or input replay during measurement.
const Watch=preload("res://scripts/frame_spike_watch.gd")
var game:Node
var rows:Array=[]
var output:String=""
var began:int=0
var previous:int=0
var previous_tick:int=0
var duration:float=18.0
var small:bool=false
var cap:int=120
var aa:int=1
var full:bool=false
var config:Dictionary={}
var contacts:Dictionary={}
var cut_events:Array=[]
var carrier_rows:Array=[]
var last_sample:=0.0
class Collector extends Node:
	var probe
	func _process(_dt:float)->void:probe.collect()
func _initialize()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):output=arg.trim_prefix("--out=")
		if arg.begins_with("--seconds="):duration=float(arg.trim_prefix("--seconds="))
		if arg=="--small":small=true
		if arg=="--fps60":cap=60
		if arg=="--aa4":aa=2
		if arg=="--full":full=true
	seed(390108)
	call_deferred("begin")
func begin()->void:
	game=load("res://scenes/training_3v3.tscn" if small else "res://scenes/match.tscn").instantiate()
	root.add_child(game);current_scene=game;game.test_mode=true
	game.settings_menu.values.quality=1;game.settings_menu.values.aa=aa
	game.settings_menu.values.lighting=1;game.settings_menu.values.volume=0
	game.settings_menu.apply_values(false)
	if not full:root.mode=Window.MODE_WINDOWED;root.size=Vector2i(1280,720)
	Engine.max_fps=cap;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	game.contact_hub.contact_resolved.connect(func(e:Dictionary):
		if e.get("success",false):
			var key:String=str(e.get("action",""));contacts[key]=int(contacts.get(key,0))+1
			var actor=e.get("actor")
			if is_instance_valid(actor) and actor.foot.touch_plan.has("cut_style"):
				cut_events.append({"time":(Time.get_ticks_usec()-began)*.000001,"actor":game.players.find(actor),"style":actor.foot.touch_plan.cut_style,"side":actor.foot.side,"position":actor.position,"ball":game.ball.position,"velocity":game.ball.velocity,"target":actor.target}))
	if small:game.training_mode.defensive_opening=true
	game.start_match(false)
	if not small:game.services.start_match(game.rule_roster(),1);game._sync_rule_phase()
	var collector:=Collector.new();collector.probe=self;collector.process_priority=9000;root.add_child(collector)
	config={"viewport":str(root.size),"settings":game.settings_menu.values.duplicate(),"cap":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode(),"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"physics_hz":Engine.physics_ticks_per_second,"players":game.players.size(),"camera":"actual first person, human idle","seed":390108}
	began=Time.get_ticks_usec();previous=began;previous_tick=Engine.get_physics_frames()
func collect()->void:
	if began==0:return
	var now:int=Time.get_ticks_usec()
	var t:float=(now-began)*.000001
	rows.append({"t":t,"frame_ms":(now-previous)*.001,"physics_ticks":Engine.get_physics_frames()-previous_tick,"physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000,"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000,"render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()),"gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),"render_setup_ms":RenderingServer.get_frame_setup_time_cpu(),"pose_ms":Watch.pose_us*.001,"tactics_ms":Watch.tactics_us*.001,"proxy_ms":Watch.proxy_us*.001,"far_ms":Watch.far_us*.001,"pose_calls":Watch.pose_calls,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"phase":game.phase})
	if t-last_sample>.05:
		last_sample=t
		var actor=game.ball.carrier
		if is_instance_valid(actor) and not actor.is_human:
			carrier_rows.append({"t":t,"actor":game.players.find(actor),"position":actor.position,"velocity":actor.velocity,"ball":game.ball.position,"ball_velocity":game.ball.velocity,"kind":actor.foot.kind,"phase":actor.foot.phase,"cut":actor.foot.touch_plan.get("cut_style",""),"requested":actor.tactical_intent.get("carry_cut",false),"cooldown":actor.ai_cut_cooldown,"reason":actor.tactical_intent.get("reason",""),"failure":actor.foot.contact_failure})
	previous=now;previous_tick=Engine.get_physics_frames()
	if t<duration:return
	began=0
	config.final_window=str(root.size);config.render_texture=str(root.get_texture().get_size())
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"config":config,"rows":rows,"contacts":contacts,"cut_events":cut_events,"carrier_rows":carrier_rows,"scope":"natural opening; actual resolution/AA/cap in config; balanced night; no capture during sample; first 3s warmup separated in analysis; CPU regions overlap; GPU measurement may be unavailable if zero"}))
	print("MOTION_FRAME_PROBE_DONE ",rows.size()," ",contacts)
	await process_frame
	# Headless observation: no claim about rendered feel or GPU performance.
	game.quit_game()

