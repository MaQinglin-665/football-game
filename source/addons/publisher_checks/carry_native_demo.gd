extends SceneTree
## QA only: normal six-actor 3v3, real keyboard input, readonly pose/contact log.
## Copy to the publisher's isolated source. Never install as a normal entry hook.
class AuditTick:
	extends Node
	var runner:SceneTree
	func _physics_process(delta:float)->void:runner.call("sample_tick",delta)

const STAGES:=[
    {"name":"low_023_reference","ticks":144,"keys":[KEY_CTRL,KEY_W]},
    {"name":"medium_carry","ticks":300,"keys":[KEY_W]},
    {"name":"accelerating_carry","ticks":144,"keys":[KEY_SHIFT,KEY_W]},
    {"name":"fast_carry","ticks":180,"keys":[KEY_SHIFT,KEY_W]},
    {"name":"fast_turn","ticks":144,"keys":[KEY_SHIFT,KEY_W,KEY_D]},
    {"name":"decelerating_carry","ticks":180,"keys":[KEY_W]},
    {"name":"release_brake","ticks":180,"keys":[]},
    {"name":"low_023_return","ticks":144,"keys":[KEY_CTRL,KEY_W]}]
var game:Node3D
var observer:AuditTick
var camera_view:Camera3D
var markers:Dictionary={}
var label:Label
var evidence:=""
var tag:="unlabelled"
var view:="fp"
var stage:=0
var stage_tick:=0
var input_keys:Array=[]
var rows:Array=[]
var contacts:Array=[]
var steps:Array=[]
var header:Dictionary={}
var captures:Array=[]
func _initialize()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="):evidence=arg.trim_prefix("--evidence=")
		elif arg.begins_with("--tag="):tag=arg.trim_prefix("--tag=")
		elif arg.begins_with("--view="):view=arg.trim_prefix("--view=")
	if evidence.is_empty() or DisplayServer.get_name()=="headless":
		push_error("Native QA requires a publisher-selected evidence directory and render window.")
		quit(2);return
	seed(61906)
	call_deferred("start_demo")

