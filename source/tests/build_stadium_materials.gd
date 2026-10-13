extends SceneTree
func _initialize()->void:
 var folder="res://art/assets/concrete_cache/"
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
 for name in ["Color","NormalGL","Roughness"]:
  var im=Image.load_from_file(ProjectSettings.globalize_path("res://art/assets/Concrete034/Concrete034_1K-JPG_"+name+".jpg"))
  assert(not im.is_empty())
  if name=="Roughness":
   # Keep texture variation but fit untreated stadium concrete, not a polished floor.
   im.convert(Image.FORMAT_R8)
   var data=im.get_data()
   for i in data.size():data[i]=roundi(184.+float(data[i])*.23)
   im=Image.create_from_data(im.get_width(),im.get_height(),false,Image.FORMAT_R8,data)
  im.generate_mipmaps()
  assert(ResourceSaver.save(im,folder+name+".res")==OK)
 print("CONCRETE_CACHE_PASS source color/normal/roughness, full mip chain")
 quit()
