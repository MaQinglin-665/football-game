extends SceneTree
func _initialize()->void:
 var passed:bool=true
 for path in ["res://scripts/ordinary_touch_scheduler.gd", "res://scripts/football.gd", "res://scripts/football_player.gd", "res://scripts/foot_action.gd", "res://addons/football_motion/football_motion_avatar.gd", "res://addons/football_motion/lateral_support_09.gd"]:
  var script:GDScript=load(path) as GDScript
  var ok:bool=script!=null and script.can_instantiate()
  print("CONTINUOUS033_PARSE ",path," ",ok)
  passed=passed and ok
 quit(0 if passed else 2)
