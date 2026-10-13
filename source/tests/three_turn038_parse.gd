extends SceneTree
func _initialize()->void:
 var passed:bool=true
 for path in ["res://scripts/dribble_rhythm.gd", "res://scripts/football.gd", "res://scripts/foot_action.gd", "res://scripts/football_shared_movement.gd", "res://scripts/dribble_turn_control.gd", "res://tests/three_turn038_short.gd"]:
  var s:GDScript=load(path) as GDScript
  var ok:bool=s!=null and s.can_instantiate()
  print("THREE_TURN038_PARSE ",path," ",ok)
  passed=passed and ok
 quit(0 if passed else 2)
