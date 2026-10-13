extends SceneTree
## One Godot instance, four synchronized views, fixed 1x authored time.
const Baseline=preload("res://tests/arms_visual/baseline_pose.gd")
const Candidate=preload("res://scripts/integration_character_pose.gd")
const DT:=1.0/120.0
const FPS:=20
const W:=512
const H:=288
var panels:Array=[]
var frames:=0
var contact_start:Array=[]
var keys:Array=[]
var prior_velocity:=Vector3.ZERO
var evidence:=""
var max_bone_origin_delta:=0.0
var max_bone_rotation_delta:=0.0
var fp_pixel_records:Array=[]
var wall_start:=0
var ticket:=""

func _init()->void:call_deferred("run")

func stage(candidate:bool,fp:bool)->Dictionary:
	var vp:=SubViewport.new();vp.size=Vector2i(W,H);vp.own_world_3d=true;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;vp.msaa_3d=Viewport.MSAA_2X;root.add_child(vp)
	var actor:Node3D=Candidate.new() if candidate else Baseline.new();vp.add_child(actor);actor.setup(0,10,fp)
	var world:=WorldEnvironment.new();var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color("b2cbdc");env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color.WHITE;env.ambient_light_energy=.60;world.environment=env;vp.add_child(world)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-35,0);sun.light_energy=1.15;sun.shadow_enabled=true;vp.add_child(sun)
	var floor:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(180,180);floor.mesh=plane;floor.position.y=-.001
	var grid:=Image.create(64,64,false,Image.FORMAT_RGB8)
	for x in 64:
		for y in 64:grid.set_pixel(x,y,Color("83a489") if x<2 or y<2 else Color("46694e") if (x<32)==(y<32) else Color("547e5b"))
	var material:=StandardMaterial3D.new();material.albedo_texture=ImageTexture.create_from_image(grid);material.uv1_scale=Vector3(180,180,1);material.roughness=1;floor.material_override=material;vp.add_child(floor)
	var camera:=Camera3D.new();camera.current=true;camera.near=.025;camera.fov=96;vp.add_child(camera)
	var ball:=MeshInstance3D.new();var sphere:=SphereMesh.new();sphere.radius=.11;sphere.height=.22;ball.mesh=sphere;var white:=StandardMaterial3D.new();white.albedo_color=Color("f4f2ec");white.roughness=.8;ball.material_override=white;vp.add_child(ball)
	var layer:=CanvasLayer.new();vp.add_child(layer);var label:=Label.new();label.position=Vector2(12,9);label.add_theme_font_size_override("font_size",16);label.add_theme_color_override("font_color",Color.WHITE);label.add_theme_color_override("font_shadow_color",Color.BLACK);label.add_theme_constant_override("shadow_offset_x",1);label.add_theme_constant_override("shadow_offset_y",1);layer.add_child(label)
	return {"viewport":vp,"actor":actor,"camera":camera,"ball":ball,"label":label,"candidate":candidate,"fp":fp}

func config(t:float)->Dictionary:
	var speeds:=[1.4,2.8,4.4,1.7,2.8,5.0,2.8]
	var i:=mini(6,int(t/2));var yaw:=0.0
	if t>=12.3 and t<13.1:yaw=PI*.5
	var forward:=Quaternion(Vector3.UP,yaw)*Vector3.FORWARD
	return {"velocity":forward*speeds[i],"forward":forward,"grounded":true,"ground_y":0.0,"locomotion":"walk" if i==0 else "run" if i<3 else "dribble","control_tier":"FREE" if i<3 else "CLOSE" if i==3 else "CRUISE","label":["WALK","JOG","RUN","CLOSE","CRUISE","RUNNING CONTROL","90deg LEFT / RIGHT"][i],"speed":speeds[i],"yaw":yaw}

func request(panel:Dictionary,index:int,t:float,state:Dictionary)->void:
	var actor:Node3D=panel.actor
	var forward:Vector3=state.forward;var right:=Vector3(-forward.z,0,forward.x)
	panel.ball.visible=t>=6
	panel.ball.position=actor.position+forward*(.26 if t<8 else .40)+Vector3.UP*.113
	if t<6:actor.clear_foot_action();return
	var period:=.20 if t<8 else .25
	var cycle:=int(floor((t-6)/period));var elapsed:=fposmod(t-6,period)
	var side:=-1 if cycle%2==0 else 1
	var surface:="INSIDE"
	var kind:="CLOSE"
	if t>=12:
		kind="TURN";surface="INSIDE" if cycle%2==0 else "OUTSIDE"
		panel.ball.position+=right*(.10 if cycle%2==0 else -.10)
	if elapsed>=.16:actor.clear_foot_action();keys[index]="";return
	var key:=str(cycle)+surface
	if keys[index]!=key:keys[index]=key;contact_start[index]=actor.get_foot_contact(side,surface).point-actor.position
	var target:Vector3=panel.ball.position-forward*.11
	var phase:="PREPARE" if elapsed<.035 else "CONTACT" if elapsed<.105 else "RECOVER"
	var nt:=.5*elapsed/.035 if phase=="PREPARE" else .5+.15*(elapsed-.035)/.07 if phase=="CONTACT" else .65+.35*(elapsed-.105)/.055
	if phase=="PREPARE":target=(actor.position+(contact_start[index] as Vector3)).lerp(target,smoothstep(0,1,elapsed/.035))
	elif phase=="RECOVER":target=target.lerp(actor.position+(contact_start[index] as Vector3),smoothstep(0,1,(elapsed-.105)/.055))
	actor.set_foot_action({"kind":kind,"side":side,"surface":surface,"phase":phase,"normalized_time":nt,"world_target":target,"strike_target":target,"direction":forward,"sequence":cycle,"contact_confirmed":false})

