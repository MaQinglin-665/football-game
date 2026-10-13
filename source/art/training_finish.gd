extends Node3D
# Small-field presentation only; no collision or rules changes.
var surfaces:Dictionary={}
func material(color:Color,rough:float)->StandardMaterial3D:
 var m=StandardMaterial3D.new();m.albedo_color=color;m.roughness=rough;return m
func box(pos:Vector3,size:Vector3,mat:Material)->void:
 var mesh=BoxMesh.new();mesh.size=size
 if not surfaces.has(mat):
  var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES);st.set_material(mat);surfaces[mat]=st
 surfaces[mat].append_from(mesh,0,Transform3D(Basis.IDENTITY,pos))
func _ready()->void:
 var steel=material(Color("75848d"),.44)
 var roof=material(Color("21333d"),.72)
 var concrete=material(Color("797c78"),.94)
 var blue=material(Color("17529c"),.67)
 var red=material(Color("b5243e"),.67)
 for side in [-1.,1.]:
  var x=side*13.8
  box(Vector3(x,.06,0),Vector3(1.8,.12,5.6),concrete)
  box(Vector3(x,2.12,0),Vector3(1.95,.09,5.7),roof)
  box(Vector3(x+side*.83,1.12,0),Vector3(.07,2.,5.5),roof)
  for z in [-2.6,0.,2.6]:
   box(Vector3(x-side*.78,1.06,z),Vector3(.055,2.1,.055),steel)
   box(Vector3(x+side*.78,1.06,z),Vector3(.055,2.1,.055),steel)
   box(Vector3(x,2.06,z),Vector3(1.7,.055,.055),steel)
  for i in 8:
   var z=-2.25+i*.64
   box(Vector3(x,.3,z),Vector3(.06,.48,.06),steel)
   # Molded seat shell: curved profile with a short rolled front edge.
   var st:SurfaceTool
   var mat=blue if side<0 else red
   if not surfaces.has(mat):st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES);st.set_material(mat);surfaces[mat]=st
   else:st=surfaces[mat]
   var profile=[Vector2(-.36,.51),Vector2(-.31,.55),Vector2(.02,.53),Vector2(.15,.59),Vector2(.22,.86),Vector2(.20,1.02)]
   for j in profile.size()-1:
    for v in [Vector3(profile[j].x*side,profile[j].y,-.25),Vector3(profile[j+1].x*side,profile[j+1].y,-.25),Vector3(profile[j].x*side,profile[j].y,.25),Vector3(profile[j].x*side,profile[j].y,.25),Vector3(profile[j+1].x*side,profile[j+1].y,-.25),Vector3(profile[j+1].x*side,profile[j+1].y,.25)]:
     st.set_normal(Vector3(-side,.4,0).normalized());st.add_vertex(v+Vector3(x,0,z))
   mat.cull_mode=BaseMaterial3D.CULL_DISABLED
 for mat in surfaces:
  var st:SurfaceTool=surfaces[mat];st.index()
  var n=MeshInstance3D.new();n.mesh=st.commit();add_child(n)
