extends SceneTree
func _initialize()->void:
 var passed:bool=true
 for path in ["res://scripts/football.gd", "res://scripts/match.gd", "res://scripts/foot_action.gd", "res://addons/football_ground_pass/ground_pass_solution.gd", "res://addons/publisher_checks/receivepass034_chain.gd"]:
  var s:GDScript=load(path) as GDScript
  var ok:bool=s!=null and s.can_instantiate()
  print("RECEIVEPASS034_PARSE ",path," ",ok)
  passed=passed and ok
 quit(0 if passed else 2)
