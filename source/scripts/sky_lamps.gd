extends Node3D
# Bounded presentation: four local flood banks, one shadow caster at most.
var game:Node
var sky_material:ShaderMaterial
var lamps:Array[SpotLight3D]=[]
var fixtures:Node3D
var stand_lights:Array[OmniLight3D]=[]
var stand_faces:Array[MeshInstance3D]=[]
func _ready()->void:
 sky_material=ShaderMaterial.new();sky_material.shader=preload("res://scripts/broadcast_sky.gdshader")
 var environment:Environment=game.get_node("MatchEnvironment").environment
 environment.sky=Sky.new();environment.sky.sky_material=sky_material
 environment.sky.process_mode=Sky.PROCESS_MODE_QUALITY
 environment.sky.radiance_size=Sky.RADIANCE_SIZE_128
 fixtures=Node3D.new();fixtures.name="FourLocalFloodBanks";add_child(fixtures)
 var small:bool=game.field_half_width<22
 var height:float=14 if small else 34.9
 var w:float=game.field_half_width+6.0
 for side in [-1.0,1.0]:
  for end in [-1.0,1.0]:
   var at:=Vector3(w*side,height,game.field_half_length*.50*end)
   var lamp:=SpotLight3D.new();fixtures.add_child(lamp);lamp.position=at;lamp.look_at(Vector3(0,.5,game.field_half_length*.20*end))
   lamp.spot_range=125 if not small else 42;lamp.spot_angle=67 if not small else 55;lamp.spot_attenuation=.20 if not small else .35
   lamp.light_color=Color("d8e7ff") if side<0 else Color("fff0d8")
   lamp.light_specular=.45;lamp.shadow_enabled=false;lamps.append(lamp)
   var casing:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(2.5,.6,.22);casing.mesh=box;casing.transform=lamp.transform
   var mat:=StandardMaterial3D.new();mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;mat.albedo_color=lamp.light_color;casing.material_override=mat
   casing.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;fixtures.add_child(casing)
   if small:
    var pole:=MeshInstance3D.new();var cylinder:=CylinderMesh.new();cylinder.top_radius=.10;cylinder.bottom_radius=.16;cylinder.height=height;cylinder.radial_segments=8
    pole.mesh=cylinder;pole.position=Vector3(at.x,height*.5,at.z);pole.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    var metal:=StandardMaterial3D.new();metal.albedo_color=Color("596675");metal.roughness=.75;pole.material_override=metal;add_child(pole)
 if not small:_build_stand_lights()
func _build_stand_lights()->void:
 # A separate layer keeps these six shadowless zones off players and the pitch.
 for branch in ["Bowl","Roof"]:
  var node:Node=game.stadium.get_node_or_null(branch)
  if node:
   for mesh in node.find_children("*","GeometryInstance3D",true,false):mesh.layers=2
 for lamp in lamps:lamp.light_cull_mask=1
 var w:float=game.field_half_width;var length:float=game.field_half_length
 var positions:Array[Vector3]=[]
 for side in [-1.0,1.0]:
  for end in [-1.0,1.0]:positions.append(Vector3(side*(w+16),14,end*length*.52))
 for end in [-1.0,1.0]:positions.append(Vector3(0,14,end*(length+16)))
 positions[0]=Vector3(-26,19,-64);positions[2]=Vector3(26,19,-64);positions[4]=Vector3(0,29,-74)
 for at in positions:
  var light:=OmniLight3D.new();add_child(light);light.position=at;light.omni_range=60 if at.z< -60 else 42;light.omni_attenuation=.35 if at.z< -60 else .75;light.light_color=Color("eee0c9");light.light_specular=.15;light.light_cull_mask=2;light.shadow_enabled=false;stand_lights.append(light)
  var face:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(4,.13,.40);face.mesh=box;face.position=at;face.layers=2;face.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  var material:=StandardMaterial3D.new();material.albedo_color=light.light_color;material.emission_enabled=true;material.emission=light.light_color;material.emission_energy_multiplier=2.0;face.material_override=material;add_child(face);stand_faces.append(face)
func apply(night:bool,quality:int,shadows:bool=true)->void:
 fixtures.visible=night
 sky_material.set_shader_parameter("night",night)
 var sun:DirectionalLight3D=game.get_node("MatchSun")
 sky_material.set_shader_parameter("sun_direction",sun.global_basis.z.normalized())
 for i in lamps.size():
  var lamp:SpotLight3D=lamps[i]
  var bank_energy:float=3.8 if i<2 else 3.3
  lamp.light_energy=(bank_energy if game.field_half_width>=22 else bank_energy*.67) if night else 0.0
  lamp.shadow_enabled=night and shadows and quality>0 and i==0
  lamp.shadow_opacity=.72;lamp.shadow_bias=.025;lamp.shadow_normal_bias=.35
 for i in stand_lights.size():
  var enabled:bool=quality>0 or i<4
  stand_lights[i].visible=enabled
  stand_lights[i].light_energy=(9.0 if i in [0,2] else 8.0 if i==4 else 2.8) if night else .30
  stand_faces[i].visible=enabled and night
