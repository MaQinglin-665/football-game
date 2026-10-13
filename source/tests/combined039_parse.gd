extends SceneTree
func _initialize()->void:
 var ok:bool=true
 for path in ["res://addons/football_character/football_character.gd", "res://addons/football_character/football_character_base.gd", "res://addons/football_ground_pass/ground_pass_controller.gd", "res://addons/football_input/intent_router.gd", "res://addons/football_keeper/install.gd", "res://addons/football_keeper/keeper_avatar.gd", "res://addons/football_keeper/keeper_ball.gd", "res://addons/football_keeper/keeper_contact.gd", "res://addons/football_keeper/keeper_dive_agent.gd", "res://addons/football_keeper/keeper_dive_body.gd", "res://addons/football_keeper/keeper_dive_motion.gd", "res://addons/football_keeper/keeper_host.gd", "res://addons/football_keeper/keeper_pose.gd", "res://addons/football_motion/body_motion.gd", "res://addons/football_motion/carry_gait_039.gd", "res://addons/football_motion/directional_gait_039.gd", "res://addons/football_motion/football_motion_avatar.gd", "res://addons/football_motion/locomotion_intent_039.gd", "res://scripts/dribble_rhythm.gd", "res://scripts/dribble_turn_control.gd", "res://scripts/foot_action.gd", "res://scripts/football_agent.gd", "res://scripts/football_lower_contacts.gd", "res://scripts/football_shared_agent.gd", "res://scripts/integration_input_bridge.gd", "res://scripts/integration_tactics.gd", "res://scripts/match.gd", "res://scripts/ordinary_touch_scheduler.gd", "res://scripts/tactics/local_tackle_window.gd", "res://scripts/tactics/receive_plan.gd", "res://scripts/tactics/tactical_director.gd", "res://scripts/visual_pose_cadence39.gd"]:
  var script:GDScript=load(path) as GDScript
  var good:bool=script!=null and script.can_instantiate()
  print("COMBINED039_PARSE ",path," ",good)
  ok=ok and good
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--output="):FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE).store_string(JSON.stringify({"passed":ok,"scope":"Changed production scripts Godot4.6.3 parse and instantiate-class capability only, no gameplay."}))
 quit(0 if ok else 2)
