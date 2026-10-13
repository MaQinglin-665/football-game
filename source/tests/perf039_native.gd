extends SceneTree
const Bucket:=preload("res://tests/perf039_bucket.gd")
var game:Node
var output:String=""
var stage:String="baseline"
var quality:String=""
var rows:Array=[]
var begun:int=0
var sampled:int=0
var previous:int=0
var measurement:bool=false
var ending:bool=false
var contacts:int=0
var config:Dictionary={}
var long_frames:int=0
var setup_started39:int=0
func _initialize()->void:
 setup_started39=Time.get_ticks_usec()
 for a in OS.get_cmdline_user_args():
  if a.begins_with("--output="):output=a.trim_prefix("--output=")
  if a.begins_with("--stage="):stage=a.trim_prefix("--stage=")
 Engine.max_fps=120
 DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
 seed(3901);call_deferred("begin")
func begin()->void:
 game=load("res://scenes/match.tscn").instantiate();game.test_mode=true;root.add_child(game);current_scene=game
 for i in 8:await process_frame
 game.hud.menu.get_node("StartMatch").pressed.emit()
 for i in 8:await physics_frame
 # DeclaredLIVE fixture. Natural kickoff is not part of this frame benchmark.
 game.services.rules.restart.clear();game.services.rules._become_live();game.set_phase(game.Phase.PLAY);game.ball.set_held(false)
 game.player.position=Vector3(0,.002,3)
 game.ball.reset(game.player.position+Vector3(0,0,-.5));game.ball.take(game.player)
 var camera:=Camera3D.new();game.add_child(camera)
 camera.global_transform=game.player.camera.global_transform;camera.current=true
 game.contact_hub.contact_resolved.connect(func(e):
  if e.get("success",false):contacts+=1)
 var monitors:Dictionary={"process_seconds":Performance.get_monitor(Performance.TIME_PROCESS),"physics_seconds":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)}
 quality=game.render_quality
 config={"stage":stage,"quality":quality,"pid":OS.get_process_id(),"screen":str(DisplayServer.screen_get_size()),"refresh_rate":DisplayServer.screen_get_refresh_rate(),"window_size":str(root.size),"viewport_visible_size":str(root.get_visible_rect().size),"viewport_texture_size":str(root.get_texture().get_size()),"content_scale_size":str(root.content_scale_size),"content_scale_mode":root.content_scale_mode,"window_mode":root.mode,"msaa3d":root.msaa_3d,"vsync":DisplayServer.window_get_vsync_mode(),"frame_cap":Engine.max_fps,"physics120":Engine.physics_ticks_per_second,"gpu":RenderingServer.get_video_adapter_name(),"gpu_vendor":RenderingServer.get_video_adapter_vendor(),"rendering_method":ProjectSettings.get_setting("rendering/renderer/rendering_method"),"camera_transform":str(camera.global_transform),"actors":game.players.size(),"AI_active":game.agents.size(),"render_texture_readback_size":str(root.get_texture().get_image().get_size()),"screen_scale":DisplayServer.screen_get_scale(),"screen_dpi":DisplayServer.screen_get_dpi(),"os_window_size":str(DisplayServer.window_get_size()),"content_scale_factor":root.content_scale_factor,"scaling3d":root.scaling_3d_scale,"monitors_start":monitors,"last_shadow_atlas_setter_size":Bucket.shadow_size,"shadow_setters":Bucket.shadow_setters,"shadow_distance":game.get_node("MatchSun").directional_shadow_max_distance}
 begun=Time.get_ticks_usec();previous=begun
func _process(_delta:float)->bool:
 if begun==0 and not ending and Time.get_ticks_usec()-setup_started39>8000000:
  ending=true
  FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"status":"ABORT_SETUP_NOT_READY","pid":OS.get_process_id()}))
  quit(2)
 if begun==0 or ending:return false
 var now:int=Time.get_ticks_usec()
 var elapsed:float=float(now-begun)/1000000.0
 if not measurement and elapsed>=1.5:
  measurement=true;sampled=now;previous=now;Bucket.totals.clear();Bucket.enabled=true
  for actor in game.players:actor.avatar.reset_pose_refresh_counters()
 if measurement:
  var ms:float=float(now-previous)/1000.0;previous=now
  rows.append({"frame":Engine.get_process_frames(),"elapsed":float(now-sampled)/1000000.0,"frame_ms":ms,"physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0,"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,"render_setup_cpu_ms":RenderingServer.call("get_frame_setup_time_cpu") if RenderingServer.has_method("get_frame_setup_time_cpu") else -1.0,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),"objects":Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),"ram_static":Performance.get_monitor(Performance.MEMORY_STATIC),"video_mem":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),"physics_frame":Engine.get_physics_frames()})
  long_frames=long_frames+1 if ms>500.0 else 0
  if long_frames>=3:finish("ABORT_three_frames_over500ms")
  elif now-sampled>=4000000:finish("completed")
 if elapsed>9.0 and not ending:finish("ABORT_setup_or_measurement_timeout")
 return false
func finish(status:String)->void:
 ending=true;Bucket.enabled=false
 var pose_counts:Array=[]
 for actor in game.players:pose_counts.append({"team":actor.team,"human":actor.is_human,"keeper":actor.is_goalkeeper,"pose":actor.avatar.get_pose_refresh_debug()})
 var report:Dictionary={"pose_counters":pose_counts,"status":status,"config":config,"rows":rows,"inclusive_cpu_function_usec_and_calls":Bucket.totals.duplicate(true),"successful_contacts":contacts,"scope":"Native GL real22avatars+21AI/World, fixedextra camera and no human input, 120cap/VSyncdisabled, 1.5s warmup+4s wallmeasurement. DeclaredLIVE skipskickoff. Inclusive timings overlap, cannot sum. Instrumentation matched baseline/candidate. No fullmatch/stability acceptance."}
 FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
 print("PERF039 ",stage," ",quality," ",status," frames=",rows.size())
 game.shutdown_audio();game.queue_free()
 for i in 4:await process_frame
 quit(0 if status=="completed" else 2)
