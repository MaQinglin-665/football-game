extends SceneTree
func _initialize()->void:
 var passed:bool=true
 for path in ["res://scripts/ordinary_touch_scheduler.gd","res://scripts/football.gd","res://scripts/foot_action.gd"]:
  var s:GDScript=load(path) as GDScript
  var ok:bool=s!=null and s.can_instantiate()
  print("DOMINANT032_PARSE ",path," ",ok)
  passed=passed and ok
 quit(0 if passed else 2)
