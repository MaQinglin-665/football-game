extends Node3D
# Original architectural study from public visual references, not a surveyed replica.
const Batch=preload("res://addons/modern_stadium/geometry_batch.gd")
var crowd_count=0
var crowd_lods:Array=[]
var crowd_lod_elapsed:float=0.0
var last_lod_eye=Vector3(INF,INF,INF)
var roof_lights:Array[Light3D]=[]
func material(hex:String,rough:float=.8)->StandardMaterial3D:
 var m=StandardMaterial3D.new();m.albedo_color=Color(hex);m.roughness=rough;return m
func node_mesh(label:String,b,mat:Material,layer:int=4)->MeshInstance3D:
 var n=MeshInstance3D.new();n.name=label;n.mesh=b.mesh(mat);n.layers=layer;n.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(n);return n
func outline(rx:float,rz:float,a:float,y:float)->Vector3:
 return Vector3(rx*signf(cos(a))*sqrt(absf(cos(a))),y,rz*signf(sin(a))*sqrt(absf(sin(a))))
## Half-width of the exponent-4 superellipse used by outline() at depth zz.
static func ring_half_width(x:float,z:float,zz:float)->float:
 return x*pow(maxf(0.0,1.0-pow(absf(zz)/z,4.0)),.25)
func build(stadium:Node3D)->void:
 name="BernabeuArchitecturalStudy"
 var d=stadium.dimensions
 var h:float=3.6
 for rows in d.tier_rows:h+=rows*d.row_rise+2.25
 # Keep original supporting stands; replace the featureless canopy with steelwork.
 for n in stadium.get_node("Roof").get_children():n.visible=false
 var metal=material("8c969e",.55);metal.metallic=.05
 var panels=Batch.new();var steel=Batch.new();var dark=Batch.new()
 var x:float=d.pitch_width*.5+8.;var z:float=d.pitch_length*.5+10.
 # Closed retractable panels, a central seam and triangulated transverse trusses.
 for row in 22:
  var za:float=-z+row*(2*z/22.);var zb:float=za+2*z/22.
  # R006: clip each closed panel row to the superellipse ring opening. Full-width
  # rectangles overlapped the sloped glass ring at the four corners (double alpha ->
  # light/dark triangular patches seen from the pitch).
  var ea:float=ring_half_width(x,z,za+.06)-.15;var eb:float=ring_half_width(x,z,zb-.06)-.15
  panels.quad(Vector3(-ea,h+4.5,za+.06),Vector3(-eb,h+4.5,zb-.06),Vector3(eb,h+4.5,zb-.06),Vector3(ea,h+4.5,za+.06),Vector2(2*x,zb-za))
  steel.rod(Vector3(-x,h+4.25,za),Vector3(x,h+4.25,za),.11,6)
  steel.rod(Vector3(-x,h+2.6,za),Vector3(x,h+2.6,za),.13,6)
  for k in 20:
   var xa:float=-x+k*x*.1;var xb:float=xa+x*.1
   steel.rod(Vector3(xa,h+2.6,za),Vector3((xa+xb)*.5,h+4.25,za),.065,5)
   steel.rod(Vector3((xa+xb)*.5,h+4.25,za),Vector3(xb,h+2.6,za),.065,5)
 for xx in [-x,0.,x]:steel.rod(Vector3(xx,h+3.9,-z),Vector3(xx,h+3.9,z),.15,6)
 # Sloped outer canopy with radial double-height trusses.
 for i in 128:
  var a:float=TAU*i/128.;var b:float=TAU*(i+1)/128.
  var p=outline(x,z,a,h+2.2);var q=outline(x,z,b,h+2.2)
  var po=outline(x+63,z+63,a,h+4.2);var qo=outline(x+63,z+63,b,h+4.2)
  panels.quad(p,po,qo,q)
  if i%2==0:
   steel.rod(p-Vector3.UP*1.4,po-Vector3.UP*.5,.17,6)
   steel.rod(p,po,.12,6)
   for j in 6:
    var f:float=j/6.;var g:float=(j+1)/6.
    steel.rod(p.lerp(po,f)-Vector3.UP*lerpf(1.4,.5,f),p.lerp(po,g),.065,5)
  # Hanging halo has a visible frame and inward-facing screen surface.
  var pa=outline(x+.7,z+.7,a,h-.6);var pb=outline(x+.7,z+.7,b,h-.6)
  dark.quad(pa,pb,pb-Vector3.UP*4.2,pa-Vector3.UP*4.2)
  if i%8==0:steel.rod(pa,pa+Vector3.UP*3.,.11,6)
 var roofmat=ShaderMaterial.new();roofmat.shader=load("res://art/scripts/roof_glass.gdshader")
 node_mesh("ArtGlassRoof",panels,roofmat)
 node_mesh("RoofTrussesAndSupports",steel,metal)
 node_mesh("HaloHousing",dark,material("11161c"))
 var screen_mat=StandardMaterial3D.new();screen_mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
 var im=Image.load_from_file(ProjectSettings.globalize_path("res://art/assets/halo.png"));im.generate_mipmaps()
 screen_mat.albedo_texture=ImageTexture.create_from_image(im);screen_mat.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
 screen_mat.cull_mode=BaseMaterial3D.CULL_DISABLED
 var screen=Batch.new()
 for i in 256:
  var a:float=TAU*i/256.;var b:float=TAU*(i+1)/256.
  var p=outline(x+.55,z+.55,a,h-.75);var q=outline(x+.55,z+.55,b,h-.75)
  var off:int=screen.uvs.size()
  screen.quad(p,q,q-Vector3.UP*3.8,p-Vector3.UP*3.8)
  var u0:float=i/256.*8.;var u1:float=(i+1)/256.*8.
  screen.uvs[off]=Vector2(u0,0);screen.uvs[off+1]=Vector2(u1,0);screen.uvs[off+2]=Vector2(u1,1);screen.uvs[off+3]=Vector2(u0,1)
 node_mesh("Continuous360Screen",screen,screen_mat)
 # Real fixture housings with separate lens cells instead of glowing white boxes.
 var housings=Batch.new();var lenses=Batch.new()
 for i in 48:
  var a:float=TAU*i/48.;var at=outline(x+2.,z+2.,a,h-5.3)
  var basis=Basis.looking_at((Vector3(0,0,0)-at).normalized(),Vector3.UP)
  housings.box(Vector3(1.6,.7,.28),at,basis)
  for row in 2:
   for col in 6:lenses.box(Vector3(.19,.23,.025),at+basis*Vector3((col-2.5)*.245,(row-.5)*.3,-.16),basis)
 node_mesh("FloodlightCasings",housings,material("252c33",.42))
 var lensmat=material("eaf1fa");lensmat.emission_enabled=true;lensmat.emission=Color("c4d2e7");lensmat.emission_energy_multiplier=2.
 node_mesh("FloodlightLensCells",lenses,lensmat)
 # Reflected roof fill, excluded from grass/players; no extra shadow maps.
 for side in [-1.,1.]:
  for end in [-1.,1.]:
   var lamp=OmniLight3D.new();add_child(lamp);lamp.position=Vector3(side*26,h-1,end*40)
   lamp.omni_range=85.;lamp.omni_attenuation=.7;lamp.light_cull_mask=4;lamp.light_energy=2.1;lamp.light_color=Color("d6e0ee");lamp.light_specular=.1;roof_lights.append(lamp)
 preload("res://art/stand_finish.gd").new().build(stadium,self)
 build_crowd(stadium)
 print("BERNABEU_READY crowd=",crowd_count," roof_closed=true")
