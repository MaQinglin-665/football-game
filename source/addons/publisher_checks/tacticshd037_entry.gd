extends Node
func _ready()->void:
 var game=get_parent()
 var eleven:bool="--eleven-tactics" in OS.get_cmdline_user_args()
 if eleven and game.scene_file_path!="res://scenes/match.tscn":
  get_tree().call_deferred("change_scene_to_file","res://scenes/match.tscn")
  return
 if not "--entry037-check" in OS.get_cmdline_user_args():queue_free();return
 call_deferred("check_entry")
func check_entry()->void:
 var game=get_parent()
 for i in 8:await get_tree().process_frame
 var eleven:bool="--eleven-tactics" in OS.get_cmdline_user_args()
 var ok:bool=game.players.size()==(22 if eleven else 6) and game.tactical_director.eleven_duties==eleven
 ok=ok and (is_equal_approx(game.services.configuration.half_seconds,600.0) if eleven else game.training_configuration!=null)
 var output:String=""
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--entry-output="):output=arg.trim_prefix("--entry-output=")
 FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"delivery_warm_usec":game.tactics_bridge.get_meta("delivery_warm_usec",-1),"lighting":game.settings_menu.lighting_fx.snapshot(),"passed":ok,"configured_half_seconds":game.services.configuration.half_seconds,"configured_match_seconds":game.match_length,"round_training":game.training_configuration!=null,"players":game.players.size(),"scene":game.scene_file_path,"eleven_duties":game.tactical_director.eleven_duties,"render_quality":game.render_quality,"shadow_range":game.get_node("MatchSun").directional_shadow_max_distance,"version":ProjectSettings.get_setting("application/config/version"),"is_debug_build":OS.is_debug_build(),"feature_release":OS.has_feature("release"),"feature_template":OS.has_feature("template"),"feature_editor":OS.has_feature("editor"),"physics_hz":Engine.physics_ticks_per_second,"time_scale":Engine.time_scale,"frame_cap":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode(),"msaa3d":get_tree().root.msaa_3d,"actual_window":str(DisplayServer.window_get_size()),"texture_size":str(get_tree().root.get_texture().get_size()),"root_size":str(get_tree().root.size),"content_factor":get_tree().root.content_scale_factor,"scale_3d":get_tree().root.scaling_3d_scale,"screen_size":str(DisplayServer.screen_get_size()),"GPU":RenderingServer.get_video_adapter_name(),"cmdline":OS.get_cmdline_args(),"user_args":OS.get_cmdline_user_args(),"pose_enabled_actors":game.players.filter(func(a):return a.pose_updates_enabled).size()}))
 print("TACTICSHD037_ENTRY ",ok," players=",game.players.size())
 reparent(get_tree().root)
 game.shutdown_audio();game.queue_free()
 for i in 4:await get_tree().process_frame
 get_tree().quit(0 if ok else 2)
