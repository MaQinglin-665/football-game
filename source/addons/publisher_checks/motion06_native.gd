extends Node
## QA only: normal six-actor 3v3, real keyboard input, readonly pose/contact log.
## Copy to the publisher's isolated source. Never install as a normal entry hook.
class AuditTick:
	extends Node
	var runner:Node
	func _physics_process(delta:float)->void:runner.call("sample_tick",delta)

const STAGES:=[
	{"name":"idle","ticks":24,"keys":[]},
	{"name":"low_forward","ticks":240,"keys":[KEY_CTRL,KEY_W]},
	{"name":"low_inside_left","ticks":120,"keys":[KEY_CTRL,KEY_W,KEY_A]},
	{"name":"low_inside_outside_right","ticks":120,"keys":[KEY_CTRL,KEY_W,KEY_D]},
	{"name":"low_left","ticks":96,"keys":[KEY_CTRL,KEY_A]},
	{"name":"low_right","ticks":96,"keys":[KEY_CTRL,KEY_D]},
	{"name":"release_roll","ticks":120,"keys":[]},
	{"name":"ordinary_run_negative_control","ticks":180,"keys":[KEY_W]},
	{"name":"shift_negative_control","ticks":120,"keys":[KEY_SHIFT,KEY_W]},
	{"name":"final_release","ticks":120,"keys":[]}]
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
var root: Window:
	get: return get_tree().root
var physics_frame: Signal:
	get: return get_tree().physics_frame
var process_frame: Signal:
	get: return get_tree().process_frame
var capture_busy := false
var captured_keys: Dictionary = {}
var captures: Array[Dictionary] = []
func quit(code: int) -> void: get_tree().quit(code)
func _ready()->void:
	if not "--motion06-check" in OS.get_cmdline_user_args():
		queue_free()
		return
	game = get_parent()
	game.test_mode = true
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
	if stage>=STAGES.size():return
	var actor:Node3D=game.player
	var foot:RefCounted=actor.get("foot") as RefCounted
	var model:Node3D=actor.get("avatar") as Node3D
	var pose:Dictionary=pose_snapshot()
	var action:Dictionary=model.get("_action")
	var row:Dictionary={"tick":Engine.get_physics_frames(),"slot":"after_training50","stage":STAGES[stage].name,"stage_tick":stage_tick,"keys":input_keys.duplicate(),"actor_position":actor.global_position,"actor_velocity":actor.get("velocity"),"semantic_motion":actor.get("semantic_motion"),"ball":game.ball_snapshot(),"ball_spin":game.ball.spin_rads,"free_roll_s":game.ball.dribble_free_roll_remaining,"foot_phase":foot.get("phase"),"foot_elapsed":foot.get("elapsed"),"action_sequence":foot.get("sequence"),"contact_tick":foot.get("contact_tick"),"contact_confirmed":foot.get("hit"),"touch_plan_state":(foot.get("touch_plan") as Dictionary).get("state","UNSPECIFIED"),"action_pose":action.duplicate(),"pose":pose}
	rows.append(pack(row))
	var body: Dictionary = pose.get("body_phase",{})
	var capture_key := String(action.get("surface",""))+str(action.get("contact_confirmed",false))
	if bool(body.get("bone_writes",false)) and captures.size()<4 and not capture_busy and not captured_keys.has(capture_key):
		capture_busy = true
		captured_keys[capture_key] = true
		call_deferred("capture_pose",capture_key,pack(row))
	update_overlay(pose,action)
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

func capture_pose(key: String, row: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(evidence)
	await RenderingServer.frame_post_draw
	var path := evidence.path_join("support_"+key+".png")
	var saved: bool = get_viewport().get_texture().get_image().save_png(path)==OK
	captures.append({"file":path,"saved":saved,"trigger_sample":row,"render_physics_tick":Engine.get_physics_frames()})
	capture_busy = false

func finish_demo()->void:
	DirAccess.make_dir_recursive_absolute(evidence)
	var actual: Array = contacts.filter(func(row):return row.event.get("success",false) and row.event.get("action","") in ["CLOSE","TURN","SHIELD"])
	var applied: Array = rows.filter(func(row):return row.pose.body_phase.get("bone_writes",false))
	var checks: Array = [{"check":"new support transfer actually applies","passed":not applied.is_empty(),"samples":applied.size()},{"check":"ordinary real contacts remain","passed":actual.size()>=3,"contacts":actual.size()},{"check":"actual motion screenshot saved","passed":not captures.is_empty() and captures.all(func(row):return row.saved)},{"check":"no modifier path lost","passed":rows.any(func(row):return row.stage=="shift_negative_control") and rows.any(func(row):return row.stage=="ordinary_run_negative_control")}]
	var valid: bool = checks.all(func(row):return row.passed)
	var report:Dictionary={"checks":checks,"passed":valid,"captures":captures,"header":header,"fixed_input":STAGES,"samples":rows,"contacts":contacts,"ground_steps":steps,"sample_count":rows.size(),"manual_feel":"NOT_TESTED","fps":"NOT_MEASURED"}
	var file:=FileAccess.open(evidence.path_join("%s_%s.json"%[tag,view]),FileAccess.WRITE)
	if file==null:push_error("Evidence write failed.");quit(2);return
	file.store_string(JSON.stringify(report)+"\n");file.close()
	print("MOTION06_NATIVE_DEMO_DONE samples=",rows.size()," actual_contacts=",contacts.size()," tag=",tag)
	reparent(get_tree().root)
	observer.queue_free()
	game.pause_match();game.shutdown_audio();game.queue_free()
	for i in 4:await process_frame
	quit(0 if valid else 1)
