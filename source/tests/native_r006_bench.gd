extends "res://tests/ai_match_review.gd"
# Native 22-AI render workload with repeatable eye-height camera travel; not manual play feel.
var force_taa_off:bool=false
var tier:int=1
var effects:int=1
var folder:String
var samples:Array=[]
var startup_frames:Array=[]
var launch_us:int=Time.get_ticks_usec()
func _initialize()->void:
 for arg in OS.get_cmdline_user_args():
  if arg=="--taa-off":force_taa_off=true
  if arg.begins_with("--tier="):tier=int(arg.trim_prefix("--tier="))
  if arg.begins_with("--effects="):effects=int(arg.trim_prefix("--effects="))
  if arg.begins_with("--folder="):folder=arg.trim_prefix("--folder=")
 super._initialize()
func fixed_window()->void:
 root.mode=Window.MODE_WINDOWED;root.size=Vector2i(1600,900);root.position=Vector2i(30,50)
 root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED;root.content_scale_size=Vector2i.ZERO
 root.scaling_3d_scale=1.;Engine.max_fps=0;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
func begin()->void:
 super.begin()
 var last:int=Time.get_ticks_usec()
 for i in 90:
  await process_frame
  var now:int=Time.get_ticks_usec();startup_frames.append((now-last)/1000.);last=now
 game.settings_menu.values.merge({"quality":tier,"effects":effects,"aa":1 if tier<2 else 2,"upscale":0,"fps_limit":2,"lighting":1,"volume":0},true)
 game.settings_menu.apply_values(false);fixed_window()
 camera.fov=90.;RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
 if force_taa_off:root.use_taa=false
 var warm:int=Time.get_ticks_usec()
 while Time.get_ticks_usec()-warm<6000000:
  camera.position=Vector3(0,1.65,12);camera.look_at(Vector3(0,1.5,-40))
  await process_frame
 var started:int=Time.get_ticks_usec();last=started
 while Time.get_ticks_usec()-started<20000000:
  var t:float=(Time.get_ticks_usec()-started)/1000000.
  camera.position=Vector3(4.*sin(t*.3),1.65,12.-t*.5)
  camera.rotation=Vector3(-.02,sin(t*.45)*.65,0.)
  await process_frame
  var now:int=Time.get_ticks_usec()
  samples.append({"ms":(now-last)/1000.,"gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),"render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()),"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.,"physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.,"vram":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)})
  last=now
 var env:Environment=game.get_node("MatchEnvironment").environment
 var report:Dictionary={"tier":tier,"effects":effects,"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"cap":Engine.max_fps,"taa":root.use_taa,"msaa":root.msaa_3d,"ssao":env.ssao_enabled,"ssil":env.ssil_enabled,"tonemap":env.tonemap_mode,"exposure":env.tonemap_exposure,"actors":game.players.size(),"live_seconds":live_seconds,"startup_frames":startup_frames,"samples":samples,"scope":"20s 22-AI workload; controlled eye-height camera travel and yaw; not human input or stable 11v11 claim. Screenshots excluded from measured interval."}
 DirAccess.make_dir_recursive_absolute(folder)
 FileAccess.open(folder+"/metrics.json",FileAccess.WRITE).store_string(JSON.stringify(report))
 game.process_mode=Node.PROCESS_MODE_DISABLED
 for view in ["pitch","stands","player"]:
  if view=="pitch":camera.position=Vector3(0,1.65,12);camera.look_at(Vector3(0,1.5,-40))
  elif view=="stands":camera.position=Vector3(24,1.65,8);camera.look_at(Vector3(55,12,0))
  else:
   var actor:Node3D=game.players[2];camera.position=actor.position+Vector3(0,1.55,3);camera.look_at(actor.position+Vector3(0,1.1,0))
  for i in 8:await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(folder+"/"+view+".png")
 finished=true;game.shutdown_audio();game.queue_free();await process_frame
 print("NATIVE_R006_DONE ",folder);quit()
