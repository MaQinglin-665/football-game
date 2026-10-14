extends "res://tests/three_turn043_contact_completion.gd"
func start()->void:
 evidence=ProjectSettings.globalize_path("res://../verification")
 game=load("res://scenes/training_3v3.tscn").instantiate();game.test_mode=true;root.add_child(game);current_scene=game
 for i in 4:await process_frame
 for spec in [{"name":"medium90","first":[KEY_W],"next":[KEY_D]},{"name":"fast90","first":[KEY_W,KEY_SHIFT],"next":[KEY_D,KEY_SHIFT]},{"name":"reverse","first":[KEY_W,KEY_SHIFT],"next":[KEY_S,KEY_SHIFT]},{"name":"fast_mouse90","first":[KEY_W,KEY_SHIFT],"next":[KEY_W,KEY_SHIFT],"yaw":PI/2},{"name":"medium_left90","first":[KEY_W],"next":[KEY_A]}]:
  await reset_case(spec.name,"B",Vector2(0,.28),true)
  if spec.has("yaw"):
   var dx:float=-game.player.position.x
   game.player.position.x+=dx;game.ball.position.x+=dx
   game.player.avatar._plants.clear();game.player.avatar.invalidate_pose_snapshot()
   for i in 4:await physics_frame
  set_keys(spec.first);await ticks(180)
  turn_marks.append({"case":case_name,"tick":case_tick})
  if spec.has("yaw"):
   game.player.head.mouse_axis=Vector2(-float(spec.yaw)/game.player.head.mouse_sensitivity,0);game.player.head.camera_rotation()
  set_keys(spec.next);await ticks(240)
  if DisplayServer.get_name()!="headless":
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../verification/r011_"+spec.name+".png"))
 set_keys([])
 var out:=ProjectSettings.globalize_path("res://../verification/r011_turn.json")
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--output="):out=arg.trim_prefix("--output=")
 FileAccess.open(out,FileAccess.WRITE).store_string(JSON.stringify({"marks":turn_marks,"rows":rows,"contacts":contacts}))
 print("CARRY_TURN_DONE rows=",rows.size())
 game.shutdown_audio();game.queue_free()
 for i in 4:await process_frame
 quit()

func ticks(count:int)->void:
 for i in count:
  await super.ticks(1)
  if case_name=="fast90" and case_tick in [206,219,232] and DisplayServer.get_name()!="headless":
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../verification/r011_follow_%s.png"%case_tick))
