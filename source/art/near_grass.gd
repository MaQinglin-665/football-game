extends Node3D
var patches:Array[MultiMeshInstance3D]=[]
var centre=Vector2i(999,999)
var last_visibility_eye=Vector2(INF,INF)
const FADE_END=5.5
const CULL_MARGIN=.25
static func patch_needs_drawing(eye:Vector2,origin:Vector2)->bool:
 # Shader height is already zero past 5.5m. Keep a margin for movement between updates.
 var nearest=Vector2(clampf(eye.x,origin.x,origin.x+2.),clampf(eye.y,origin.y,origin.y+2.))
 return eye.distance_squared_to(nearest)<pow(FADE_END+CULL_MARGIN,2.)
func _ready()->void:
 var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
 for a in [0.,1.3]:
  for v in [Vector3(-.0028,0,0),Vector3(.001,.017,.004),Vector3(.0028,0,0)]:
   st.set_normal(Vector3.UP);st.set_uv(Vector2(.5,v.y/.017));st.add_vertex(Basis(Vector3.UP,a)*v)
 var mesh=st.commit();var mat=ShaderMaterial.new();mat.shader=load("res://art/scripts/blades.gdshader")
 var rng=RandomNumberGenerator.new();rng.seed=6130
 for i in 49:
  var mm=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.mesh=mesh;mm.instance_count=360
  for j in mm.instance_count:mm.set_instance_transform(j,Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*rng.randf_range(.6,1.)),Vector3(rng.randf()*2,0,rng.randf()*2)))
  var n=MultiMeshInstance3D.new();n.multimesh=mm;n.material_override=mat;n.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(n);patches.append(n)
func _process(_delta:float)->void:
 visible=int(get_parent().game.settings_menu.values.grass)>0
 if not visible:return
 var camera=get_viewport().get_camera_3d()
 if not camera:return
 var p=camera.global_position;var c=Vector2i(floori(p.x/2.),floori(p.z/2.))
 var eye=Vector2(p.x,p.z)
 if c==centre and eye.distance_squared_to(last_visibility_eye)<.04:return
 centre=c;last_visibility_eye=eye
 for x in range(-3,4):
  for z in range(-3,4):
   var i=posmod(c.x+x,7)*7+posmod(c.y+z,7)
   var n=patches[i];var desired=Vector3((c.x+x)*2.,.001,(c.y+z)*2.)
   if n.position!=desired:n.position=desired
   var inside=absf(desired.x+1)<get_parent().game.field_half_width-1 and absf(desired.z+1)<get_parent().game.field_half_length-1
   n.visible=inside and patch_needs_drawing(eye,Vector2(desired.x,desired.z))
