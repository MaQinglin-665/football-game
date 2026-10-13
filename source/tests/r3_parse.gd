extends SceneTree
func _initialize()->void:
 var s:GDScript=load("res://scripts/football_agent.gd") as GDScript
 var ok:bool=s!=null and s.can_instantiate()
 print("R3_PARSE ",ok)
 quit(0 if ok else 2)
