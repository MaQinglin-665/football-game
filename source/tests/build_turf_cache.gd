extends SceneTree
func _initialize()->void:
 var base="res://art/assets/Grass005/"
 var path="res://art/assets/turf_cache/"
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
 var raw=FileAccess.get_file_as_bytes("res://../evidence/performance_r6/grass_ra.bin")
 assert(raw.size()==2048*2048*2)
 var packed=Image.create_from_data(2048,2048,false,Image.FORMAT_RG8,raw)
 packed.generate_mipmaps()
 assert(ResourceSaver.save(packed,path+"roughness_ao.res")==OK)
 for name in ["Color","NormalGL"]:
  var im=Image.load_from_file(ProjectSettings.globalize_path(base+"Grass005_2K-JPG_"+name+".jpg"))
  im.generate_mipmaps()
  assert(ResourceSaver.save(im,path+name+".res")==OK)
 var ao=Image.load_from_file(ProjectSettings.globalize_path(base+"Grass005_2K-JPG_AmbientOcclusion.jpg"))
 var rough=Image.load_from_file(ProjectSettings.globalize_path(base+"Grass005_2K-JPG_Roughness.jpg"))
 var saved:Image=load(path+"roughness_ao.res")
 for y in range(0,2048,37):
  for x in range(0,2048,31):
   assert(absf(saved.get_pixel(x,y).r-rough.get_pixel(x,y).r)<.0001)
   assert(absf(saved.get_pixel(x,y).g-ao.get_pixel(x,y).r)<.0001)
 print("TURF_CACHE_PASS linear RG8 channels exact, mipmaps=",saved.get_mipmap_count())
 quit()