func start_demo()->void:
	game=(load("res://scenes/training_3v3.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene=game
	# This flag only removes QA focus-pause and mouse capture; AI stays enabled.
	game.test_mode=true
	for i in 4:await process_frame
	game.hud.menu.get_node("StartMatch").pressed.emit()
	for i in 24:await physics_frame
	header={"tag":tag,"view":view,"native":DisplayServer.get_name()!="headless","seed":61906,"physics_hz":Engine.physics_ticks_per_second,"actors":game.players.size(),"agents":game.agents.size(),"ai_enabled":game.ai_enabled,"phase":game.phase,"pose_interface_installed":game.player.avatar.has_method("get_control_support_snapshot"),"turf_extra_mps2":game.physics_profile.low_speed_roll_extra_mps2,"test_mode_effect":"focus/mouse only","scope":"Synthesized real keyboard input, normal 3v3, readonly completed-pose samples and actual hub contacts; no FPS or manual-feel claim."}
	if game.players.size()!=6 or game.agents.size()!=5 or not game.ai_enabled or Engine.physics_ticks_per_second!=120 or game.phase!=game.Phase.PLAY:
		push_error("Demo requires normal six-actor 120Hz 3v3 with AI enabled.");quit(2);return
	game.contact_hub.contact_resolved.connect(on_contact)
	if game.player.avatar.has_signal("ground_step"):game.player.avatar.ground_step.connect(on_step)
	make_overlay()
	observer=AuditTick.new()
	observer.runner=self
	observer.process_physics_priority=90 # After world20 / match40 / training50.
	root.add_child(observer)
	set_keys(STAGES[stage].keys)

func set_keys(wanted:Array)->void:
	game.input_bridge.focused=true
	game.input_bridge.sync_context()
	for code in [KEY_CTRL,KEY_SHIFT,KEY_W,KEY_A,KEY_S,KEY_D]:
		if input_keys.has(code)==wanted.has(code):continue
		var event:=InputEventKey.new()
		event.keycode=code;event.physical_keycode=code
		event.pressed=wanted.has(code);event.ctrl_pressed=wanted.has(KEY_CTRL);event.shift_pressed=wanted.has(KEY_SHIFT)
		Input.parse_input_event(event)
	Input.flush_buffered_events()
	input_keys=wanted.duplicate()

func pose_snapshot()->Dictionary:
	var model:Node3D=game.player.avatar
	if model.has_method("get_control_support_snapshot"):return model.call("get_control_support_snapshot")
	# Baseline019 fallback: identical readonly observations, without new methods.
	var sk:Skeleton3D=model.get("skeleton") as Skeleton3D
	var debug:Dictionary=model.call("get_motion_debug")
	var legs:Dictionary={}
	for side in ["L","R"]:
		var plant:Dictionary=debug.plants.get(side,{})
		var hip:Vector3=sk.to_global(sk.get_bone_global_pose(sk.find_bone("thigh."+side)).origin)
		var knee:Vector3=sk.to_global(sk.get_bone_global_pose(sk.find_bone("shin."+side)).origin)
		var ankle:Vector3=sk.to_global(sk.get_bone_global_pose(sk.find_bone("foot."+side)).origin)
		var a:float=sk.get_bone_rest(sk.find_bone("shin."+side)).origin.length()
		var b:float=sk.get_bone_rest(sk.find_bone("foot."+side)).origin.length()
		var foot:Transform3D=sk.get_bone_global_pose(sk.find_bone("foot."+side))
		var rotation:Quaternion=sk.global_basis.get_rotation_quaternion()*foot.basis.get_rotation_quaternion()
		legs[side]={"state":"RELEASING" if bool(plant.get("releasing",false)) else "PLANTED" if not plant.is_empty() else "SWING","hip":hip,"knee":knee,"ankle":ankle,"anchor":plant.get("point",Vector3.ZERO),"leg_margin_m":a+b-hip.distance_to(ankle),"knee_flexion_deg":180.0-rad_to_deg((hip-knee).angle_to(ankle-knee)),"sole_min_above_ground_m":ankle.y+model.call("_minimum_offset",side,rotation)-float(model.get("_ground_y"))}
	return {"support_phase":legs,"gait_clip":debug.base_clip,"gait_phase":debug.phase,"hips_world":sk.to_global(sk.get_bone_global_pose(sk.find_bone("hips")).origin),"source_stage":"read_only_last_completed_model_pose","body_phase":{}}

func sample_tick(_delta:float)->void:
	if not game.input_bridge.focused:
		var restore_keys:=input_keys.duplicate()
		input_keys=[]
		set_keys(restore_keys)
	if stage>=STAGES.size():return
	var actor:Node3D=game.player
	var foot:RefCounted=actor.get("foot") as RefCounted
	var model:Node3D=actor.get("avatar") as Node3D
	var pose:Dictionary=pose_snapshot()
	var action:Dictionary=model.get("_action")
	var row:Dictionary={"tick":Engine.get_physics_frames(),"slot":"after_training50","stage":STAGES[stage].name,"stage_tick":stage_tick,"keys":input_keys.duplicate(),"actor_position":actor.global_position,"actor_velocity":actor.get("velocity"),"semantic_motion":actor.get("semantic_motion"),"ball":game.ball_snapshot(),"ball_spin":game.ball.spin_rads,"free_roll_s":game.ball.dribble_free_roll_remaining,"foot_phase":foot.get("phase"),"foot_elapsed":foot.get("elapsed"),"action_sequence":foot.get("sequence"),"contact_tick":foot.get("contact_tick"),"contact_confirmed":foot.get("hit"),"touch_plan_state":(foot.get("touch_plan") as Dictionary).get("state","UNSPECIFIED"),"action_pose":action.duplicate(),"pose":pose,"carry_run":model.call("get_carry_run_debug") if model.has_method("get_carry_run_debug") else {"revision":"original024"}}
	rows.append(pack(row))
	update_overlay(pose,action)
	if stage_tick==int(STAGES[stage].ticks)/2: capture_stage(STAGES[stage].name)
	stage_tick+=1
	if stage_tick>=int(STAGES[stage].ticks):
		stage+=1;stage_tick=0
		if stage>=STAGES.size():
			observer.set_physics_process(false);set_keys([]);call_deferred("finish_demo")
		else:set_keys(STAGES[stage].keys)

func on_contact(event:Dictionary)->void:
	if event.get("actor")!=game.player:return
	contacts.append(pack({"event":event,"slot":"actual_contact_hub_before_world_step","ball":game.ball_snapshot(),"pose":pose_snapshot()}))

func on_step(event:Dictionary)->void:
	steps.append(pack({"event":event,"tick":Engine.get_physics_frames()}))

func make_overlay()->void:
	for name in ["L","R","HIP","SHOE","TARGET"]:
		var sphere:=SphereMesh.new();sphere.radius=.025;sphere.height=.05
		var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		sphere.material=material
		var node:=MeshInstance3D.new();node.mesh=sphere;root.add_child(node);markers[name]=node
	var layer:=CanvasLayer.new();root.add_child(layer)
	label=Label.new();label.position=Vector2(20,175);label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size",18);layer.add_child(label)
	if view in ["side","front"]:
		# Rendering only; original first-person eye/camera transform is untouched.
		for node in game.player.avatar.mesh_nodes:node.visible=true
		camera_view=Camera3D.new();camera_view.fov=52;root.add_child(camera_view);camera_view.make_current()

func update_overlay(pose:Dictionary,action:Dictionary)->void:
	var phases:Dictionary=pose.get("support_phase",{})
	for side in ["L","R"]:
		var leg:Dictionary=phases.get(side,{})
		var socket:Dictionary=game.player.avatar.get_foot_contact(-1 if side=="L" else 1,"SOLE")
		markers[side].position=socket.point+Vector3.UP*.018
		markers[side].mesh.material.albedo_color=Color.GREEN if leg.get("state")=="PLANTED" else Color.YELLOW if leg.get("state")=="RELEASING" else Color.RED
	markers.HIP.position=Vector3(pose.hips_world.x,game.player.position.y+.02,pose.hips_world.z)
	markers.HIP.mesh.material.albedo_color=Color.CYAN # Hip projection, not mass COM.
	markers.TARGET.visible=action.get("world_target") is Vector3
	markers.SHOE.visible=markers.TARGET.visible
	if markers.TARGET.visible:
		markers.TARGET.position=action.world_target;markers.TARGET.mesh.material.albedo_color=Color.MAGENTA
		markers.SHOE.position=game.player.avatar.get_foot_contact(int(action.get("side",1)),String(action.get("surface","INSIDE"))).point
		markers.SHOE.mesh.material.albedo_color=Color.BLUE
	label.text="%s / %s  tick %s\nL %s   R %s   CYAN = HIP PROJECTION\n%s %s %s   hit %s   ball %.2fm/s"%[tag,STAGES[stage].name,Engine.get_physics_frames(),phases.get("L",{}).get("state","?"),phases.get("R",{}).get("state","?"),action.get("kind",""),action.get("surface",""),action.get("phase","IDLE"),action.get("contact_confirmed",false),game.ball.velocity.length()]
	var running:Dictionary=game.player.avatar.call("get_carry_run_debug") if game.player.avatar.has_method("get_carry_run_debug") else {}
	label.text+="\nRUN07 weight %.2f  applied %s  pitch %.1fdeg  sprint %.2f  drive %.2f  brake %.2f"%[float(running.get("weight",0)),running.get("bone_writes",false),rad_to_deg(float(running.get("added_pitch_rad",0))),float(running.get("jog_sprint_blend",0)),float(running.get("acceleration_drive",0)),float(running.get("braking",0))]
	if is_instance_valid(camera_view):
		var facing:Vector3=game.player.body_facing
		var right:=Vector3(-facing.z,0,facing.x)
		camera_view.position=game.player.global_position+Vector3.UP*1.10+(right*2.8+facing*.8 if view=="side" else facing*2.8)
		camera_view.look_at(game.player.global_position+Vector3.UP*.85,Vector3.UP)

func pack(value:Variant)->Variant:
	if value is Vector3:return [value.x,value.y,value.z]
	if value is Quaternion:return [value.x,value.y,value.z,value.w]
	if value is Node:return str(value.get_path())
	if value is Dictionary:
		var result:Dictionary={}
		for key in value:result[str(key)]=pack(value[key])
		return result
	if value is Array:
		var result:Array=[]
		for item in value:result.append(pack(item))
		return result
	return value

func finish_demo()->void:
	DirAccess.make_dir_recursive_absolute(evidence)
	var report:Dictionary={"header":header,"fixed_input":STAGES,"samples":rows,"contacts":contacts,"ground_steps":steps,"captures":captures,"sample_count":rows.size(),"manual_feel":"NOT_TESTED","fps":"NOT_MEASURED"}
	var file:=FileAccess.open(evidence.path_join("%s_%s.json"%[tag,view]),FileAccess.WRITE)
	if file==null:push_error("Evidence write failed.");quit(2);return
	file.store_string(JSON.stringify(report)+"\n");file.close()
	print("CARRY07_NATIVE_DEMO_DONE samples=",rows.size()," actual_contacts=",contacts.size()," tag=",tag)
	game.pause_match();game.shutdown_audio();game.queue_free()
	for i in 4:await process_frame
	quit(0)

func capture_stage(name:String)->void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(evidence)
	var path:=evidence.path_join(tag+"_"+name+".png")
	if root.get_texture().get_image().save_png(path)==OK:captures.append(path)
