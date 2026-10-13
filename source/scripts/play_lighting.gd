extends Node3D
# Visual-only light profile and bounded ground contact shading for the flat pitch.
var game:Node
var sky_lamps:Node3D
var level:=1
var contacts:MultiMeshInstance3D
var instances:MultiMesh
var fill:DirectionalLight3D
var rim:DirectionalLight3D
var shadows:=true
var slots:Array[Dictionary]=[]
func _ready()->void:
	name="PlayLighting"
	sky_lamps=preload("res://scripts/sky_lamps.gd").new();sky_lamps.game=game;add_child(sky_lamps)
	contacts=MultiMeshInstance3D.new();contacts.name="GroundContactShading";add_child(contacts)
	instances=MultiMesh.new();instances.transform_format=MultiMesh.TRANSFORM_3D;instances.use_colors=true
	var plane:=PlaneMesh.new();plane.size=Vector2.ONE
	var material:=ShaderMaterial.new();material.shader=preload("res://scripts/contact_ground.gdshader");plane.material=material
	instances.mesh=plane;instances.instance_count=game.players.size()*2+1;instances.visible_instance_count=0
	contacts.multimesh=instances
	contacts.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	contacts.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for actor in game.players:
		for side in ["L","R"]:slots.append({"actor":actor,"bone":actor.avatar.cached_bone_id("foot."+side)})
	fill=DirectionalLight3D.new();fill.name="OptionalSkyFill";fill.shadow_enabled=false;fill.light_specular=0.0;fill.sky_mode=DirectionalLight3D.SKY_MODE_LIGHT_ONLY;fill.visible=false;add_child(fill)
	rim=DirectionalLight3D.new();rim.name="OptionalStadiumRim";rim.shadow_enabled=false;rim.sky_mode=DirectionalLight3D.SKY_MODE_LIGHT_ONLY;rim.visible=false;add_child(rim)
func apply(profile:int,night:bool,shadow_enabled:bool,quality:int=1,shadow_level:int=1)->void:
	level=clampi(profile,0,2);shadows=shadow_enabled
	var environment:Environment=game.get_node("MatchEnvironment").environment
	var sun:DirectionalLight3D=game.get_node("MatchSun")
	var legacy:Node=game.stadium.get_node_or_null("NightFixtureRig")
	if legacy:legacy.deactivate() # No second light/cull-mask owner on F3 transitions.
	var sky:ShaderMaterial=sky_lamps.sky_material
	sky.set_shader_parameter("zenith",Color("111c30") if night else Color("739bbc"))
	sky.set_shader_parameter("horizon",Color("3c4b62") if night else Color("c7d7df"))
	sky.set_shader_parameter("ground",Color("303d38") if night else Color("71806a"))
	environment.background_mode=Environment.BG_SKY
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_sky_contribution=.80
	environment.ambient_light_color=Color("c1cede") if night else Color("dce7ed")
	environment.ambient_light_energy=.50 if night else .64
	environment.tonemap_mode=Environment.TONE_MAPPER_LINEAR;environment.tonemap_exposure=1.0
	environment.fog_enabled=false;environment.volumetric_fog_enabled=false
	environment.ssil_enabled=false;environment.sdfgi_enabled=false;environment.ssr_enabled=false
	environment.glow_enabled=false
	# 4.6 Compatibility supports radius/intensity only. Optional high tier, never a brightness fix.
	environment.ssao_enabled=level==2 and quality>=2
	environment.ssao_radius=.35;environment.ssao_intensity=.65
	sun.rotation_degrees=Vector3(-38,-32,0) if not night else Vector3(-58,-28,0)
	sun.light_cull_mask=1048575;sun.sky_mode=DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	sun.light_color=Color("fff1da") if not night else Color("b9cee6")
	sun.light_energy=1.02 if not night else .12
	sun.light_specular=.48
	sun.shadow_enabled=shadows and not night;sun.shadow_opacity=.76 if not night else .52
	sun.shadow_normal_bias=.35;sun.shadow_bias=.025
	sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance=100 if shadow_level==2 else 75
	sun.directional_shadow_split_1=.22;sun.directional_shadow_blend_splits=true;sun.shadow_blur=1.25
	RenderingServer.directional_shadow_atlas_set_size(2048 if quality==0 else 4096,true)
	# Fixed opposite sky fill lifts vertical faces, while sky lighting retains hemisphere contrast.
	fill.visible=level>0;fill.rotation_degrees=Vector3(-16,145,0)
	fill.light_color=Color("bacfe3");fill.light_energy=.18 if not night else .10;fill.light_specular=.18
	rim.visible=false # Avoid another full-field additive source.
	contacts.visible=level>0 and shadows
	sky_lamps.apply(night,mini(level,quality),shadows)
	sky.set_shader_parameter("sun_color",sun.light_color)
	environment.reflected_light_source=Environment.REFLECTION_SOURCE_SKY
	game.get_node("MatchEnvironment").set_meta("stadium_lighting_mode","night" if night else "daylight")
	# R004: Forward+ post stack (no-op on the Compatibility fallback).
	game.get_node("MatchEnvironment").set_meta("forward_plus_fx",ForwardPlusFx.apply(environment,game.get_viewport(),["low","balanced","high"][clampi(quality,0,2)],level>0))
