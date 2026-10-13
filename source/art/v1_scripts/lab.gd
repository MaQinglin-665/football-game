extends Node3D
const Batch=preload("res://art/v1_scripts/batch.gd")
const Athlete=preload("res://art/v1_scripts/athlete.gd")
const Ball=preload("res://art/v1_scripts/baseline_ball.gd")
var before=false
var night=false
var camera:Camera3D
var walker:CharacterBody3D
var sun:DirectionalLight3D
var environment:Environment
var sky_material:ShaderMaterial
var lamps:Array[Light3D]=[]
var fixtures:Array[MeshInstance3D]=[]
var players:Array=[]
var hud:CanvasLayer
var info:Label
var timer=0.
var samples:Array=[]
var auto_test=false
var last_usec=0
var shot_index=0
var test_phase=0
var loaded=false
var capture_busy=false
var pose_running=false
var collisions:Array=[]
var route_samples:Array=[]
var initial_source:Vector3
var look_event_count=0

func mat(hex:String,rough:float=.7,metal:float=0.)->StandardMaterial3D:
 var m=StandardMaterial3D.new();m.albedo_color=Color(hex);m.roughness=rough;m.metallic=metal;return m
func mesh_node(mesh:Mesh,m:Material,pos:Vector3=Vector3.ZERO)->MeshInstance3D:
 var n=MeshInstance3D.new();n.mesh=mesh;n.material_override=m;n.position=pos;add_child(n);return n
func box(size:Vector3,pos:Vector3,m:Material,solid:bool=false)->MeshInstance3D:
 var mesh=BoxMesh.new();mesh.size=size;var n=mesh_node(mesh,m,pos)
 if solid:solid_box(size,pos)
 return n
func solid_box(size:Vector3,pos:Vector3)->void:
 var b=StaticBody3D.new();b.position=pos;var c=CollisionShape3D.new();var shape=BoxShape3D.new();shape.size=size;c.shape=shape;b.add_child(c);add_child(b)
func label3(text:String,pos:Vector3,size:int=70,scale_factor:float=.01)->void:
 var l=Label3D.new();l.text=text;l.position=pos;l.font_size=size;l.pixel_size=scale_factor;l.modulate=Color("e8ecdf");l.outline_size=0;l.no_depth_test=false;l.shaded=true;add_child(l)

func _ready()->void:
 before="--before" in OS.get_cmdline_user_args();auto_test="--capture" in OS.get_cmdline_user_args();night="--night" in OS.get_cmdline_user_args()
 Engine.max_fps=120
 DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
 DisplayServer.window_set_title("FC Visual Lab | " + ("BASELINE" if before else "ART STUDY") + " | F4 DAY / NIGHT")
 build_environment();build_pitch();build_stand();build_goal();build_players();build_grass();build_lights();build_camera();build_hud();set_night(night);view(1)
 if auto_test:hud.visible=false
 last_usec=Time.get_ticks_usec();loaded=true
 print("LAB_READY ",JSON.stringify({"before":before,"renderer":RenderingServer.get_current_rendering_method(),"resolution":[1600,900],"cap":120,"vsync":DisplayServer.window_get_vsync_mode(),"bones":players[0].skeleton.get_bone_count(),"driver":RenderingServer.get_video_adapter_name()}))
 if "--pose-check" in OS.get_cmdline_user_args():call_deferred("pose_check")

