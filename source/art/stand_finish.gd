extends RefCounted
const Batch=preload("res://addons/modern_stadium/geometry_batch.gd")
func outline(rx:float,rz:float,a:float,y:float)->Vector3:
 return Vector3(rx*signf(cos(a))*sqrt(absf(cos(a))),y,rz*signf(sin(a))*sqrt(absf(sin(a))))
func add_mesh(parent:Node3D,label:String,b,hex:String,rough:float)->void:
 var mat=StandardMaterial3D.new();mat.albedo_color=Color(hex);mat.roughness=rough;mat.metallic=.15 if label.contains("Rails") else 0.
 var node=MeshInstance3D.new();node.name=label;node.mesh=b.mesh(mat);node.layers=2;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;parent.add_child(node)
func build(stadium:Node3D,parent:Node3D)->void:
 # Replace the coplanar fascia and four-sided rail; retain terrace and tunnel geometry.
 for label in ["BalconyRails","BalconyFascias"]:
  var old=stadium.get_node_or_null("Bowl/"+label)
  if old:old.visible=false
 var old_aisle=stadium.get_node_or_null("PitchFinishDetails/AisleHandrails")
 if old_aisle:old_aisle.visible=false
 # The match loads a saved stadium, so replace its meshes explicitly.
 var seat_material=StandardMaterial3D.new();seat_material.albedo_color=Color("233b4b");seat_material.roughness=.68;seat_material.metallic_specular=.25
 stadium.replace_material("SeatNavy",seat_material);stadium.replace_material("SeatBlue",seat_material)
 var seat:Mesh=preload("res://art/seat.gd").make()
 var simplified=Batch.new()
 simplified.box(Vector3(.43,.04,.44),Vector3(0,.292,-.015))
 simplified.box(Vector3(.41,.45,.045),Vector3(0,.55,.205),Basis(Vector3.RIGHT,-.10))
 var mid:Mesh=simplified.mesh()
 stadium.seat_lod_meshes.assign([seat,mid,mid])
 for node in stadium.find_children("Seats_*","MultiMeshInstance3D",true,false):
  node.multimesh.mesh=seat if int(node.get_meta("lod_level",0))==0 else mid
 for node in stadium.find_children("FarSeats_*","MeshInstance3D",true,false):node.position.y+=.17
 var rails=Batch.new();var panels=Batch.new();var bases=Batch.new();var glazing=Batch.new();var frames=Batch.new()
 var d=stadium.dimensions;var offset:float=0.;var y:float=1.2
 for tier in d.tier_rows.size():
  var rx:float=d.pitch_width*.5+15.+offset-.08
  var rz:float=d.pitch_length*.5+16.+offset-.08
  for i in 384:
   var a:float=TAU*i/384.;var b:float=TAU*(i+1)/384.
   var p:Vector3=outline(rx,rz,a,y);var q:Vector3=outline(rx,rz,b,y)
   if tier==0 and absf((p.z+q.z)*.5)<4.:continue
   panels.quad(p-Vector3.UP*.75,q-Vector3.UP*.75,q,p)
   # Continuous top rail, lower rail and spaced posts; no dense wire grid.
   rails.smooth_rod(p+Vector3.UP*.90,q+Vector3.UP*.90,.022,8)
   rails.smooth_rod(p+Vector3.UP*.42,q+Vector3.UP*.42,.016,6)
   if i%2==0:
    rails.smooth_rod(p,p+Vector3.UP*.90,.022,8)
    bases.box(Vector3(.09,.028,.09),p+Vector3.UP*.014)
  # Recessed concourse glazing occupies the otherwise empty black inter-tier gap.
  if tier>0:
   for i in 192:
    var a:float=TAU*i/192.;var b:float=TAU*(i+1)/192.
    var p:Vector3=outline(rx+.28,rz+.28,a,y-1.08)
    var q:Vector3=outline(rx+.28,rz+.28,b,y-1.08)
    var tint:Color=Color(.50,.58,.66) if i%7<2 else Color(.85,.76,.57)
    glazing.quad(p-Vector3.UP*.72,q-Vector3.UP*.72,q,p,Vector2.ONE,tint)
    frames.smooth_rod(p-Vector3.UP*.75,p+Vector3.UP*.05,.025,6)
    frames.smooth_rod(p+Vector3.UP*.03,q+Vector3.UP*.03,.025,6)
  # Handrails follow existing stair centrelines, with clear openings at the front.
  for sector in d.sector_count:
   var a:float=TAU*sector/d.sector_count
   var previous:Vector3=Vector3.ZERO
   for row in d.tier_rows[tier]:
    if tier==0 and row<6 and absf(sin(a))<.001:continue
    var at:Vector3=outline(rx+.08+row*d.row_depth,rz+.08+row*d.row_depth,a,y+row*d.row_rise)
    if previous!=Vector3.ZERO:rails.smooth_rod(previous+Vector3.UP*.88,at+Vector3.UP*.88,.020,8)
    if row%3==0:rails.smooth_rod(at,at+Vector3.UP*.88,.020,8)
    previous=at
  offset+=d.tier_rows[tier]*d.row_depth+3.
  y+=d.tier_rows[tier]*d.row_rise+2.25
 add_mesh(parent,"RefinedStandRails",rails,"66727b",.63)
 add_mesh(parent,"StandFasciaPanels",panels,"303b47",.88)
 add_mesh(parent,"RailAnchorPlates",bases,"414b55",.7)

 var glassmat=StandardMaterial3D.new();glassmat.albedo_color=Color("56616a");glassmat.vertex_color_use_as_albedo=true;glassmat.roughness=.55
 glassmat.emission_enabled=true;glassmat.emission=Color("807667");glassmat.emission_energy_multiplier=.22;glassmat.cull_mode=BaseMaterial3D.CULL_DISABLED
 var glassnode=MeshInstance3D.new();glassnode.name="RecessedConcourseWindows";glassnode.mesh=glazing.mesh(glassmat);glassnode.layers=2;glassnode.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;parent.add_child(glassnode)
 add_mesh(parent,"ConcourseFrames",frames,"35414a",.75)
