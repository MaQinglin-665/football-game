extends "res://tests/integration_checks.gd"
## Native GPU evidence from the unchanged host motor and synthetic engine keys.
## The comparison shadow is visual only: old 0.6.3 motion on the same C mesh.
class PoseSampler extends Node:
	var driver
	func _physics_process(delta: float) -> void:
		driver.sample_frame(delta)

var shadow: Node3D
var observer: Camera3D
var caption: Label
var phase_label := "setup"
var motion_rows: Array[Dictionary] = []
var image_files: Array[String] = []
var phase_summaries: Dictionary = {}
var sampler: Node

func _initialize() -> void:
	AudioServer.set_bus_mute(0,true)
	super._initialize()

func bone_metrics(actor: Node3D) -> Dictionary:
	var sk: Skeleton3D = actor.skeleton
	var torso: Vector3 = sk.get_bone_global_pose(sk.find_bone("chest")).origin-sk.get_bone_global_pose(sk.find_bone("hips")).origin
	var arm: Vector3 = sk.get_bone_global_pose(sk.find_bone("forearm.L")).origin-sk.get_bone_global_pose(sk.find_bone("upper_arm.L")).origin
	var length_error := 0.0
	for side in ["L","R"]:
		var thigh: Vector3 = sk.get_bone_global_pose(sk.find_bone("thigh."+side)).origin
		var shin: Vector3 = sk.get_bone_global_pose(sk.find_bone("shin."+side)).origin
		var foot: Vector3 = sk.get_bone_global_pose(sk.find_bone("foot."+side)).origin
		length_error=maxf(length_error,absf(thigh.distance_to(shin)-sk.get_bone_rest(sk.find_bone("shin."+side)).origin.length()))
		length_error=maxf(length_error,absf(shin.distance_to(foot)-sk.get_bone_rest(sk.find_bone("foot."+side)).origin.length()))
	return {"lean_deg":rad_to_deg(atan2(-torso.z,torso.y)),"bank_deg":rad_to_deg(atan2(torso.x,torso.y)),"arm_deg":rad_to_deg(atan2(arm.z,-arm.y)),"leg_length_error_m":length_error}

func sample_frame(delta: float) -> void:
	# This test's hidden window cannot supply desktop focus. Only its context is
	# kept focused; all motion still comes from engine input and the swept World.
	game.input_bridge.focused=true
	if not is_instance_valid(shadow): return
	var p: Node3D=game.player
	shadow.global_position=p.global_position+Vector3(1.1,0,0)
	shadow.update_pose(delta,{"velocity":p.velocity,"forward":p.body_facing,"grounded":p.position.y<.025,"locomotion":p.locomotion})
	if phase_label=="setup": return
	var row := {"phase":phase_label,"speed_mps":Vector2(p.velocity.x,p.velocity.z).length(),"velocity":p.velocity,"position":p.position,"input_motion":p.semantic_motion,"locomotion":p.locomotion,"new":bone_metrics(p.avatar),"legacy_same_mesh":bone_metrics(shadow),"body":p.avatar.get_full_body_debug()}
	motion_rows.append(row)

func summarize_phase(label: String) -> Dictionary:
	var rows: Array=motion_rows.filter(func(r):return r.phase==label)
	var result := {"samples":rows.size(),"peak_speed_mps":0.0,"min_lean_deg":INF,"max_lean_deg":-INF,"min_bank_deg":INF,"max_bank_deg":-INF,"min_arm_deg":INF,"max_arm_deg":-INF,"legacy_min_arm_deg":INF,"legacy_max_arm_deg":-INF,"max_leg_error_m":0.0,"last_speed_mps":0.0}
	for row in rows:
		result.peak_speed_mps=maxf(result.peak_speed_mps,row.speed_mps)
		result.min_lean_deg=minf(result.min_lean_deg,row.new.lean_deg)
		result.max_lean_deg=maxf(result.max_lean_deg,row.new.lean_deg)
		result.min_bank_deg=minf(result.min_bank_deg,row.new.bank_deg)
		result.max_bank_deg=maxf(result.max_bank_deg,row.new.bank_deg)
		result.min_arm_deg=minf(result.min_arm_deg,row.new.arm_deg)
		result.max_arm_deg=maxf(result.max_arm_deg,row.new.arm_deg)
		result.legacy_min_arm_deg=minf(result.legacy_min_arm_deg,row.legacy_same_mesh.arm_deg)
		result.legacy_max_arm_deg=maxf(result.legacy_max_arm_deg,row.legacy_same_mesh.arm_deg)
		result.max_leg_error_m=maxf(result.max_leg_error_m,row.new.leg_length_error_m)
		result.last_speed_mps=row.speed_mps
	phase_summaries[label]=result
	return result