func build_environment()->void:
 environment=Environment.new();environment.background_mode=Environment.BG_SKY
 var sky=Sky.new();sky_material=ShaderMaterial.new();sky_material.shader=load("res://art/v1_scripts/sky.gdshader");sky_material.set_shader_parameter("panorama",load("res://art/assets/sky.hdr"));sky.sky_material=sky_material;environment.sky=sky
 environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.ambient_light_color=Color("b7cbed");environment.ambient_light_energy=.48
 environment.reflected_light_source=Environment.REFLECTION_SOURCE_SKY
 environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC;environment.tonemap_exposure=1.;environment.tonemap_white=4.
 var we=WorldEnvironment.new();we.environment=environment;add_child(we)
 sun=DirectionalLight3D.new();sun.light_color=Color("fff1dc");sun.light_energy=1.05;sun.shadow_enabled=true;sun.directional_shadow_max_distance=70;sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS;sun.shadow_bias=.12;sun.shadow_normal_bias=1.2;add_child(sun)
 var im:Image=load("res://art/assets/sky.hdr").get_image();var peak=0.;var pixel=Vector2i.ZERO
 for y in range(0,im.get_height()/2,2):
  for x in range(0,im.get_width(),2):
   var c=im.get_pixel(x,y);var e=c.r+c.g+c.b
   if e>peak:peak=e;pixel=Vector2i(x,y)
 var theta=PI*(pixel.y+.5)/im.get_height();var phi=TAU*((pixel.x+.5)/im.get_width()-.5)
 initial_source=Vector3(sin(phi)*sin(theta),cos(theta),cos(phi)*sin(theta))
 var desired=Vector3(-.55,initial_source.y,.45).normalized()
 desired=Vector3(-.76*sqrt(1.-initial_source.y*initial_source.y),initial_source.y,.65*sqrt(1.-initial_source.y*initial_source.y)).normalized()
 sun.look_at(-desired)
 sky_material.set_shader_parameter("source_rotation",Basis(Vector3.UP,atan2(initial_source.x,initial_source.z)-atan2(desired.x,desired.z)))

func build_pitch()->void:
 var turf=ShaderMaterial.new();turf.shader=load("res://art/v1_scripts/turf.gdshader");turf.set_shader_parameter("grass",load("res://art/assets/sports_turf.png"));turf.set_shader_parameter("grass_normal",load("res://art/assets/sports_turf_normal.png"));turf.set_shader_parameter("before",before)
 if before:
  turf=ShaderMaterial.new();turf.shader=load("res://art/v1_scripts/baseline_with_lines.gdshader");turf.set_shader_parameter("detail_texture",load("res://art/assets/baseline_turf_data.png"));turf.set_shader_parameter("mowing_band_m",5.);turf.set_shader_parameter("pitch_half_length",25.);turf.set_shader_parameter("detail_tile_m",1.15);turf.set_shader_parameter("detail_strength",.32);turf.set_shader_parameter("normal_strength",.43);turf.set_shader_parameter("detail_fade_start_m",9.);turf.set_shader_parameter("detail_fade_end_m",23.)
 var p=PlaneMesh.new();p.size=Vector2(48,60);var ground=mesh_node(p,turf);ground.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 solid_box(Vector3(100,.4,130),Vector3(0,-.22,0))
 var base=box(Vector3(100,.10,130),Vector3(0,-.12,0),mat("303c3b"));base.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 # Runoff paved edge: separate from the field and true scale 40 x 50 m sample.
 box(Vector3(49,.10,3),Vector3(0,-.07,-31),mat("555e60"))
 for x in [-24.2,24.2]:box(Vector3(.25,.25,61),Vector3(x,.03,0),mat("c3c7bc"))

func concrete()->Material:
 var m=mat("a4aaa5",.91)
 if not before:
  m.albedo_texture=load("res://art/assets/Concrete034/Concrete034_1K-JPG_Color.jpg");m.normal_enabled=true;m.normal_texture=load("res://art/assets/Concrete034/Concrete034_1K-JPG_NormalGL.jpg");m.normal_scale=.4;m.uv1_triplanar=true;m.uv1_triplanar_sharpness=4.;m.uv1_scale=Vector3(1./1.1,1./.55,1./1.1);m.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
 return m

