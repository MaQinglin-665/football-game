extends SceneTree
func _initialize()->void:call_deferred("run")
func check_mesh(mesh:ArrayMesh)->int:
 var count=0
 for s in mesh.get_surface_count():
  var arrays=mesh.surface_get_arrays(s)
  var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
  var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
  assert(not vertices.is_empty())
  assert((indices.size() if not indices.is_empty() else vertices.size())%3==0)
  for index in indices:assert(index>=0 and index<vertices.size())
  for v in vertices:assert(v.is_finite())
  count+=vertices.size()
 return count
func run()->void:
 var actor=load("res://art/scripts/athlete.gd").new();root.add_child(actor)
 actor.build(Color("17529c"),7,false)
 var vertices=0
 for child in actor.skeleton.get_children():
  if child is MeshInstance3D and str(child.name).begins_with("Authored_"):
   vertices+=check_mesh(child.mesh)
   for s in child.mesh.get_surface_count():
    var arrays=child.mesh.surface_get_arrays(s)
    for bone in arrays[Mesh.ARRAY_BONES]:assert(bone>=0 and bone<actor.skeleton.get_bone_count())
 var ball=load("res://art/scripts/panel_ball.gd").make(.11)
 var ball_vertices=check_mesh(ball)
 var stand=load("res://art/training_finish.gd").new();root.add_child(stand)
 for child in stand.get_children():check_mesh(child.mesh)
 print("QUALITY_ASSETS_PASS athlete_vertices=",vertices," ball_vertices=",ball_vertices," bones=",actor.skeleton.get_bone_count()," stand_batches=",stand.get_child_count())
 actor.queue_free();stand.queue_free();await process_frame;quit()
