extends SceneTree
var game:Node
func _initialize()->void:call_deferred("run")
func key(code:int,pressed:bool)->void:
 var e:=InputEventKey.new();e.keycode=code;e.physical_keycode=code;e.pressed=pressed
 Input.parse_input_event(e);Input.flush_buffered_events()
func run()->void:
 seed(391016);game=load("res://scenes/match.tscn").instantiate();game.test_mode=true;root.add_child(game);current_scene=game
 for i in 90:await process_frame
 game.settings_menu.values.merge({"quality":1,"effects":1,"aa":1,"upscale":0,"fps_limit":2,"volume":0},true);game.settings_menu.apply_values(false)
 root.mode=Window.MODE_WINDOWED;root.size=Vector2i(1600,900);root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED;root.content_scale_size=Vector2i.ZERO
 DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);Engine.max_fps=0
 game.start_match(false);game.services.start_match(game.rule_roster(),1);game._sync_rule_phase()
 var rows:Array=[];var t:int=Time.get_ticks_usec();var step:int=0;var last:Vector3=game.player.position;var distance:float=0.
 while Time.get_ticks_usec()-t<18000000:
  var elapsed:float=(Time.get_ticks_usec()-t)/1000000.
  if elapsed>5 and step==0:key(KEY_W,true);step=1
  if elapsed>9 and step==1:key(KEY_SHIFT,true);step=2
  elif step==2:key(KEY_SHIFT,false);step=3
  if elapsed>12:game.player.head.rotation.y+=.004
  await process_frame
  distance+=game.player.position.distance_to(last);last=game.player.position
  if rows.is_empty() or elapsed-float(rows[-1].t)>.2:rows.append({"t":elapsed,"position":game.player.position,"velocity":game.player.velocity,"phase":game.phase})
 key(KEY_W,false);key(KEY_SHIFT,false)
 var folder:String=ProjectSettings.globalize_path("res://../evidence/first_person");DirAccess.make_dir_recursive_absolute(folder)
 await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(folder+"/night_walk.png")
 game.settings_menu.values.lighting=0;game.settings_menu.apply_values(false)
 root.mode=Window.MODE_WINDOWED;root.size=Vector2i(1600,900);root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED;root.content_scale_size=Vector2i.ZERO
 for i in 30:await process_frame
 await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(folder+"/day_walk.png")
 FileAccess.open(folder+"/movement.json",FileAccess.WRITE).store_string(JSON.stringify({"distance_m":distance,"rows":rows,"scope":"Normal human player, injected W and Shift inputs and head turn; natural AI kickoff. Automated walk/run smoke, not human feel acceptance."}))
 print("WALK_DONE distance=",distance)
 game.shutdown_audio();game.queue_free();await process_frame;quit()