func seat_mesh()->Mesh:
 var b=Batch.new()
 if before:b.box(Vector3(.43,.11,.43),Vector3(0,.44,0));b.box(Vector3(.43,.42,.085),Vector3(0,.69,-.21));return b.mesh()
 # Curved concave seat bucket and back with real shell thickness, rolled leading lip.
 var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
 var profile=[[-.27,.88],[-.265,.92],[-.235,.94],[-.207,.93],[-.18,.85],[-.158,.66],[-.125,.50],[-.08,.455],[.02,.445],[.17,.46],[.225,.475],[.25,.462],[.254,.43],[.21,.421],[.08,.412],[-.09,.42],[-.16,.454],[-.197,.62],[-.22,.82],[-.27,.88]]
 for j in profile.size()-1:
  for i in 12:
   var quad:Array=[]
   for idx in [[i,j],[i+1,j],[i+1,j+1],[i,j+1]]:
    var u=float(idx[0])/12.;var r=profile[idx[1]];var x=(u-.5)*.44;var curve=pow(absf(x)/.22,3.)*.032
    quad.append(Vector3(x,r[1]+curve,r[0]+curve*.5))
   var norm=(quad[1]-quad[0]).cross(quad[2]-quad[0]).normalized()
   for k in [0,2,1,0,3,2]:st.set_normal(norm);st.set_uv(Vector2(quad[k].x,quad[k].y));st.add_vertex(quad[k])
 # Endcaps on each shell side.
 for sx in [-.22,.22]:
  for j in range(1,profile.size()-2):
   for k in [0,j,j+1]:st.set_normal(Vector3(signf(sx),0,0));st.set_uv(Vector2.ZERO);st.add_vertex(Vector3(sx,profile[k][1]+.032,profile[k][0]+.016))
 st.index();st.generate_normals();return st.commit()

func build_stand()->void:
 var cement=concrete();var dark=mat("182830",.43,.68);var stairs=Batch.new();var rails=Batch.new();var roof=Batch.new();var support=Batch.new()
 for row in 14:
  var y=.24+row*.42;var z=-33.-row*.83
  for signx in [-1.,1.]:stairs.box(Vector3(21.5,.42,.83),Vector3(signx*12.25,y-.21,z))
  # Central aisle and side access steps, twice the riser frequency.
  for half in 2:stairs.box(Vector3(3.,.21,.415),Vector3(0,y-.315+half*.21,z+.208-half*.415))
 mesh_node(stairs.mesh(),cement)
 for x in [-23.,23.]:box(Vector3(.3,6.4,12.5),Vector3(x,3.1,-38.8),cement,true)
 box(Vector3(46,1.15,.35),Vector3(0,.57,-32.2),cement,true)
 # Two genuine recessed entry tunnels, lintels and sidewalls.
 for x in [-12.,12.]:
  box(Vector3(3.3,2.5,3),Vector3(x,1.25,-46.8),mat("111a22"),true)
  box(Vector3(.35,2.8,3.3),Vector3(x-1.85,1.4,-46.8),cement);box(Vector3(.35,2.8,3.3),Vector3(x+1.85,1.4,-46.8),cement);box(Vector3(4.05,.35,3.3),Vector3(x,2.85,-46.8),cement)
 var seat=seat_mesh()
 for section in 4:
  var mm=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.use_colors=true;mm.mesh=seat;mm.instance_count=14*17
  var m=mat("ffffff",.54);m.vertex_color_use_as_albedo=true;m.cull_mode=BaseMaterial3D.CULL_DISABLED
  for row in 14:
   for column in 17:
    var x=-21.8+section*11.35+column*.51;var z=-33.1-row*.83;var y=.24+row*.42
    mm.set_instance_transform(row*17+column,Transform3D(Basis.IDENTITY,Vector3(x,y,z)))
    var lightseat=(column+row*2)%13==0 or (row in [6,7] and column in [4,5,6,7,8,9,10,11,12])
    mm.set_instance_color(row*17+column,Color("b9c8c9") if lightseat else Color("315e7d"))
  var node=MultiMeshInstance3D.new();node.multimesh=mm;node.material_override=m;node.visibility_range_end=125;add_child(node)
 if not before:
  for aisle_x in [-23.,-11.9,-1.55,1.55,11.9,23.]:
   for row in range(0,14,2):
    var at=Vector3(aisle_x,.24+row*.42,-32.65-row*.83);rails.smooth_rod(at,at+Vector3.UP*1.05,.023,8)
   rails.smooth_rod(Vector3(aisle_x,1.29,-32.65),Vector3(aisle_x,6.75,-43.44),.031,10)
  for x in range(-22,23,2):rails.smooth_rod(Vector3(x,1.1,-32.15),Vector3(x,2.,-32.15),.026,8)
  rails.smooth_rod(Vector3(-22,2.,-32.15),Vector3(22,2.,-32.15),.035,12)
  for x in [-23.,-11.5,0.,11.5,23.]:
   support.box(Vector3(.32,11.5,.32),Vector3(x,5.75,-45.))
   for z in range(-45,-30,3):
    rails.smooth_rod(Vector3(x,10.6,z),Vector3(x,11.7,z-3),.055,8);rails.smooth_rod(Vector3(x,11.7,z),Vector3(x,10.6,z-3),.055,8)
   rails.smooth_rod(Vector3(x,10.6,-30),Vector3(x,10.6,-47),.09,10);rails.smooth_rod(Vector3(x,11.7,-30),Vector3(x,11.7,-47),.09,10)
  for z in [-30.,-33.,-36.,-39.,-42.,-45.,-47.]:support.box(Vector3(47,.16,.14),Vector3(0,11.75,z))
  roof.box(Vector3(47,.16,17.4),Vector3(0,11.96,-38.5))
  roof.box(Vector3(47,.8,.20),Vector3(0,11.66,-29.8))
  mesh_node(rails.mesh(),mat("8c999f",.36,.72));mesh_node(support.mesh(),dark);mesh_node(roof.mesh(),mat("d0d7d3",.57,.3))
  label3("N O R T H   /   A T H L E T I C",Vector3(0,11.65,-29.66),64,.006)
 else:box(Vector3(47,.18,17.4),Vector3(0,11.96,-38.5),mat("7e8990"))
 # Pitchside boards create a readable horizontal scale, with original identity.
 for x in [-18.,-6.,6.,18.]:
  box(Vector3(11.5,.82,.16),Vector3(x,.45,-30.8),mat("112335",.49),true)
  label3("ATHLETIC  /  FIELD LAB" if int(x)%3==0 else "PLAY THE BEAUTIFUL GAME",Vector3(x,.47,-30.70),56,.005)
 # Secondary side terraces establish depth but have a simpler repeated structure.
 for sx in [-1.,1.]:
  for row in 5:box(Vector3(.8,.4,46),Vector3(sx*(27.+row*.9),row*.4+.2,-5),mat("344d59"))
  var mm=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.mesh=seat;mm.instance_count=240
  for row in 5:
   for col in 48:mm.set_instance_transform(row*48+col,Transform3D(Basis(Vector3.UP,-sx*PI*.5),Vector3(sx*(27.+row*.9),row*.4+.32,-24.5+col*.85)))
  var seats=MultiMeshInstance3D.new();seats.multimesh=mm;seats.material_override=mat("36576b",.7);seats.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;seats.visibility_range_end=110.;add_child(seats)
 # Keep walkable collision ramps within aisles and solid section faces.
 for sx in [-1.,1.]:solid_box(Vector3(21.5,6.,12.),Vector3(sx*12.25,2.6,-39.))

