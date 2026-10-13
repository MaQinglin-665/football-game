extends "res://tests/tactical_flow_review.gd"
# Rendered natural match evidence. Camera/recording are test-only; no gameplay writes.
var capture_start:float=0
var capture_end:float=40
var capture_dir:String=""
var frame_number:int=0
var last_capture:float=-1
var capture_busy:bool=false
var label:Label
const CAPTURE_FPS:float=24.0
const CUT_PRE_SECONDS:float=.8
const CUT_CLIP_SECONDS:float=4.0
const MAX_CUT_CLIPS:int=3
var capture_cuts:bool=false
var next_capture:float=-1
var frame_buffer:Array=[]
var active_clip:Dictionary={}
var saved_clips:Array=[]
var continuous_frames:Array=[]
var seen_cuts:Dictionary={}
var last_clip_end:float=-INF
var capture_closed:bool=false
class CaptureObserver extends Node:
	var host
	func _process(dt:float)->void:host.render_frame(dt)

func begin()->void:
	var explicit_end:bool=false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-start="):capture_start=float(arg.trim_prefix("--capture-start="))
		if arg.begins_with("--capture-end="):capture_end=float(arg.trim_prefix("--capture-end="));explicit_end=true
		if arg.begins_with("--capture-dir="):capture_dir=arg.trim_prefix("--capture-dir=")
		if arg=="--capture-cuts":capture_cuts=true
	if capture_cuts and not explicit_end:capture_end=duration
	super.begin()
	root.mode=Window.MODE_WINDOWED;root.size=Vector2i(1280,720)
	game.settings_menu.values.volume=0;game.settings_menu.apply_values(false)
	if is_instance_valid(camera):
		camera.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
		camera.fov=58
	if not capture_dir.is_empty():DirAccess.make_dir_recursive_absolute(capture_dir)
	var layer:=CanvasLayer.new();root.add_child(layer)
	# Keep the upper-left instructions and central scoreboard unobscured.
	label=Label.new();label.position=Vector2(850,96);label.size=Vector2(410,44)
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size",14)
	label.add_theme_constant_override("outline_size",3)
	label.add_theme_color_override("font_outline_color",Color(0,0,0,.85))
	layer.add_child(label)
	if capture_cuts:game.contact_hub.contact_resolved.connect(_on_capture_contact)
	var observer:=CaptureObserver.new();observer.host=self;root.add_child(observer)
	_write_capture_manifest()

func observe(dt:float)->void:
	# Flush even a partial final clip before the inherited normal shutdown.
	if not finished and (elapsed+dt>=duration or full_match and game.services.rules.state_name()=="FULL_TIME"):
		_close_capture("match_end")
	super.observe(dt)

func render_frame(dt:float)->void:
	if finished or not is_instance_valid(camera) or not is_instance_valid(game):return
	var focus:Vector3=game.ball.position;focus.y=.7
	var wanted:Vector3=focus+(Vector3(5,8,11) if capture_cuts else Vector3(7,13,17))
	camera.position=camera.position.lerp(wanted,1.0-exp(-dt*5.0))
	camera.look_at(focus)
	label.text="自然对抗观察录像 · 试玩仍为第一人称\n模拟 %.2f s%s" % [elapsed," · 扣球片段 %d/%d" % [saved_clips.size(),MAX_CUT_CLIPS] if capture_cuts else ""]
	if capture_closed or capture_busy or capture_dir.is_empty() or elapsed<capture_start:return
	if elapsed>capture_end:
		_close_capture("capture_window_end");return
	if next_capture<0:next_capture=elapsed
	if elapsed+.00001<next_capture:return
	# Advance a fixed sampling clock: 60 Hz physics otherwise quantizes 24 fps to 20.
	# Missed render slots are not duplicated; the manifest preserves their real gaps.
	next_capture+=(floor(maxf(0,elapsed-next_capture)*CAPTURE_FPS)+1.0)/CAPTURE_FPS
	capture_busy=true
	await RenderingServer.frame_post_draw
	if capture_closed or finished:
		capture_busy=false;return
	last_capture=elapsed
	var frame:Dictionary={"simulation_time_s":elapsed,"physics_frame":Engine.get_physics_frames(),"wall_time_us":Time.get_ticks_usec(),"jpeg":root.get_texture().get_image().save_jpg_to_buffer(.88)}
	if capture_cuts:
		frame_buffer.append(frame)
		while not frame_buffer.is_empty() and float(frame_buffer[0].simulation_time_s)<elapsed-CUT_PRE_SECONDS:
			frame_buffer.pop_front()
		if not active_clip.is_empty():
			_save_frame(frame,active_clip.directory,active_clip.frames)
			if elapsed>=float(active_clip.requested_end_s):_finish_clip("window_complete")
	else:
		_save_frame(frame,capture_dir,continuous_frames)
		frame_number=continuous_frames.size()
	capture_busy=false

