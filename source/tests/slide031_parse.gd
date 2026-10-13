extends SceneTree
func _initialize()->void:
 var passed:bool=true
 for path in ["res://addons/football_interaction/slide_interaction.gd", "res://addons/football_interaction/low_body_state.gd", "res://addons/football_interaction/low_action_pose.gd", "res://scripts/football_shared_player.gd", "res://scripts/football_shared_agent.gd", "res://addons/publisher_checks/slide031_check.gd"]:
  var script:GDScript=load(path) as GDScript
  var ok:bool=script!=null and script.can_instantiate()
  print("SLIDE031_PARSE ",path," ",ok)
  passed=passed and ok
 quit(0 if passed else 2)