func capture(t:float,state:Dictionary)->void:
	for panel in panels:
		var actor:Node3D=panel.actor;var camera:Camera3D=panel.camera
		if panel.fp:
			camera.projection=Camera3D.PROJECTION_PERSPECTIVE
			camera.position=actor.position+Quaternion(Vector3.UP,float(state.yaw))*Vector3(0,1.60,.16)
			camera.rotation=Vector3(deg_to_rad(-42),float(state.yaw),0)
		else:
			camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2.08
			camera.position=actor.position+Quaternion(Vector3.UP,float(state.yaw))*Vector3(4,1.02,-.08)
			camera.look_at(actor.position+Vector3(0,.86,0))
		panel.label.text=("0.6.10 ARMS" if panel.candidate else "0.6.9 BASELINE")+" / "+("FP" if panel.fp else "SIDE")+" / 1x\n%s  %.1fm/s  %.2fs"%[state.label,state.speed,t]
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var output:=Image.create(W*2,H*2,false,Image.FORMAT_RGB8)
	for i in panels.size():
		var rendered:Image=panels[i].viewport.get_texture().get_image()
		rendered.convert(Image.FORMAT_RGB8)
		output.blit_rect(rendered,Rect2i(0,0,W,H),Vector2i((i%2)*W,(i/2)*H))
	assert(output.save_jpg(evidence.path_join("frames/frame_%04d.jpg"%frames),.82)==OK)
	var old_fp:Image=panels[2].viewport.get_texture().get_image()
	var new_fp:Image=panels[3].viewport.get_texture().get_image()
	var center_changed:=0
	var body_changed:=0
	for x in range(W/10,9*W/10,2):
		for y in range(H/5,9*H/10,2):
			var a:=old_fp.get_pixel(x,y);var b:=new_fp.get_pixel(x,y)
			if maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))>.04:
				body_changed+=1
				if x>=int(W*.4) and x<int(W*.6) and y>=int(H*.4) and y<int(H*.6):center_changed+=1
	fp_pixel_records.append({"frame":frames,"t":t,"center_changed_samples":center_changed,"body_changed_samples":body_changed})
	for offset in [0,2]:
		var a:Skeleton3D=panels[offset].actor.skeleton
		var b:Skeleton3D=panels[offset+1].actor.skeleton
		assert(a.get_bone_count()==b.get_bone_count())
		for bone in a.get_bone_count():
			var ap:=a.get_bone_global_pose(bone);var bp:=b.get_bone_global_pose(bone)
			max_bone_origin_delta=maxf(max_bone_origin_delta,ap.origin.distance_to(bp.origin))
			max_bone_rotation_delta=maxf(max_bone_rotation_delta,ap.basis.get_rotation_quaternion().angle_to(bp.basis.get_rotation_quaternion()))
	if frames in [19,59,99,139,179,219,249,269]:output.save_png(evidence.path_join("view_%04d.png"%frames))
	frames+=1

func run()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="):evidence=arg.trim_prefix("--evidence=")
		if arg.begins_with("--exclusive-render-ticket="):ticket=arg.trim_prefix("--exclusive-render-ticket=")
	if DisplayServer.get_name()=="headless" or evidence.is_empty() or ticket.is_empty():
		print("Arms visual fixture requires native rendering and a single-renderer ticket")
		quit(2);return
	Engine.max_fps=60
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	wall_start=Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(evidence.path_join("frames"))
	for fp in [false,true]:
		for candidate in [false,true]:panels.append(stage(candidate,fp));contact_start.append(Vector3.ZERO);keys.append("")
	for tick in range(1,14*120+1):
		var t:float=tick*DT;var state:=config(t)
		state.acceleration=((state.velocity as Vector3)-prior_velocity)/DT;prior_velocity=state.velocity
		for i in panels.size():
			var actor:Node3D=panels[i].actor
			actor.position+=(state.velocity as Vector3)*DT;request(panels[i],i,t,state);actor.update_pose(DT,state)
		if tick%6==0:await capture(t,state)
		if tick%240==0:print("FP03_RENDER second ",tick/120)
	var report:={"engine":Engine.get_version_info(),"frames":frames,"fps":FPS,"duration_seconds":14,"wall_seconds":(Time.get_ticks_usec()-wall_start)/1000000.0,"GPU_used":true,"single_engine_instance":true,"reservation":ticket,"FP_camera":{"height":1.60,"z":.16,"pitch_deg":-42,"fov":96},"max_bone_origin_delta":max_bone_origin_delta,"max_bone_rotation_delta":max_bone_rotation_delta,"fp_pixel_records":fp_pixel_records,"scope":"Engine source fixture with exact release arms host vs read-only0.6.9 pose; original authored1x14sec side+FP video. Prescribed motion and foot targets, no gameplay ball physics/AI or performance acceptance. Actual exported EXE controls are separately measured."}
	FileAccess.open(evidence.path_join("native_arms_visual.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("ARMS_VISUAL_COMPLETE frames=",frames," bone_origin_delta=",max_bone_origin_delta)
	quit(0)
