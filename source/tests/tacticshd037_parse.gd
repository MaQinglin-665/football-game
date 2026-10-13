extends SceneTree
func _initialize()->void:
 var passed:bool=true
 for path in ["res://scripts/match.gd", "res://scripts/render_quality.gd", "res://scripts/integration_tactics.gd", "res://scripts/training/training_profile.gd", "res://scripts/training/training_mode.gd", "res://scripts/tactics/tactical_director.gd", "res://scripts/tactics/defensive_tasks.gd", "res://addons/football_character/football_character.gd", "res://addons/football_materials_b/material_patch.gd", "res://addons/publisher_checks/tacticshd037_entry.gd"]:
  var s:GDScript=load(path) as GDScript
  var ok:bool=s!=null and s.can_instantiate()
  print("TACTICSHD037_PARSE ",path," ",ok)
  passed=passed and ok
 quit(0 if passed else 2)
