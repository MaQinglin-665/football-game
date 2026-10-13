extends Node3D
# Presentation-only adapter. Existing avatars retain their skeleton, pose controller and sockets.
const Athlete=preload("res://art/v1_scripts/athlete.gd")
var game:Node
var meshes:Dictionary={}
var ready_art=false
var before=false
var turf:ShaderMaterial
var concrete:StandardMaterial3D
var sky:ShaderMaterial
var source_sun=Vector3.UP
var elapsed=0.0
var frames:Array=[]
var checked=false
var night_done=false
var near_done=false
var test=false
var capture_busy=false
var previous_us=0
var directory:String
var walking=false
var running=false
var movement_start=Vector3.ZERO
var distance_walked=0.0
var skip_frames=0
var photo_index=0
var photo_camera:Camera3D

func _ready()->void:call_deferred("install")
func install()->void:
 game=get_parent();before="--art-before" in OS.get_cmdline_user_args();test="--art-check" in OS.get_cmdline_user_args()
 directory=ProjectSettings.globalize_path("res://../evidence/"+("before" if before else "after"))
 DirAccess.make_dir_recursive_absolute(directory)
 if not before:
  for actor in game.agents:apply_actor(actor)
  game.ball.visual.mesh=preload("res://art/v1_scripts/panel_ball.gd").make(game.ball.radius)
  for i in game.ball.visual.mesh.get_surface_count():game.ball.visual.set_surface_override_material(i,null)
  for i in 2:
   var m=game.ball.visual.mesh.surface_get_material(i);m.shader=load("res://art/v1_scripts/ball_surface.gdshader")
  concrete=StandardMaterial3D.new();concrete.albedo_color=Color("a4aaa5");concrete.roughness=.91
  concrete.albedo_texture=load("res://art/assets/Concrete034/Concrete034_1K-JPG_Color.jpg");concrete.normal_enabled=true;concrete.normal_texture=load("res://art/assets/Concrete034/Concrete034_1K-JPG_NormalGL.jpg");concrete.normal_scale=.4
  concrete.uv1_triplanar=true;concrete.uv1_scale=Vector3(1./1.1,1./.55,1./1.1);concrete.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
  turf=ShaderMaterial.new();turf.shader=load("res://art/v1_scripts/turf.gdshader")
  turf.set_shader_parameter("grass",load("res://art/assets/sports_turf.png"));turf.set_shader_parameter("grass_normal",load("res://art/assets/sports_turf_normal.png"))
  sky=ShaderMaterial.new();sky.shader=load("res://art/v1_scripts/sky.gdshader");sky.set_shader_parameter("panorama",load("res://art/assets/sky.hdr"))
  var im:Image=load("res://art/assets/sky.hdr").get_image();var peak=0.;var pixel=Vector2i.ZERO
  for y in range(0,im.get_height()/2,2):
   for x in range(0,im.get_width(),2):
    var c=im.get_pixel(x,y);var energy=c.r+c.g+c.b
    if energy>peak:peak=energy;pixel=Vector2i(x,y)
  var theta=PI*(pixel.y+.5)/im.get_height();var phi=TAU*((pixel.x+.5)/im.get_width()-.5)
  source_sun=Vector3(sin(phi)*sin(theta),cos(theta),cos(phi)*sin(theta))
  game.quality_change.connect(func(_r):finish())
  finish()
 if test:
  game.settings_menu.values.quality=1;game.settings_menu.values.aa=2;game.settings_menu.values.lighting=0
  game.settings_menu.apply_values(false)
  DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED);DisplayServer.window_set_size(Vector2i(1600,900));DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);Engine.max_fps=120
  game.start_match()
  game.player.head.rot.x=deg_to_rad(-10.);game.player.head.rotation.x=game.player.head.rot.x
  movement_start=game.player.position
 ready_art=true
 if "--photos-only" in OS.get_cmdline_user_args():
  test=false
  await get_tree().create_timer(2.).timeout
  photos()
 print("ART_READY roster=",game.players.size()," ai=",game.agents.size()," before=",before," renderer=",RenderingServer.get_current_rendering_method())

func apply_actor(actor:Node)->void:
 var avatar=actor.avatar
 var builder=Athlete.new();builder.skeleton=avatar.skeleton;builder.jersey=actor.jersey
 builder.team=Color("176ae0") if actor.team==0 else Color("ed2944")
 if actor.is_goalkeeper:builder.team=Color("30c59a") if actor.team==0 else Color("d99f20")
 builder.skin=Skin.new()
 for i in avatar.skeleton.get_bone_count():builder.skin.add_bind(i,avatar.skeleton.get_bone_global_rest(i).affine_inverse())
 for m in avatar.mesh_nodes:
  if not str(m.name).begins_with("Boot"):m.visible=false
  else:
   for i in m.mesh.get_surface_count():
    var name_part=m.mesh.surface_get_material(i).resource_name
    var mat=StandardMaterial3D.new();mat.albedo_color=Color("14202e");mat.roughness=.39
    if "Sole" in name_part:mat.albedo_color=Color("dcdcd1");mat.roughness=.69
    if "Stud" in name_part:mat.albedo_color=Color("263442");mat.roughness=.5
    if "Laces" in name_part:mat.albedo_color=Color("f1eee1");mat.roughness=.88
    if "Accent" in name_part:mat.albedo_color=Color("c4f358");mat.roughness=.42
    m.set_surface_override_material(i,mat)
 if meshes.is_empty():
  builder.make_body()
  for m in avatar.skeleton.get_children():
   if m is MeshInstance3D and str(m.name).begins_with("Authored_"):meshes[str(m.name)]=m.mesh
 else:
  for key in meshes:
   var m=MeshInstance3D.new();m.name=key;m.mesh=meshes[key];m.skin=builder.skin;avatar.skeleton.add_child(m);m.skeleton=NodePath("..");m.extra_cull_margin=1.
 for m in avatar.skeleton.get_children():
  if m is MeshInstance3D and str(m.name).begins_with("Authored_"):m.material_override=builder.material(str(m.name).trim_prefix("Authored_"))
 builder.free()

