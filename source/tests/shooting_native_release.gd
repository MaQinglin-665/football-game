extends "res://tests/shooting_release_checks.gd"
## One coordinated native session; synthetic input in the actual22-player World.
## Exact-pose images pause the test tree only and never reset a foot/ball pose.
class FocusGuard extends Node:
	var driver
	func _physics_process(_delta: float) -> void:
		if is_instance_valid(driver.game): driver.game.input_bridge.focused=true

var saved_views: Dictionary = {}
var native_images: Array[Dictionary] = []
var observer: Camera3D
var caption: Label
var authored_body: Array[MeshInstance3D] = []

func run() -> void:
	if not native:
		quit(2)
		return
	var guard := FocusGuard.new()
	guard.driver=self
	guard.process_physics_priority=-60
	root.add_child(guard)
	await super.run()

func key(code: int,pressed: bool) -> void:
	if is_instance_valid(game):
		game.input_bridge.focused=true
		game.sync_input_context()
	super.key(code,pressed)

func mouse(button: int,pressed: bool) -> void:
	if is_instance_valid(game):
		game.input_bridge.focused=true
		game.sync_input_context()
	super.mouse(button,pressed)

func observe(count: int,tag: String) -> void:
	for i in count:
		await super.observe(1,tag)
		var f: FootballFootAction=game.player.foot
		if f.kind!="SHOT":continue
		var phase_label: String=FootballFootAction.Phase.keys()[f.phase]
		var shot_key: String=case_id+"_"+phase_label
		if saved_views.has(shot_key):continue
		if phase_label=="PREPARE" and f.elapsed<f.windup*.50:continue
		if phase_label not in ["PREPARE","CONTACT","RECOVER"]:continue
		saved_views[shot_key]=true
		await snapshot(shot_key)

func snapshot(label: String) -> void:
	paused=true
	var p:Node3D=game.player
	if observer==null:
		observer=Camera3D.new()
		observer.near=.015
		game.add_child(observer)
		var canvas:=CanvasLayer.new()
		root.add_child(canvas)
		caption=Label.new()
		caption.position=Vector2(12,136)
		caption.add_theme_font_size_override("font_size",16)
		canvas.add_child(caption)
	var old_pitch:float=p.head.rotation.x
	var mesh_visibility:Array[bool]=[]
	for mesh in p.avatar.mesh_nodes:mesh_visibility.append(mesh.visible)
	# The art adapter preserves the human first-person body. For the external
	# pose inspection use its authored kit on the same live skeleton, without
	# reviving hidden legacy mannequin parts as the old fixture did.
	if authored_body.is_empty():
		game.get_node("IndependentArt").apply_actor(p)
		for mesh in p.avatar.skeleton.get_children():
			if mesh is MeshInstance3D and str(mesh.name).begins_with("Authored_"):
				authored_body.append(mesh)
	var row:Dictionary={"label":label,"frame":frames,"shot_style":p.foot.shot_style,"phase":FootballFootAction.Phase.keys()[p.foot.phase],"hit":p.foot.hit,"ball":xyz(game.ball.position),"socket":p.foot.actual_contact.duplicate(true),"body":p.avatar.shooting_motion.debug.duplicate(true),"images":[]}
	for view in ["first_person","body_side"]:
		caption.text="0.6.5-shot / actual engine input / %s / %s\n%s strike / hit=%s / body sampled before final foot IK\nNormal22 actors/World; pause only for this exact-pose image"%[label,view,p.foot.shot_style,str(p.foot.hit)]
		if view=="first_person":
			for mesh in authored_body:mesh.visible=false
			p.head.rotation.x=deg_to_rad(-68)
			p.camera.current=true
			for i in p.avatar.mesh_nodes.size():p.avatar.mesh_nodes[i].visible=mesh_visibility[i]
		else:
			for mesh in p.avatar.mesh_nodes:mesh.visible=str(mesh.name).begins_with("Boot")
			for mesh in authored_body:mesh.visible=true
			observer.projection=Camera3D.PROJECTION_ORTHOGONAL
			observer.size=2.5
			var aim:Vector3=p.position+Vector3(0,.78,-.15)
			observer.global_position=aim+Vector3(3,.25,.95)
			observer.look_at(aim)
			observer.current=true
		await process_frame
		await RenderingServer.frame_post_draw
		var filename:String="shot_%s_%s.png"%[label,view]
		check("native image "+filename,root.get_texture().get_image().save_png(evidence.path_join(filename))==OK)
		row.images.append(filename)
	p.head.rotation.x=old_pitch
	p.camera.current=true
	for mesh in authored_body:mesh.visible=false
	for i in p.avatar.mesh_nodes.size():p.avatar.mesh_nodes[i].visible=mesh_visibility[i]
	native_images.append(row)
	write_native_report()
	paused=false

func shot_case(spec: Dictionary) -> void:
	await super.shot_case(spec)
	write_native_report()

func write_native_report() -> void:
	var report:Dictionary={"version":"0.6.5-shot","engine":Engine.get_version_info().string,"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"images":native_images,"checks":checks,"outcomes":outcomes,"master_muted":true,"scope":"Actual C mesh, full_body_01 and unified action_pose_sampled on latest integrated tree. Synthetic engine mouse/keyboard events and test-only focus guard; normal22 AI and World. Pause tree only for exact-pose pictures, camera/mesh visibility only, no avatar setup/reset. No human input, audible listening, whole-shoe sphere separation, full-match or FPS acceptance."}
	FileAccess.open(evidence.path_join("shooting_native_views.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