func build_crowd(stadium:Node3D)->void:
 preload("res://art/seat_spacing.gd").repair(stadium)
 var near_models:Array=[];var far_models:Array=[];var distant_models:Array=[]
 for i in 8:
  near_models.append(preload("res://art/crowd_body.gd").new().make(i,true))
  far_models.append(preload("res://art/crowd_body.gd").new().make(i,false))
  distant_models.append(preload("res://art/crowd_body.gd").new().make(i,false,true))
 var mat=ShaderMaterial.new();mat.shader=load("res://art/crowd_surface.gdshader")
 var rng=RandomNumberGenerator.new();rng.seed=81375
 for seats in stadium.find_children("Seats_*","MultiMeshInstance3D",true,false):
  var source:MultiMesh=seats.multimesh
  var variants:Array=[]
  for v in 8:variants.append([])
  for i in source.instance_count:
   if rng.randf()<.025:continue
   var t:Transform3D=seats.get_meta("crowd_seat_transforms")[i] if seats.has_meta("crowd_seat_transforms") else source.get_instance_transform(i)
   if t.basis.y.length()<.5:continue
   # Shape variation is anchored at the seat; no vertical translation or flying shoes.
   var width:float=rng.randf_range(.91,1.025)
   t.basis=t.basis.rotated(t.basis.y,rng.randf_range(-.10,.10)).scaled(Vector3(width,1.,1.))
   t.origin+=t.basis.x*rng.randf_range(-.012,.012)
   var v:int=rng.randi_range(0,7)
   variants[v].append([t,Color(rng.randf(),rng.randf(),rng.randf(),rng.randf())])
  for v in 8:
   if variants[v].is_empty():continue
   var mm=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.use_custom_data=true;mm.mesh=far_models[v];mm.instance_count=variants[v].size()
   var bounds:AABB=AABB(variants[v][0][0].origin,Vector3.ZERO)
   for i in variants[v].size():
    mm.set_instance_transform(i,variants[v][i][0]);mm.set_instance_custom_data(i,variants[v][i][1])
    bounds=bounds.expand(variants[v][i][0].origin)
   bounds=bounds.grow(1.5);mm.custom_aabb=bounds
   crowd_count+=variants[v].size()
   var n=MultiMeshInstance3D.new();n.name="Spectators_"+str(seats.get_parent().name)+"_"+str(seats.name)+"_"+str(v);n.multimesh=mm;n.material_override=mat;n.layers=8;n.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(n)
   crowd_lods.append([n,near_models[v],far_models[v],bounds,1,distant_models[v]])
 update_crowd_detail()
func _process(delta:float)->void:
 crowd_lod_elapsed+=delta
 if crowd_lod_elapsed<.35:return
 crowd_lod_elapsed=0.;update_crowd_detail()
func update_crowd_detail()->void:
 var camera:Camera3D=get_viewport().get_camera_3d()
 if camera==null:return
 var eye:Vector3=to_local(camera.global_position)
 if eye.distance_squared_to(last_lod_eye)<.25:return
 last_lod_eye=eye
 for entry in crowd_lods:
  var bounds:AABB=entry[3]
  var distance_squared:float=eye.distance_squared_to(eye.clamp(bounds.position,bounds.end))
  var level:int=crowd_level(distance_squared,int(entry[4]))
  if level!=entry[4]:
   entry[0].multimesh.mesh=entry[1] if level==0 else entry[2] if level==1 else entry[5];entry[4]=level
static func crowd_level(distance_squared:float,previous:int)->int:
 if distance_squared<(1024. if previous==0 else 576.):return 0
 if distance_squared>(4624. if previous==2 else 6084.):return 2
 return 1
