extends Node3D
# Presentation-only adapter. Existing avatars retain their skeleton, pose controller and sockets.
const Athlete=preload("res://art/scripts/athlete.gd")
var grass_detail:Node3D
var architecture:Node3D
var stand_rig:Node3D
var game:Node
var meshes:Dictionary={}
var ready_art=false
var before=false
var legacy=false
var view_generation=-1
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
 if DisplayServer.get_name()=="headless":return # Rendering is verified in the separate native run.
 legacy="--v1-look" in OS.get_cmdline_user_args()
 game=get_parent();before="--art-before" in OS.get_cmdline_user_args();test="--art-check" in OS.get_cmdline_user_args()
 directory=ProjectSettings.globalize_path("res://../evidence/"+("v1_matched" if legacy else "forward" if "--forward-compare" in OS.get_cmdline_user_args() else "before" if before else "after"))
 DirAccess.make_dir_recursive_absolute(directory)
 if not before:
  for actor in game.agents:apply_actor(actor)
  game.ball.visual.mesh=preload("res://art/scripts/panel_ball.gd").make(game.ball.radius)
  for i in game.ball.visual.mesh.get_surface_count():game.ball.visual.set_surface_override_material(i,null)
  for i in 2:
   var m=game.ball.visual.mesh.surface_get_material(i);m.shader=load("res://art/scripts/ball_surface.gdshader")
  concrete=StandardMaterial3D.new();concrete.albedo_color=Color("a4aaa5");concrete.roughness=.91
  concrete.albedo_texture=load("res://art/assets/Concrete034/Concrete034_1K-JPG_Color.jpg");concrete.normal_enabled=true;concrete.normal_texture=load("res://art/assets/Concrete034/Concrete034_1K-JPG_NormalGL.jpg");concrete.normal_scale=.4
  concrete.uv1_triplanar=true;concrete.uv1_scale=Vector3(1./1.1,1./.55,1./1.1);concrete.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
  turf=ShaderMaterial.new();turf.shader=load("res://art/v1_scripts/turf.gdshader" if legacy else "res://art/scripts/turf_pbr.gdshader")
  for pair in [["grass","Color"],["grass_normal","NormalGL"],["grass_roughness","Roughness"],["grass_ao","AmbientOcclusion"]]:
   var texture_image=Image.load_from_file(ProjectSettings.globalize_path("res://art/assets/Grass005/Grass005_2K-JPG_"+pair[1]+".jpg"))
   texture_image.generate_mipmaps();turf.set_shader_parameter(pair[0],ImageTexture.create_from_image(texture_image))
  sky=ShaderMaterial.new();sky.shader=load("res://art/scripts/sky.gdshader");sky.set_shader_parameter("panorama",load("res://art/assets/sky.hdr"))
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
  game.settings_menu.values.quality=1;game.settings_menu.values.aa=2;game.settings_menu.values.lighting=1 if "--night-check" in OS.get_cmdline_user_args() else 0
  game.settings_menu.apply_values(false)
  DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED);DisplayServer.window_set_size(Vector2i(1600,900));DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);Engine.max_fps=120
  game.start_match()
  game.player.head.rot.x=deg_to_rad(-10.);game.player.head.rotation.x=game.player.head.rot.x
  movement_start=game.player.position
 if not test:
  DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED);DisplayServer.window_set_size(Vector2i(1600,900))
 grass_detail=preload("res://art/near_grass.gd").new();add_child(grass_detail)
 ready_art=true
 if "--photos-only" in OS.get_cmdline_user_args():
  test=false
  await get_tree().create_timer(2.).timeout
  photos()
 print("ART_READY roster=",game.players.size()," ai=",game.agents.size()," before=",before," renderer=",RenderingServer.get_current_rendering_method())