func build_goal()->void:
 var frame=Batch.new();var net=Batch.new();var feet=Batch.new()
 var z=-25.;var w=3.72;var h=2.50
 for x in [-w,w]:
  frame.smooth_rod(Vector3(x,0,z),Vector3(x,h,z),.06,24)
  frame.smooth_rod(Vector3(x,h,z),Vector3(x,2.4,z-1.7),.025,12)
  frame.smooth_rod(Vector3(x,2.4,z-1.7),Vector3(x,.04,z-2.4),.025,12)
  frame.smooth_rod(Vector3(x,.04,z),Vector3(x,.04,z-2.4),.025,12)
  feet.box(Vector3(.2,.018,.24),Vector3(x,.011,z))
  solid_box(Vector3(.12,2.5,.12),Vector3(x,1.25,z))
 frame.smooth_rod(Vector3(-w,h,z),Vector3(w,h,z),.06,32)
 frame.smooth_rod(Vector3(-w,.04,z-2.4),Vector3(w,.04,z-2.4),.025,12)
 var radius=.0025 if not before else .004
 # 12 cm square net. Each rope is true geometry; all ropes share one draw surface.
 for i in 63:
  var x=-w+i*(w*2./62.)
  for j in 12:
   var a=float(j)/12.;var b=float(j+1)/12.
   net.smooth_rod(Vector3(x,lerpf(.035,2.42,a),z-2.4+a*.7),Vector3(x,lerpf(.035,2.42,b),z-2.4+b*.7),radius,4)
  net.smooth_rod(Vector3(x,2.42,z-1.7),Vector3(x,h,z),radius,4)
 for j in 21:
  var y=.035+j*.118;var back=z-2.4+(y/2.42)*.7
  net.smooth_rod(Vector3(-w,y,back),Vector3(w,y,back),radius,4)
  for x in [-w,w]:net.smooth_rod(Vector3(x,y,z),Vector3(x,y,back),radius,4)
 for k in 15:
  var f=float(k)/14.;net.smooth_rod(Vector3(-w,lerpf(h,2.42,f),z-1.7*f),Vector3(w,lerpf(h,2.42,f),z-1.7*f),radius,4)
 for side in [-w,w]:
  for k in 19:
   var depth=k*.12;var high=h if depth<1.7 else maxf(.04,2.42*(2.4-depth)/.7)
   net.smooth_rod(Vector3(side,.04,z-depth),Vector3(side,high,z-depth),radius,4)
 mesh_node(frame.mesh(),mat("eeeede",.31,.22));mesh_node(feet.mesh(),mat("8e9897",.55,.7))
 var n=mesh_node(net.mesh(),mat("bbbfae",.9));n.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func build_players()->void:
 for i in 2:
  var a=Athlete.new();add_child(a);a.position=Vector3(-.95,0,-14) if i==0 else Vector3(2.5,0,-17.2);a.rotation.y=PI+(.10 if i==0 else -.38);a.build(Color("1666d9") if i==0 else Color("ef3f52"),7 if i==0 else 9,before);players.append(a)
  var body=StaticBody3D.new();body.position=a.position+Vector3.UP*.85;var cs=CollisionShape3D.new();var shape=CapsuleShape3D.new();shape.height=1.7;shape.radius=.29;cs.shape=shape;body.add_child(cs);add_child(body)
 var ball_mesh=Ball.make(.11) if before else preload("res://art/v1_scripts/panel_ball.gd").make(.11);var ball=mesh_node(ball_mesh,null,Vector3(.3,.112,-13.7));ball.rotation=Vector3(.3,.25,.2)
 if not before:
  for s in 2:
   var m:ShaderMaterial=ball_mesh.surface_get_material(s).duplicate();m.shader=load("res://art/v1_scripts/ball_surface.gdshader");m.set_shader_parameter("panel_color",Color("122740") if s==0 else Color("f0eee4"));ball.set_surface_override_material(s,m)
 var body=StaticBody3D.new();body.position=ball.position;var c=CollisionShape3D.new();var sphere=SphereShape3D.new();sphere.radius=.11;c.shape=sphere;body.add_child(c);add_child(body)