func snapshot(label: String,side := false) -> void:
	if not native:return
	var p: Node3D=game.player
	var midpoint: Vector3=p.global_position+Vector3(.55,0,0)
	observer.projection=Camera3D.PROJECTION_ORTHOGONAL
	observer.size=3.1
	observer.global_position=midpoint+(Vector3(4,1.12,.7) if side else Vector3(.0,1.2,-4))
	observer.look_at(midpoint+Vector3(0,.84,0))
	observer.current=true
	caption.text="0.6.4 / REAL HOST INPUT / %s / %.2f m/s\nNew motion at x0; old 0.6.3 motion at x+1.1 on the SAME C mesh\nNormal 22 actors and World; extra comparison is visual only" % [label,Vector2(p.velocity.x,p.velocity.z).length()]
	await process_frame
	await RenderingServer.frame_post_draw
	var filename: String="body_%s_%s.png"%[label,"side" if side else "front"]
	var error: Error=root.get_texture().get_image().save_png(evidence.path_join(filename))
	check("native image "+filename,error==OK)
	image_files.append(filename)

func segment(label: String,count: int,capture_at := -1) -> Dictionary:
	phase_label=label
	for i in count:
		await ticks(1)
		if i==capture_at:await snapshot(label)
	return summarize_phase(label)