func apply_actor(actor:Node)->void:
 var avatar=actor.avatar
 var builder=preload("res://art/v1_scripts/athlete.gd").new() if legacy else Athlete.new();builder.skeleton=avatar.skeleton;builder.jersey=actor.jersey
 builder.team=Color("17529c") if actor.team==0 else Color("b5243e")
 if legacy:builder.team=Color("176ae0") if actor.team==0 else Color("ed2944")
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
 if legacy:
  var old=preload("res://art/v1_integration.gd").new();old.game=game;old.turf=turf;old.sky=sky;old.concrete=concrete;old.source_sun=source_sun;old.finish();old.free();return
 game.stadium.replace_material("Turf",turf)
 game.stadium.replace_material("Concrete",concrete)
 var seat_material=StandardMaterial3D.new();seat_material.albedo_color=Color("233b4b");seat_material.roughness=.92;seat_material.metallic_specular=.08
 game.stadium.replace_material("SeatNavy",seat_material);game.stadium.replace_material("SeatBlue",seat_material)
 var night=int(game.settings_menu.values.lighting)==1
 var environment:Environment=game.get_node("MatchEnvironment").environment
 environment.sky.sky_material=sky;sky.set_shader_parameter("night",night)
 var forward=RenderingServer.get_current_rendering_method()=="forward_plus"
 sky.set_shader_parameter("linear_render",forward)
 var sun:DirectionalLight3D=game.get_node("MatchSun")
 sky.set_shader_parameter("source_rotation",Basis(Vector3.UP,atan2(source_sun.x,source_sun.z)-atan2(sun.global_basis.z.x,sun.global_basis.z.z)))
 if not night:sun.rotation.x=-asin(source_sun.y)
 sun.shadow_normal_bias=1.0;sun.shadow_bias=.055
 environment.ambient_light_energy=.48 if not night else .22
 environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR if night else Environment.AMBIENT_SOURCE_SKY
 environment.ambient_light_color=Color("a4b1c0") if night else Color("dce7ed")
 environment.ambient_light_sky_contribution=.25 if night else .8
 environment.tonemap_mode=Environment.TONE_MAPPER_ACES if forward else Environment.TONE_MAPPER_FILMIC
 environment.tonemap_exposure=1.0
 environment.glow_enabled=forward;environment.glow_intensity=.45;environment.glow_strength=.65;environment.glow_bloom=.025;environment.glow_hdr_threshold=1.3
 environment.ssao_enabled=true;environment.ssao_radius=.45;environment.ssao_intensity=1.35
 get_viewport().positional_shadow_atlas_size=4096
 RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
 environment.ssil_enabled=forward;environment.ssil_radius=2.0;environment.ssil_intensity=.7
 game.settings_menu.lighting_fx.fill.light_energy=.10 if night else .13
 sun.light_energy=.015 if night else 1.02
 if night:sun.look_at_from_position(Vector3.ZERO,Vector3(.20,-.83,.52),Vector3.UP)
 if game.team_size==5 or game.small_training_pitch:
  # Keep the actual 3v3 training ground: no full-size stadium bowl/roof injection.
  sun.light_energy=.35 if night else 1.02
  environment.ambient_light_energy=.35 if night else .48
  return
 if stand_rig==null:
  stand_rig=preload("res://art/stand_lighting.gd").new();add_child(stand_rig);stand_rig.build(game.stadium)
 stand_rig.set_night(night)
 for face in stand_rig.faces:face.visible=false
 # Stand rig owns its night profile, including quality/day-night reapplication.
 if architecture==null:
  architecture=preload("res://art/bernabeu.gd").new();add_child(architecture);architecture.build(game.stadium)
 for face in game.settings_menu.lighting_fx.sky_lamps.stand_faces:face.visible=false
 for n in game.settings_menu.lighting_fx.sky_lamps.fixtures.get_children():
  if n is MeshInstance3D:n.visible=false
 var stand_lights=game.settings_menu.lighting_fx.sky_lamps.stand_lights
 for i in stand_lights.size():
  stand_lights[i].light_energy=([1.8,1.5,1.8,1.5,1.2,1.5][i] if night else .15)
  stand_lights[i].light_color=Color("c4d4e5")
  stand_lights[i].light_cull_mask=4
 var banks=game.settings_menu.lighting_fx.sky_lamps.lamps
 for i in banks.size():
  banks[i].spot_angle=67.;banks[i].spot_range=125.;banks[i].spot_attenuation=.20;banks[i].light_energy=([1.95,1.0,1.0,1.95][i]) if night else 0.
  banks[i].light_color=Color("e5edff") if i<2 else Color("fff4e4")
  banks[i].light_specular=.75;banks[i].shadow_normal_bias=.18;banks[i].shadow_bias=.015
  banks[i].shadow_enabled=night and i in [0,3];banks[i].shadow_opacity=.72
  banks[i].light_size=.45 if forward else 0.
  banks[i].shadow_blur=1.2