func build_grass()->void:
 if before:return
 var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
 for angle in [0.,PI*.5]:
  var basis=Basis(Vector3.UP,angle)
  for v in [Vector3(-.0022,0,0),Vector3(.001,.017,.004),Vector3(.0022,0,0)]:st.set_normal(Vector3(.1,.95,.25).normalized());st.set_uv(Vector2(.5,v.y/.017));st.add_vertex(basis*v)
 var blade=st.commit();var m=ShaderMaterial.new();m.shader=load("res://art/v1_scripts/blades.gdshader");var rng=RandomNumberGenerator.new();rng.seed=51273
 for x in range(-8,8,4):
  for z in range(-28,-4,4):
   var mm=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.mesh=blade;mm.instance_count=1600
   for i in mm.instance_count:mm.set_instance_transform(i,Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*rng.randf_range(.65,1.15)),Vector3(rng.randf()*4,0,rng.randf()*4)))
   var node=MultiMeshInstance3D.new();node.multimesh=mm;node.material_override=m;node.position=Vector3(x,.001,z);node.visibility_range_end=14.;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(node)

func build_lights()->void:
 for x in [-21.,21.]:
  for z in [-23.,13.]:
   var frame=Batch.new();frame.smooth_rod(Vector3(x,0,z),Vector3(x,16,z),.14,16);mesh_node(frame.mesh(),mat("667985",.34,.7))
   box(Vector3(3.4,1.15,.30),Vector3(x,16,z),mat("172b3a",.45,.6))
   var face=box(Vector3(3.1,.83,.08),Vector3(x,16,z+.19),mat("edf7ff"));fixtures.append(face)
   var light=SpotLight3D.new();light.position=Vector3(x,15.7,z+.4);light.spot_range=65;light.spot_angle=62;light.spot_attenuation=.65;light.light_color=Color("dcecff");light.shadow_enabled=(x<0&&z<0);light.light_energy=4.8 if light.shadow_enabled else 1.8;light.shadow_bias=.055;light.shadow_normal_bias=.35;add_child(light);light.look_at(Vector3(0,0,-10));lamps.append(light)
 for x in [-18.,0.,18.]:
  var l=OmniLight3D.new();l.position=Vector3(x,7.5,-34.);l.omni_range=14.;l.omni_attenuation=1.4;l.light_energy=1.2;l.light_color=Color("ffe4bb");add_child(l);lamps.append(l)
  var f=box(Vector3(1.4,.14,.22),Vector3(x,8.4,-33.),mat("fff0cc"));fixtures.append(f)
 for x in [-12.,12.]:
  var l=OmniLight3D.new();l.position=Vector3(x,2.0,-45.2);l.light_energy=1.3;l.omni_range=4.;l.light_color=Color("ffcb8d");add_child(l);lamps.append(l)

