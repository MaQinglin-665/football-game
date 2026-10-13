extends SceneTree
func _initialize()->void:call_deferred("run")
func triangles(mesh:Mesh)->int:
 var total=0
 for i in mesh.get_surface_count():
  var a=mesh.surface_get_arrays(i)
  total+=(a[Mesh.ARRAY_INDEX].size() if a[Mesh.ARRAY_INDEX].size()>0 else a[Mesh.ARRAY_VERTEX].size())/3
 return total
func run()->void:
 var Crowd=load("res://art/crowd_body.gd");var Architecture=load("res://art/bernabeu.gd")
 var geometry=[]
 for i in 8:
  var builder=Crowd.new();var mid=builder.make(i,false);var far=builder.make(i,false,true)
  assert(triangles(far)<triangles(mid))
  # Full body, including standing variation, retains its vertical envelope.
  assert(absf(mid.get_aabb().end.y-far.get_aabb().end.y)<.05)
  geometry.append({"variant":i,"mid_triangles":triangles(mid),"far_triangles":triangles(far)})
 assert(Architecture.crowd_level(23.*23.,1)==0)
 assert(Architecture.crowd_level(30.*30.,0)==0)
 assert(Architecture.crowd_level(79.*79.,1)==2)
 assert(Architecture.crowd_level(70.*70.,2)==2)
 assert(Architecture.crowd_level(67.*67.,2)==1)
 var env=Environment.new();var viewport=SubViewport.new();root.add_child(viewport)
 for effects in 3:
  preload("res://art/performance_profile.gd").apply_stadium(env,viewport,{"effects":effects,"quality":1},true)
  assert(env.ssao_enabled==(effects>0));assert(env.ssil_enabled==(effects==2));assert(viewport.positional_shadow_atlas_size==4096)
 viewport.queue_free()
 var game=load("res://scenes/match.tscn").instantiate();root.add_child(game)
 await process_frame
 assert(game.players.size()==22)
 var art=Architecture.new();game.add_child(art);art.build(game.stadium)
 var spectators=0
 for entry in art.crowd_lods:spectators+=entry[0].multimesh.instance_count
 assert(spectators==art.crowd_count and spectators>1000)
 # The dummy renderer cannot retrieve saved MultiMesh transforms reliably. Do not
 # derive field-camera visibility or submitted triangle counts from this run.
 var report={"players":22,"constructed_instances_headless":spectators,"constructed_batches":art.crowd_lods.size(),"geometry":geometry,"scope":"Headless construction and per-model geometry only. Saved MultiMesh poses/real LOD distribution need native verification; no FPS estimate."}
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../evidence/stadium_r7"))
 FileAccess.open("res://../evidence/stadium_r7/geometry.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
 print("STADIUM_R7_PASS ",JSON.stringify(report))
 game.shutdown_audio();game.queue_free();await process_frame;quit()
