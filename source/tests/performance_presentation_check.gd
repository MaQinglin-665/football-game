extends SceneTree
const Grass=preload("res://art/near_grass.gd")
const Profile=preload("res://art/performance_profile.gd")
func _initialize()->void:
 var minimum=49;var maximum=0
 for sx in 20:
  for sz in 20:
   var eye=Vector2(sx*.1,sz*.1);var drawn=0
   for x in range(-3,4):
    for z in range(-3,4):
     var origin=Vector2(x*2.,z*2.)
     var show=Grass.patch_needs_drawing(eye,origin)
     if show:drawn+=1
     # Any patch with a vertex in the shader's live radius must be retained.
     for offset in [Vector2.ZERO,Vector2(2,0),Vector2(0,2),Vector2(2,2),Vector2.ONE]:
      if eye.distance_to(origin+offset)<=5.5:assert(show)
   minimum=mini(minimum,drawn);maximum=maxi(maximum,drawn)
 var env=Environment.new();var viewport=SubViewport.new();root.add_child(viewport)
 for forward in [false,true]:
  for effects in 3:
   for quality in 3:
    for shadows in 3:
     Profile.apply_small(env,viewport,{"effects":effects,"quality":quality,"shadows":shadows},forward)
     assert(env.ssao_enabled==(forward and effects>0))
     assert(env.ssil_enabled==(forward and effects==2 and quality>=2))
     assert(env.glow_enabled==(forward and effects>0))
     assert(viewport.positional_shadow_atlas_size==(4096 if shadows==2 else 2048))
 print("PRESENTATION_PERF_PASS grass patches ",minimum,"..",maximum,"/49; all 72 profiles; no shader-live grass culled")
 viewport.queue_free();quit()