func set_night(value:bool)->void:
 night=value;sky_material.set_shader_parameter("night",night);sun.visible=not night
 environment.ambient_light_color=Color("8ca7db") if night else Color("b7cbed");environment.ambient_light_energy=.25 if night else .52
 for light in lamps:light.visible=night
 for f in fixtures:
  var m=mat("dae5ed",.4);m.emission_enabled=night;m.emission=Color("c8e2ff");m.emission_energy_multiplier=2.5;f.material_override=m

func build_camera()->void:
 walker=CharacterBody3D.new();walker.name="WalkController";add_child(walker)
 var c=CollisionShape3D.new();var shape=CapsuleShape3D.new();shape.height=1.75;shape.radius=.25;c.shape=shape;c.position.y=.875;walker.add_child(c)
 camera=Camera3D.new();walker.add_child(camera);camera.position.y=1.60;camera.fov=96;camera.near=.05;camera.far=220;camera.current=true

func build_hud()->void:
 hud=CanvasLayer.new();add_child(hud)
 var panel=ColorRect.new();panel.color=Color(.025,.045,.068,.86);panel.position=Vector2(24,24);panel.size=Vector2(344,100);hud.add_child(panel)
 var title=Label.new();title.position=Vector2(40,36);title.text="ATHLETIC / FIELD LAB";title.add_theme_font_size_override("font_size",24);hud.add_child(title)
 info=Label.new();info.position=Vector2(40,73);info.add_theme_font_size_override("font_size",16);hud.add_child(info)
 var help=Label.new();help.position=Vector2(28,842);help.text="CLICK to look   WASD walk   SHIFT run   F4 day/night   1 / 2 / 3 viewpoints   J jog pose   H hide UI   ESC release mouse";help.add_theme_font_size_override("font_size",18);hud.add_child(help)
 var cross=Label.new();cross.position=Vector2(796,444);cross.text="·";hud.add_child(cross)

func view(index:int)->void:
 var positions=[Vector3(-.3,0,-12.05),Vector3(4.6,0,-5.0),Vector3(10.5,0,5.)]
 var targets=[Vector3(-.95,1.03,-14),Vector3(0,1.8,-23.),Vector3(0,4.0,-35.)]
 walker.position=positions[index-1];walker.rotation=Vector3.ZERO;camera.rotation=Vector3.ZERO;camera.look_at(targets[index-1]);var yaw=camera.rotation.y;camera.rotation.y=0;walker.rotation.y=yaw

func _input(event:InputEvent)->void:
 if auto_test:return
 if event is InputEventMouseButton and event.pressed:
  Input.mouse_mode=Input.MOUSE_MODE_CAPTURED;print("INPUT_MOUSE_CAPTURE ",Input.mouse_mode)
 if event is InputEventMouseMotion and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:
  walker.rotation.y-=event.relative.x*.002;camera.rotation.x=clampf(camera.rotation.x-event.relative.y*.002,-1.45,1.45)
  look_event_count+=1
  if look_event_count==1:print("INPUT_LOOK_OK ",event.relative)
 if event is InputEventKey and event.pressed and not event.echo:
  match event.keycode:
   KEY_ESCAPE:Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
   KEY_F4:set_night(not night)
   KEY_1:view(1)
   KEY_2:view(2)
   KEY_3:view(3)
   KEY_H:hud.visible=not hud.visible
   KEY_J:
    pose_running=not pose_running
    players[1].player.play("Run" if pose_running else "Idle")
    print("INPUT_JOG ",pose_running)
   KEY_F12:capture("manual_"+str(Time.get_ticks_msec()))

