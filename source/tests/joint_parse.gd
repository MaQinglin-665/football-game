extends SceneTree
func _initialize()->void:
 var checks:Array=[]
 for path in ["res://addons/football_character/surface_joint_08.gd","res://addons/football_character/football_character_base.gd","res://addons/football_character/football_character.gd","res://scripts/integration_character_pose.gd"]:
  var script:GDScript=load(path) as GDScript
  checks.append({"script":path,"compiled":script!=null and script.can_instantiate()})
 var passed:bool=checks.all(func(c):return c.compiled)
 print("JOINT030_PARSE ",JSON.stringify({"passed":passed,"checks":checks}))
 quit(0 if passed else 2)