func run() -> void:
	if not native:
		print("NATIVE_RENDER_REQUIRED")
		quit(2)
		return
	game=load("res://scenes/match.tscn").instantiate()
	game.test_mode=true
	root.add_child(game)
	game.input_bridge.focused=true
	game.start_match(false)
	for i in 2400:
		game.input_bridge.focused=true
		await ticks(1)
		if game.is_restart_taker(game.player):break
	key(KEY_Q,true)
	await ticks(50)
	key(KEY_Q,false)
	await ticks(100)
	check("native kickoff actual contact reaches LIVE",game.phase==game.Phase.PLAY and game.stats.passes==1)
	fixture()
	game.player.set_semantic_movement(Vector3.ZERO,"run") # initial fixture only
	game.ball.position=Vector3(-20,.113,8)
	game.ball.previous_position=game.ball.position
	game.player.avatar.setup(0,10,false) # temporary observer visibility
	shadow=load("res://tests/legacy_body_pose.gd").new()
	game.add_child(shadow)
	shadow.setup(0,10,false)
	observer=Camera3D.new()
	observer.near=.025
	game.add_child(observer)
	var canvas:=CanvasLayer.new()
	root.add_child(canvas)
	caption=Label.new()
	caption.position=Vector2(14,12)
	caption.add_theme_font_size_override("font_size",16)
	canvas.add_child(caption)
	sampler=PoseSampler.new()
	sampler.driver=self
	sampler.process_physics_priority=60
	game.add_child(sampler)
	check("22 host avatars contain motion layer",game.players.size()==22 and game.players.all(func(a):return a.avatar.has_method("get_full_body_debug")))
	check("C shape retains 32 bones and eight meshes",game.player.avatar.skeleton.get_bone_count()==32 and game.player.avatar.mesh_nodes.size()==8)
	key(KEY_CTRL,true)
	key(KEY_W,true)
	var walk:Dictionary=await segment("walk",180,100)
	key(KEY_CTRL,false)
	key(KEY_SHIFT,true)
	var run_stats:Dictionary=await segment("run",180,100)
	await snapshot("run",true)
	key(KEY_D,true)
	var right:Dictionary=await segment("right_turn",75,12)
	key(KEY_D,false)
	await segment("straight",45)
	key(KEY_A,true)
	var left:Dictionary=await segment("left_turn",75,12)
	key(KEY_A,false)
	await segment("straight_again",45)
	release_inputs()
	var brake:Dictionary=await segment("brake",45,8)
	var stop:Dictionary=await segment("stop",180,140)
	check("real run speed exceeds real walk",run_stats.peak_speed_mps>walk.peak_speed_mps+.3,{"walk":walk.peak_speed_mps,"run":run_stats.peak_speed_mps})
	check("run has greater arm swing than legacy same mesh",run_stats.max_arm_deg-run_stats.min_arm_deg>run_stats.legacy_max_arm_deg-run_stats.legacy_min_arm_deg+5,run_stats)
	check("run torso visibly leans forward",run_stats.max_lean_deg>8,run_stats)
	check("right and left actual motion bank both ways",right.max_bank_deg>1 and left.min_bank_deg < -1,{"right":right,"left":left})
	check("actual key release stops host movement",stop.last_speed_mps<.15,{"brake":brake,"stop":stop,"semantic_motion":game.player.semantic_motion})
	check("stopped body returns upright",absf(float(game.player.avatar.get_full_body_debug().lean_radians))<.025 and absf(float(game.player.avatar.get_full_body_debug().bank_radians))<.01,game.player.avatar.get_full_body_debug())
	check("leg lengths retain rigid geometry",motion_rows.all(func(r):return r.new.leg_length_error_m<.0001))
	phase_label="setup"
	game.player.avatar.setup(0,10,true)
	shadow.visible=false
	observer.current=false
	game.player.camera.current=true
	game.player.head.rotation.x=deg_to_rad(-42)
	caption.text="0.6.4 / HOST FIRST PERSON / -42 pitch / 96 FOV\nC shoulder meshes follow first-person hide contract"
	await process_frame
	await RenderingServer.frame_post_draw
	var fp_file: String="body_first_person.png"
	check("native first-person image",root.get_texture().get_image().save_png(evidence.path_join(fp_file))==OK)
	image_files.append(fp_file)
	var shoulder_hidden:bool=game.player.avatar.mesh_nodes.filter(func(m):return String(m.name) in ["RobotArm_L","RobotArm_R"]).all(func(m):return not m.visible)
	check("first-person C shoulders hidden",shoulder_hidden)
	var passed:int=checks.filter(func(c):return c.passed).size()
	var report:Dictionary={"build":"0.6.4 full body + C shape on frozen0.6.3","passed":passed,"failed":checks.size()-passed,"checks":checks,"phases":phase_summaries,"samples":motion_rows,"images":image_files,"engine":Engine.get_version_info().string,"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"driver":RenderingServer.get_current_rendering_driver_name(),"adapter":RenderingServer.get_video_adapter_name(),"scope":"Native GPU images of actual host velocity from synthetic Input.parse_input_event keyboard events. Hidden-window focus maintained in this test context only. Normal22 actors, AI and swept World enabled. Free-ball motion fixtures only after real kickoff; no assigned motion velocity after fixture. Old-motion comparison shadow is nonphysical and uses the SAME C mesh, not the old 0.6.3 model. First-person observer pitch temporary. No human keyboard/feel, sound listening, full-match or frame-rate acceptance."}
	FileAccess.open(evidence.path_join("full_body_host_motion.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("FULL_BODY_HOST_NATIVE ",passed,"/",checks.size())
	release_inputs()
	game.pause_match()
	game.shutdown_audio()
	game.queue_free()
	canvas.queue_free()
	for i in 4:await process_frame
	quit(0 if passed==checks.size() else 1)
