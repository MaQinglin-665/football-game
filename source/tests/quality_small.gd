extends SceneTree
var game:Node
var folder:String
func _initialize()->void:call_deferred("run")
func run()->void:
 seed(6130)
 folder=ProjectSettings.globalize_path("res://../evidence/quality_r5/"+OS.get_environment("FC_CAPTURE"))
 DirAccess.make_dir_recursive_absolute(folder)
 game=load("res://scenes/match_6v6_small.tscn").instantiate();root.add_child(game)
 await create_timer(3.).timeout
 game.settings_menu.values.quality=1;game.settings_menu.values.aa=2;game.settings_menu.values.volume=0
 if game.settings_menu.values.has("upscale"):game.settings_menu.values.upscale=1 if OS.get_environment("FC_CAPTURE")=="fsr" else 0
 game.settings_menu.apply_values(false)
 root.mode=Window.MODE_WINDOWED;root.size=Vector2i(1600,900)
 DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);Engine.max_fps=120
 game.start_match()
 await create_timer(3.).timeout
 var frames:Array=[];var previous:int=Time.get_ticks_usec()
 for i in 720:
  if game.is_restart_taker(game.player):game.input_bridge.focused=true
  game.player.turn_view(game.player.rotation.y+.004)
  await process_frame
  var now:int=Time.get_ticks_usec();frames.append((now-previous)/1000.);previous=now
 var total:float=0.
 for value in frames:total+=value
 frames.sort()
 var result={"fps":1000.*frames.size()/total,"p95_ms":frames[int(frames.size()*.95)],"p99_ms":frames[int(frames.size()*.99)],"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"video_mib":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)/1048576.,"render_scale":root.scaling_3d_scale,"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"scope":"Turning view; background CPU activity recorded by runner; not a gameplay latency test."}
 FileAccess.open(folder+"/metrics.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
 game.process_mode=Node.PROCESS_MODE_DISABLED;game.hud.visible=false
 var actor=game.agents[4];actor.position=Vector3(0,0,0);actor.avatar.visual.rotation.y=0
 for j in actor.avatar.skeleton.get_bone_count():actor.avatar.skeleton.reset_bone_pose(j)
 actor.reset_physics_interpolation();game.ball.position=Vector3(.65,.115,-.5);game.ball.reset_physics_interpolation()
 var camera=Camera3D.new();root.add_child(camera);camera.current=true;camera.fov=65.;camera.near=.03
 for mode in [0,1]:
  game.settings_menu.values.lighting=mode;game.settings_menu.apply_values(false)
  root.mode=Window.MODE_WINDOWED;root.size=Vector2i(1600,900)
  for shot in ["player","ball","pitch"]:
   camera.position=Vector3(.9,1.4,-2.8) if shot=="player" else Vector3(1.,.38,-1.05) if shot=="ball" else Vector3(10.,1.65,14.)
   camera.look_at(Vector3(0,1.,0) if shot=="player" else Vector3(.65,.115,-.5) if shot=="ball" else Vector3(0,1.,0))
   for i in 12:await process_frame
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png(folder+"/"+shot+("_day" if mode==0 else "_night")+".png")
 print("QUALITY_PROBE ",JSON.stringify(result))
 game.shutdown_audio();quit()