func capture(label:String)->void:
 capture_busy=true
 await RenderingServer.frame_post_draw
 get_viewport().get_texture().get_image().save_png(directory+"/"+label+".png")
 capture_busy=false;skip_frames=3

func _process(delta:float)->void:
 if ready_art and not test and game.phase!=game.Phase.MENU and game.match_generation!=view_generation:
  view_generation=game.match_generation;game.player.head.rot.x=deg_to_rad(-8.);game.player.head.rotation.x=game.player.head.rot.x
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
  checked=true;capture("night_walk" if "--night-check" in OS.get_cmdline_user_args() else "day_match")
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
 game.process_mode=Node.PROCESS_MODE_DISABLED
 set_process(false)
 for actor in game.players:actor.process_mode=Node.PROCESS_MODE_DISABLED
 game.set_physics_process(false);game.set_process(false)
 game.hud.visible=false
 photo_camera=Camera3D.new();add_child(photo_camera);photo_camera.fov=70.;photo_camera.near=.05;photo_camera.current=true
 var actor=game.agents[4]
 actor.position=Vector3(-1.,.002,-30.);actor.reset_physics_interpolation();actor.avatar.visual.rotation.y=PI
 game.player.visible=false
 photo_camera.position=Vector3(-.65,1.55,-27.8);photo_camera.look_at(Vector3(-1,1.,-30.))
 for i in 10:await get_tree().process_frame
 await capture("motion_close")
 for j in actor.avatar.skeleton.get_bone_count():actor.avatar.skeleton.reset_bone_pose(j)
 for mode in [0,1]:
  game.settings_menu.values.lighting=mode;game.settings_menu.apply_values(false)
  DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED);DisplayServer.window_set_size(Vector2i(1600,900));DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);Engine.max_fps=120
  for view in ["close","wide","eye","roof","turf","stand","crowd_detail","sky_debug"]:
   photo_camera.position=Vector3(-.65,1.55,-27.8) if view=="close" else Vector3(0,5.,25.)
   photo_camera.look_at(Vector3(-1,1.,-30.) if view=="close" else Vector3(0,8.,-45.))
   if view=="eye":
    photo_camera.position=Vector3(0,1.7,8);photo_camera.look_at(Vector3(-38,7,-55))
   if view=="roof":
    photo_camera.position=Vector3(0,1.7,0);photo_camera.look_at(Vector3(0,32,-55))
   if view=="turf":
    photo_camera.position=Vector3(2,1.7,-16);photo_camera.look_at(Vector3(2,0,-19.5))
   if view=="stand":
    photo_camera.position=Vector3(-37,1.7,-12);photo_camera.look_at(Vector3(-57,7,-14))
   if view=="crowd_detail":
    photo_camera.position=Vector3(-46,3.,-12);photo_camera.look_at(Vector3(-51,3.,-12))
   if view=="sky_debug":
    photo_camera.position=Vector3(0,60.,0);photo_camera.look_at(Vector3(-20,143.,-52))
   game.stadium.update_detail_for_camera(photo_camera.global_position)
   if architecture:architecture.update_crowd_detail()
   for i in 15:await get_tree().process_frame
   game.settings_menu.lighting_fx._process(0.)
   if grass_detail:grass_detail._process(0.)
   if mode==1 and view=="close":
    for bone in ["foot.L","foot.R"]:print("FOOT_DIAG ",bone," ",actor.avatar.skeleton.global_transform*actor.avatar.skeleton.get_bone_global_pose(actor.avatar.cached_bone_id(bone)))
   await get_tree().process_frame
   if mode==1 and view=="eye":
    var seats_diag=game.stadium.find_children("Seats_*","MultiMeshInstance3D",true,false)[0]
    print("SEAT_DIAG ",seats_diag.material_override," layers=",seats_diag.layers," meta=",seats_diag.get_meta("material_slot","none"))
   if "--hide-seats" in OS.get_cmdline_user_args():
    for n in game.stadium.find_children("Seats_*","MultiMeshInstance3D",true,false):n.visible=false
    for n in game.stadium.find_children("FarSeats_*","MeshInstance3D",true,false):n.visible=false
    await get_tree().process_frame
   await capture(("day_" if mode==0 else "night_")+view)
 get_tree().quit()
