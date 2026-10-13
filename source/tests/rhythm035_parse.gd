extends SceneTree
func _initialize()->void:
 var passed:bool=true
 for path in ["res://scripts/dribble_rhythm.gd", "res://scripts/football.gd", "res://scripts/ordinary_touch_scheduler.gd", "res://scripts/foot_action.gd", "res://scripts/football_shared_movement.gd", "res://addons/football_motion/lateral_support_09.gd", "res://scripts/football_agent.gd", "res://scripts/tactics/defensive_tasks.gd", "res://scripts/tactics/give_go_plan.gd", "res://scripts/tactics/tactical_director.gd"]:
  var s:GDScript=load(path) as GDScript
  var ok:bool=s!=null and s.can_instantiate()
  print("RHYTHM035_PARSE ",path," ",ok)
  passed=passed and ok
 quit(0 if passed else 2)
