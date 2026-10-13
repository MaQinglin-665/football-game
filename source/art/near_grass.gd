extends Node3D
var patches:Array[MultiMeshInstance3D]=[]
var centre=Vector2i(999,999)
func _ready()->void:
 var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
 for a in [0.,1.3]:
  for v in [Vector3(-.002,0,0),Vector3(.001,.023,.005),Vector3(.002,0,0)]:
   st.set_normal(Vector3.UP);st.set_uv(Vector2(.5,v.y/.023));st.add_vertex(Basis(Vector3.UP,a)*v)
 var mesh=st.commit();var mat=ShaderMaterial.new();mat.shader=load("res://art/scripts/blades.gdshader")
 var rng=RandomNumberGenerator.new();rng.seed=6130
 for i in 49:
  var mm=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.mesh=mesh;mm.instance_count=650
  for j in mm.instance_count:mm.set_instance_transform(j,Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*rng.randf_range(.6,1.)),Vector3(rng.randf()*2,0,rng.randf()*2)))
  var n=MultiMeshInstance3D.new();n.multimesh=mm;n.material_override=mat;n.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(n);patches.append(n)
func _process(_delta:float)->void:
 var camera=get_viewport().get_camera_3d()
 if not camera:return
 var p=camera.global_position;var c=Vector2i(floori(p.x/2.),floori(p.z/2.))
 if c==centre:return
 centre=c;var i=0
 for x in range(-3,4):
  for z in range(-3,4):
   var n=patches[i];n.position=Vector3((c.x+x)*2.,.001,(c.y+z)*2.);n.visible=absf(n.position.x+1)<get_parent().game.field_half_width-1 and absf(n.position.z+1)<get_parent().game.field_half_length-1;i+=1