func finish()->void:
 if before:return
 game.stadium.replace_material("Turf",turf)
 game.stadium.replace_material("Concrete",concrete)
 var night=int(game.settings_menu.values.lighting)==1
 var environment:Environment=game.get_node("MatchEnvironment").environment
 environment.sky.sky_material=sky;sky.set_shader_parameter("night",night)
 var sun:DirectionalLight3D=game.get_node("MatchSun")
 sky.set_shader_parameter("source_rotation",Basis(Vector3.UP,atan2(source_sun.x,source_sun.z)-atan2(sun.global_basis.z.x,sun.global_basis.z.z)))
 if not night:sun.rotation.x=-asin(source_sun.y)
 sun.shadow_normal_bias=1.0;sun.shadow_bias=.055
 environment.ambient_light_energy=.58 if not night else .42
 var banks=game.settings_menu.lighting_fx.sky_lamps.lamps
 for i in banks.size():
  banks[i].spot_angle=67.;banks[i].spot_range=125.;banks[i].spot_attenuation=.20;banks[i].light_energy=(3.8 if i<2 else 3.3) if night else 0.

func capture(label:String)->void:
 capture_busy=true
 await RenderingServer.frame_post_draw
 get_viewport().get_texture().get_image().save_png(directory+"/"+label+".png")
 capture_busy=false;skip_frames=3

func _process(delta:float)->void:
 if not ready_art or not test:return
 elapsed+=delta
 var now=Time.get_ticks_usec()
 if elapsed>8. and elapsed<28. and not capture_busy and skip_frames==0 and not (elapsed>17.8 and elapsed<20.):frames.append(float(now-previous_us)/1000.)
 previous_us=now
 skip_frames=maxi(0,skip_frames-1)
 # Exercise real input and existing player code while AI/rules continue normally.
 if elapsed>8. and elapsed<14. and not walking:
  walking=true;feed(KEY_W,true)
 if elapsed>11. and elapsed<14. and not running:
  running=true;feed(KEY_SHIFT,true)
 if elapsed>14. and walking:
  walking=false;feed(KEY_W,false);feed(KEY_SHIFT,false);distance_walked=game.player.position.distance_to(movement_start)
 if elapsed>14. and elapsed<17.:game.player.turn_view(game.player.rotation.y+delta*.5)
 if elapsed>7. and not checked:
  checked=true;capture("day_match")
 if elapsed>18. and not night_done:
  night_done=true;game.settings_menu.values.lighting=1;game.settings_menu.apply_values(false)
  DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED);DisplayServer.window_set_size(Vector2i(1600,900));DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);Engine.max_fps=120
 if elapsed>22. and not near_done:near_done=true;capture("night_match")
 if elapsed>29. and photo_index==0:
  frames.sort()
  var sum=0.
  for f in frames:sum+=f
  var report={"player_displacement_m":distance_walked,"players":game.players.size(),"agents":game.agents.size(),"frames":frames.size(),"average_fps":1000.*frames.size()/sum,"p50_ms":frames[int(frames.size()*.5)],"p95_ms":frames[int(frames.size()*.95)],"p99_ms":frames[int(frames.size()*.99)],"max_ms":frames[-1],"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"video_memory_mib":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)/1048576.,"phase":game.phase,"before":before}
  FileAccess.open(directory+"/metrics.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
  print("ART_CHECK ",JSON.stringify(report));photo_index=1;call_deferred("photos")

func feed(key:Key,pressed:bool)->void:
 var e=InputEventKey.new();e.physical_keycode=key;e.keycode=key;e.pressed=pressed
 Input.parse_input_event(e)
 # Feed the semantic adapter explicitly so the probe is independent of GUI focus.
 game.input_bridge.adapter.feed_event(e)
 game.input_bridge._input(e)

func photos()->void:
 set_process(false)
 for actor in game.players:actor.set_physics_process(false)
 game.set_physics_process(false)
 game.hud.visible=false
 photo_camera=Camera3D.new();add_child(photo_camera);photo_camera.fov=70.;photo_camera.near=.05;photo_camera.current=true
 var actor=game.agents[4]
 actor.position=Vector3(-1.,.002,-30.);actor.avatar.visual.rotation.y=PI
 photo_camera.position=Vector3(-.4,1.55,-26.6);photo_camera.look_at(Vector3(-1,1.,-30.))
 for i in 10:await get_tree().process_frame
 await capture("motion_close")
 for j in actor.avatar.skeleton.get_bone_count():actor.avatar.skeleton.reset_bone_pose(j)
 for mode in [0,1]:
  game.settings_menu.values.lighting=mode;game.settings_menu.apply_values(false)
  DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED);DisplayServer.window_set_size(Vector2i(1600,900));DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);Engine.max_fps=120
  for view in ["close","wide"]:
   photo_camera.position=Vector3(-.4,1.55,-26.6) if view=="close" else Vector3(0,5.,25.)
   photo_camera.look_at(Vector3(-1,1.,-30.) if view=="close" else Vector3(0,8.,-45.))
   for i in 15:await get_tree().process_frame
   await capture(("day_" if mode==0 else "night_")+view)
 get_tree().quit()
