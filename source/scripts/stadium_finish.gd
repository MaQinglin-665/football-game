extends RefCounted
const FinishShader=preload("res://scripts/stadium_finish.gdshader")
const Batch=preload("res://addons/modern_stadium/geometry_batch.gd")
static func material(color:Color,kind:int,detail:bool)->ShaderMaterial:
 var m:=ShaderMaterial.new();m.shader=FinishShader;m.set_shader_parameter("base_color",color);m.set_shader_parameter("kind",kind);m.set_shader_parameter("detail_enabled",detail);return m
static func apply(stadium:Node3D,quality:String)->void:
 var detail:bool=quality!="low"
 for entry in [["SeatBlue",Color("527787"),1],["SeatNavy",Color("314d62"),1],["Concrete",Color("777d7e"),0],["Metal",Color("667079"),2],["Roof",Color("58636b"),4]]:
  stadium.replace_material(entry[0],material(entry[1],entry[2],detail))
 var steps:MeshInstance3D=stadium.get_node_or_null("Bowl/AisleSteps")
 if steps:steps.material_override=material(Color("a2a093"),0,detail)
 var apron:MeshInstance3D=stadium.get_node_or_null("Pitch/ServiceApron")
 if apron:apron.material_override=material(Color("4a5052"),3,detail)
 if not stadium.has_meta("pitch_finish_installed"):
  stadium.set_meta("pitch_finish_installed",true)
  var seat:=seat_mesh()
  if stadium.seat_lod_meshes.size()==3:
   stadium.seat_lod_meshes[0]=seat
   for node in stadium.find_children("Seats_*","MultiMeshInstance3D",true,false):
    if int(node.get_meta("lod_level",0))==0:node.multimesh.mesh=seat
  build_edges(stadium)
 var edges:Node3D=stadium.get_node_or_null("PitchFinishDetails")
 if edges:edges.visible=detail
static func seat_mesh()->ArrayMesh:
 var b=Batch.new()
 # Three shallow segments make a moulded seat pan and tapered back; same instance count.
 b.box(Vector3(.43,.065,.32),Vector3(0,.13,-.025),Basis(Vector3.RIGHT,.05))
 b.box(Vector3(.41,.065,.09),Vector3(0,.145,-.205),Basis(Vector3.RIGHT,-.16))
 b.box(Vector3(.42,.23,.06),Vector3(0,.285,.16),Basis(Vector3.RIGHT,-.12))
 b.box(Vector3(.38,.16,.06),Vector3(0,.47,.185),Basis(Vector3.RIGHT,-.20))
 b.box(Vector3(.25,.08,.19),Vector3(0,.065,.04))
 return b.mesh()
static func build_edges(stadium:Node3D)->void:
 var d:Resource=stadium.dimensions
 var group:=Node3D.new();group.name="PitchFinishDetails";stadium.add_child(group)
 var rails=Batch.new();var drains=Batch.new();var offset:=0.0;var base_y:=1.20
 var hw:float=d.pitch_width*.5;var hl:float=d.pitch_length*.5
 # Rails follow existing aisle stairs, one shared mesh, no per-seat shadow casting.
 if stadium.get_node("Bowl").get_child_count()>0:
  for rows in d.tier_rows:
   for sec in range(d.sector_count):
    var angle:float=TAU*sec/d.sector_count
    for r in range(0,int(rows)-1,3):
     var a:Vector3=outline(hw+15+offset+r*d.row_depth,hl+16+offset+r*d.row_depth,angle,base_y+r*d.row_rise)
     var end_row:int=mini(r+3,int(rows)-1)
     var b:Vector3=outline(hw+15+offset+end_row*d.row_depth,hl+16+offset+end_row*d.row_depth,angle,base_y+end_row*d.row_rise)
     rails.rod(a+Vector3.UP*.84,b+Vector3.UP*.84,.024,4)
     rails.rod(a,a+Vector3.UP*.84,.024,4)
   offset+=int(rows)*d.row_depth+3.0;base_y+=int(rows)*d.row_rise+2.25
 var rx:float=hw+d.runoff+.12;var rz:float=hl+d.runoff+.12
 for side in [-1,1]:
  drains.box(Vector3(.15,.025,rz*2),Vector3(side*rx,0,0))
  drains.box(Vector3(rx*2,.025,.15),Vector3(0,0,side*rz))
 for pair in [["AisleHandrails",rails,Color("75818a"),2],["PitchDrainEdges",drains,Color("262d2c"),3]]:
  var mesh:=MeshInstance3D.new();mesh.name=pair[0];mesh.mesh=pair[1].mesh();mesh.material_override=material(pair[2],pair[3],true);mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;group.add_child(mesh)
static func outline(rx:float,rz:float,a:float,y:float)->Vector3:
 return Vector3(rx*signf(cos(a))*sqrt(absf(cos(a))),y,rz*signf(sin(a))*sqrt(absf(sin(a))))