func _process(_delta:float)->void:
	if level==0 or not shadows or not is_instance_valid(game.player):return
	var used:=0
	var active_camera:Camera3D=get_viewport().get_camera_3d()
	var eye:Vector3=active_camera.global_position if is_instance_valid(active_camera) else game.player.camera.global_position
	# Read completed bones only, never request another pose/contact solve.
	for slot in slots:
		var actor:Node3D=slot.actor
		if not actor.visible or actor==game.player or actor.position.distance_squared_to(eye)>900:continue
		var sk:Skeleton3D=actor.avatar.skeleton
		var pose:Transform3D=sk.global_transform*sk.get_bone_global_pose(int(slot.bone))
		pose.origin+=actor.get_global_transform_interpolated().origin-actor.global_position
		var height:float=maxf(0,pose.origin.y-.10)
		if height>.40:continue
		var at:Vector3=pose.origin+pose.basis*Vector3(0,0,-.08)
		if absf(at.x)>game.field_half_width+1 or absf(at.z)>game.field_half_length+1:continue
		var forward:Vector3=-pose.basis.z;forward.y=0
		var basis:Basis=Basis(Vector3.UP,atan2(-forward.x,-forward.z)).scaled(Vector3(.28+height*.2,1,.43+height*.2))
		instances.set_instance_transform(used,Transform3D(basis,Vector3(at.x,.017,at.z)))
		instances.set_instance_color(used,Color(1,1,1,.56*(1-height/.40)));used+=1
	if is_instance_valid(game.ball) and game.ball.position.y<2.0:
		var height:float=maxf(0,game.ball.position.y-game.ball.radius)
		var size:float=.28+height*.12
		var shown_ball:Vector3=game.ball.get_global_transform_interpolated().origin
		instances.set_instance_transform(used,Transform3D(Basis.IDENTITY.scaled(Vector3(size,1,size)),Vector3(shown_ball.x,.018,shown_ball.z)))
		instances.set_instance_color(used,Color(1,1,1,.36*(1-height/2.0)));used+=1
	instances.visible_instance_count=used
func snapshot()->Dictionary:
	return {"level":level,"contact_shading":contacts.visible,"contact_instances":instances.visible_instance_count,"shadowless_fill":fill.visible,"shadowless_rim":rim.visible,"depth_haze":game.get_node("MatchEnvironment").environment.fog_enabled,"extra_shadow_maps":1 if sky_lamps.lamps[0].shadow_enabled else 0}

