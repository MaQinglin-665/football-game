extends Node3D
# Architectural lighting stays off the pitch and dynamic players.
var lights:Array[Light3D]=[]
var faces:Array[MeshInstance3D]=[]
func outline(rx:float,rz:float,a:float,y:float)->Vector3:
 return Vector3(rx*signf(cos(a))*sqrt(absf(cos(a))),y,rz*signf(sin(a))*sqrt(absf(sin(a))))
func build(stadium:Node3D)->void:
 for mesh in stadium.get_node("Roof").find_children("*","GeometryInstance3D",true,false):mesh.layers=4
 var d=stadium.dimensions
 var h:float=3.6
 for rows in d.tier_rows:h+=rows*d.row_rise+2.25
 # White roof-mounted banks illuminate all seating tiers, with overlapping cones.
 for i in 20:
  var a:float=TAU*(i+.5)/16. if i<16 else TAU*(i-16)/4.
  var at:Vector3=outline(d.pitch_width*.5+10.,d.pitch_length*.5+12.,a,h-.8)
  var target:Vector3=outline(d.pitch_width*.5+34.,d.pitch_length*.5+35.,a,18.)
  var lamp=SpotLight3D.new();add_child(lamp);lamp.position=at;lamp.look_at(target)
  lamp.spot_range=75.;lamp.spot_angle=64.;lamp.spot_attenuation=.40
  lamp.light_color=Color("f2f3f5");lamp.light_energy=.55;lamp.light_specular=.18
  lamp.light_cull_mask=10;lamp.shadow_enabled=false;lamp.set_meta("night_energy",.55);lights.append(lamp)
  fixture(lamp.transform,Vector3(2.2,.28,.22),lamp.light_color)
 # Broad reflected light on the bowl fronts, excluded from pitch and roof.
 for azimuth in [-40.,140.]:
  var fill=DirectionalLight3D.new();add_child(fill);fill.rotation_degrees=Vector3(-18.,azimuth,0.)
  fill.light_color=Color("dce4ec");fill.light_energy=.60;fill.light_cull_mask=10;fill.light_specular=0.;fill.shadow_enabled=false
  fill.set_meta("night_energy",.60);lights.append(fill)
 # Warm balcony wash provides a second, bounded layer between the blue seat tiers.
 var offset:float=0.;var y:float=1.2
 for tier in d.tier_rows.size():
  if tier>0:
   for i in 12:
    var a:float=TAU*(i+.5)/12.
    var at:Vector3=outline(d.pitch_width*.5+15.+offset,d.pitch_length*.5+16.+offset,a,y-.35)
    var lamp=OmniLight3D.new();add_child(lamp);lamp.position=at
    lamp.omni_range=7.;lamp.omni_attenuation=1.4;lamp.light_color=Color("ffe2b1")
    lamp.light_energy=1.8;lamp.light_specular=.1;lamp.light_cull_mask=2;lamp.shadow_enabled=false
    lamp.set_meta("night_energy",1.8);lights.append(lamp)
    var basis=Basis(Vector3.UP,atan2(at.x,at.z))
    fixture(Transform3D(basis,at),Vector3(2.6,.07,.10),lamp.light_color)
  offset+=d.tier_rows[tier]*d.row_depth+3.
  y+=d.tier_rows[tier]*d.row_rise+2.25
func fixture(t:Transform3D,size:Vector3,color:Color)->void:
 var mesh=MeshInstance3D.new();var box=BoxMesh.new();box.size=size;mesh.mesh=box
 var mat=StandardMaterial3D.new();mat.albedo_color=color;mat.emission_enabled=true;mat.emission=color;mat.emission_energy_multiplier=1.5
 mesh.material_override=mat;mesh.transform=t;mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 add_child(mesh);faces.append(mesh)
func set_night(night:bool)->void:
 for lamp in lights:lamp.visible=night;lamp.light_energy=float(lamp.get_meta("night_energy")) if night else 0.
 for face in faces:face.visible=night