func _physics_process(delta:float)->void:
 if not loaded:return
 var move=Vector3.ZERO
 if not auto_test:
  move=Vector3(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),0,float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W)))
  move=walker.basis*move.normalized()*(5.2 if Input.is_physical_key_pressed(KEY_SHIFT) else 2.5)
 elif test_phase==1:
  var t=timer-14.;var yaw=sin(t*.65)*.45;walker.rotation.y=yaw;camera.rotation.x=-.10+sin(t*.7)*.08
  if t>10.:walker.rotation.y+=PI
  move=walker.basis*Vector3(0,0,-1.)*(2.5 if t<5. else 5.2)
 walker.velocity.x=move.x;walker.velocity.z=move.z;walker.velocity.y-=9.8*delta;walker.move_and_slide()
 walker.position.x=clampf(walker.position.x,-23.5,23.5);walker.position.z=clampf(walker.position.z,-30.0,28.)

func _process(delta:float)->void:
 if not loaded:return
 var now=Time.get_ticks_usec();var ms=(now-last_usec)/1000.;last_usec=now
 timer+=delta
 if info:info.text=("BASELINE" if before else "ART STUDY")+"  /  "+("NIGHT" if night else "DAY")+"  /  "+str(Engine.get_frames_per_second())+" FPS"
 if not auto_test:return
 if test_phase==1 and timer>16. and not (timer>23.9 and timer<25.5):
  samples.append({"ms":ms,"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.,"physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.,"draws":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"objects":Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),"vram_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),"phase":test_phase})
 if test_phase==0 and not capture_busy and timer>2.+shot_index*1.8:
  capture_busy=true
  if shot_index<6:
   set_night(shot_index>=3);view(shot_index%3+1)
   for actor in players:actor.player.play("Idle");actor.player.seek(.25,true);actor.player.pause()
   await get_tree().process_frame
   await RenderingServer.frame_post_draw
   capture(("night_" if night else "day_")+["close","medium","wide"][shot_index%3]);shot_index+=1;capture_busy=false
  else:
   test_phase=1;timer=14.;view(1);walker.position=Vector3(3.,0,1.);players[0].player.play("Idle");players[1].player.play("Run")
 if test_phase==1:
  if night!=(timer>=24.):set_night(timer>=24.)
  if route_samples.is_empty() or timer-float(route_samples[-1].time)>.5:route_samples.append({"time":timer,"position":[walker.position.x,walker.position.y,walker.position.z],"yaw":walker.rotation.y,"night":night})
  if timer>34.:
   test_phase=2;capture("walk_end");write_report();get_tree().quit()

func capture(stem:String)->void:
 var folder=ProjectSettings.globalize_path("res://../evidence/"+("before" if before else "after"));DirAccess.make_dir_recursive_absolute(folder)
 var error=get_viewport().get_texture().get_image().save_png(folder+"/"+stem+".png");print("CAPTURE ",stem," ",error)

func write_report()->void:
 var file=FileAccess.open("res://../evidence/"+("before" if before else "after")+"/metrics.json",FileAccess.WRITE)
 file.store_string(JSON.stringify({"samples":samples,"route":route_samples,"renderer":RenderingServer.get_current_rendering_method(),"resolution":[1600,900],"fps_cap":120,"vsync":0,"cpu_frame_note":"Godot process/physics monitor timings; not CPU utilization or GPU timestamps", "gpu_frame_time":"unavailable","bone_count":players[0].skeleton.get_bone_count()},"  "))

func pose_check()->void:
 hud.visible=false;players[0].visible=false;players[1].position=Vector3(-.95,0,-14);players[1].rotation.y=PI+.1;view(1)
 for t in [.15,.35,.60]:
  players[1].player.play("Run");players[1].player.seek(t,true);players[1].player.pause()
  await get_tree().process_frame
  await RenderingServer.frame_post_draw
  capture("pose_run_"+str(int(t*100)))
 get_tree().quit()