func _on_capture_contact(event:Dictionary)->void:
	if not capture_cuts or capture_closed or capture_dir.is_empty() or not active_clip.is_empty() or saved_clips.size()>=MAX_CUT_CLIPS:return
	if elapsed<capture_start or elapsed>capture_end or elapsed-CUT_PRE_SECONDS<=last_clip_end:return
	if not event.get("success",false) or event.get("kind","")!="FOOT_TOUCH" or event.get("action","")!="TURN":return
	var actor:Node3D=event.get("actor")
	if not is_instance_valid(actor) or actor.is_human:return
	var style:String=String(actor.foot.touch_plan.get("cut_style",""))
	if style.is_empty():return
	var identity:String="%d:%d:%d" % [game.match_generation,game.players.find(actor),actor.foot.sequence]
	if seen_cuts.has(identity):return
	seen_cuts[identity]=true
	var directory:String=capture_dir.path_join("cut_%02d" % (saved_clips.size()+1))
	if DirAccess.make_dir_recursive_absolute(directory)!=OK:
		push_error("Could not create capture directory: "+directory);return
	active_clip={"directory":directory,"trigger":{"simulation_time_s":elapsed,"physics_frame":event.get("physics_frame",Engine.get_physics_frames()),"contact_serial":event.get("serial",-1),"actor_id":game.players.find(actor),"team":actor.team,"jersey":actor.jersey,"foot_sequence":actor.foot.sequence,"cut_style":style,"source":"successful FOOT_TOUCH / TURN"},"requested_start_s":maxf(capture_start,elapsed-CUT_PRE_SECONDS),"requested_end_s":elapsed+CUT_CLIP_SECONDS-CUT_PRE_SECONDS,"frames":[]}
	for frame:Dictionary in frame_buffer:
		if float(frame.simulation_time_s)>=float(active_clip.requested_start_s) and float(frame.simulation_time_s)>last_clip_end:
			_save_frame(frame,directory,active_clip.frames)
	_write_capture_manifest()

func _save_frame(frame:Dictionary,directory:String,records:Array)->void:
	# A trigger can arrive between scheduling and readback; never duplicate its frame.
	if not records.is_empty() and float(frame.simulation_time_s)<=float(records[-1].simulation_time_s):return
	var name:String="frame_%05d.jpg" % records.size()
	var file:FileAccess=FileAccess.open(directory.path_join(name),FileAccess.WRITE)
	if file==null:
		push_error("Could not write capture frame: "+directory.path_join(name));return
	file.store_buffer(frame.jpeg);file.close()
	if not records.is_empty():records[-1].duration_to_next_s=float(frame.simulation_time_s)-float(records[-1].simulation_time_s)
	records.append({"file":name,"simulation_time_s":frame.simulation_time_s,"physics_frame":frame.physics_frame,"wall_time_us":frame.wall_time_us,"duration_to_next_s":null})

func _finish_clip(reason:String)->void:
	if active_clip.is_empty():return
	active_clip.status=reason
	var frames:Array=active_clip.frames
	active_clip.observed_span_s=0.0 if frames.is_empty() else float(frames[-1].simulation_time_s)-float(frames[0].simulation_time_s)
	active_clip.recommended_last_frame_hold_s=1.0/CAPTURE_FPS
	active_clip.frame_timing="Encode adjacent simulation_time_s differences; do not assume evenly spaced 24 fps. Last frame hold is separate from observed span."
	if not frames.is_empty():last_clip_end=float(frames[-1].simulation_time_s)
	_write_json(String(active_clip.directory).path_join("manifest.json"),active_clip)
	saved_clips.append(active_clip.duplicate(true));active_clip.clear()
	_write_capture_manifest()
	if saved_clips.size()>=MAX_CUT_CLIPS and reason=="window_complete":duration=minf(duration,elapsed+.1)

func _close_capture(reason:String)->void:
	if capture_closed:return
	capture_closed=true
	_finish_clip(reason)
	_write_capture_manifest()
	frame_buffer.clear()

func _write_capture_manifest()->void:
	if capture_dir.is_empty():return
	var data:Dictionary={"mode":"cuts" if capture_cuts else "continuous","seed":seed_value,"nominal_capture_fps":CAPTURE_FPS,"simulation_time_source":"Inherited natural-match elapsed clock; each image stamped after frame_post_draw.","camera":"test observer only; physics interpolation disabled","capture_start_s":capture_start,"capture_end_s":capture_end,"closed":capture_closed,"scope":"Recording does not write ball/player state. Readback/encoding overhead is not a game-performance benchmark."}
	if capture_cuts:
		data.pre_seconds=CUT_PRE_SECONDS;data.clip_seconds=CUT_CLIP_SECONDS;data.maximum_clips=MAX_CUT_CLIPS
		data.clips=saved_clips;data.active_clip=active_clip
	else:
		data.frames=continuous_frames;data.recommended_last_frame_hold_s=1.0/CAPTURE_FPS
	_write_json(capture_dir.path_join("manifest.json"),data)

func _write_json(path:String,data:Dictionary)->void:
	var file:FileAccess=FileAccess.open(path,FileAccess.WRITE)
	if file==null:push_error("Could not write capture manifest: "+path);return
	file.store_string(JSON.stringify(data,"  "));file.close()
