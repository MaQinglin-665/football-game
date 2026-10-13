extends Node
## QA-only actual EXE image comparison. No gameplay or performance authority.
const Clarity := preload("res://addons/stadium_far_clarity/far_seats.gd")
var game: Node3D
var camera: Camera3D
var evidence := ""
var ticket := ""
var checks: Array[Dictionary] = []
var captures: Array[Dictionary] = []
var film: Array[Dictionary] = []
var film_start := 0
@onready var root: Window = get_tree().root
@onready var process_frame: Signal = get_tree().process_frame

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="):evidence=arg.trim_prefix("--evidence=")
		if arg.begins_with("--exclusive-render-ticket="):ticket=arg.trim_prefix("--exclusive-render-ticket=")
	if DisplayServer.get_name()=="headless" or ticket.is_empty() or evidence.is_empty():
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(evidence.path_join("frames"))
	AudioServer.set_bus_mute(0,true)
	Engine.max_fps=60
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	call_deferred("run")

func check(label: String, ok: bool, detail: Variant = null) -> void:
	checks.append({"check":label,"passed":ok,"detail":detail})
	print("PASS " if ok else "FAIL ",label)

func lod_exclusive() -> bool:
	for node in game.stadium.find_children("Seats_*","MultiMeshInstance3D",true,false):
		var proxy: Node = node.get_parent().get_node_or_null("Far"+String(node.name))
		if proxy and node.visible and proxy.visible:return false
	return true

func place(at: Vector3, target: Vector3) -> void:
	camera.global_position=at
	camera.look_at(target,Vector3.UP)
	game.stadium.update_detail_for_camera(camera.global_position)

func snapshot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var file := tag+".png"
	var result := root.get_texture().get_image().save_png(evidence.path_join(file))
	captures.append({"file":file,"result":result,"size":root.size,"camera":camera.global_transform,"fov":camera.fov,"msaa":root.msaa_3d,"far_enabled":game.stadium.get_meta("far_clarity_enabled"),"lod":game.stadium.get_detail_stats()})

func still_pair(label: String, at: Vector3, target: Vector3) -> void:
	for enabled in [false,true]:
		Clarity.set_enabled(game.stadium,enabled)
		place(at,target)
		for _i in 8:await process_frame
		await snapshot(label+("_new" if enabled else "_original"))
		check(label+" exclusive LOD "+str(enabled),lod_exclusive())

func pan(enabled: bool) -> void:
	Clarity.set_enabled(game.stadium,enabled)
	var name := "new" if enabled else "original"
	place(Vector3(-30,1.65,0),Vector3(90,16,0))
	for _i in 8:await process_frame
	await snapshot(name+"_pan_start")
	var start := Time.get_ticks_usec()
	var last_capture := 0
	var middle := false
	while Time.get_ticks_usec()-start<3000000:
		var elapsed := (Time.get_ticks_usec()-start)/1000000.0
		var alpha := clampf(elapsed/3.0,0,1)
		place(Vector3(-30+4*alpha,1.65,0),Vector3(90,16,-12+24*alpha))
		await process_frame
		if elapsed>=1.5 and not middle:
			middle=true
			await snapshot(name+"_pan_middle")
		var now := Time.get_ticks_usec()
		if now-last_capture>=50000:
			last_capture=now
			await RenderingServer.frame_post_draw
			var stamp := Time.get_ticks_usec()
			var file := "frames/frame_%04d.jpg"%film.size()
			var result := root.get_texture().get_image().save_jpg(evidence.path_join(file),.98)
			film.append({"file":file,"wall_seconds":(stamp-film_start)/1000000.0,"pan_elapsed_seconds":(stamp-start)/1000000.0,"condition":name,"result":result,"camera":camera.global_transform})
	await snapshot(name+"_pan_end")
	check(name+" pan exclusive LOD",lod_exclusive())

func run() -> void:
	seed(20261003)
	game=load("res://scenes/match.tscn").instantiate()
	game.test_mode=true
	root.add_child(game)
	for _i in 3:await process_frame
	game.pause_match()
	game.set_process(false)
	game.set_physics_process(false)
	game.physics_world.set_physics_process(false)
	for actor in game.players:actor.set_physics_process(false)
	game.hud.visible=false
	camera=Camera3D.new()
	camera.fov=game.player.camera.fov
	camera.near=game.player.camera.near
	camera.far=game.player.camera.far
	root.add_child(camera)
	camera.current=true
	check("actualEXE has expected single far-only module",game.stadium.has_meta("far_clarity_state") and not game.stadium.has_meta("night_profile"))
	check("unchanged1280x720LOWAA0 and120Hz normal time",root.size==Vector2i(1280,720) and root.msaa_3d==Viewport.MSAA_DISABLED and Engine.physics_ticks_per_second==120 and is_equal_approx(Engine.time_scale,1.0))
	await still_pair("midfield_east",Vector3(0,1.65,0),Vector3(90,16,0))
	await still_pair("far_east",Vector3(-30,1.65,0),Vector3(90,16,0))
	film_start=Time.get_ticks_usec()
	await pan(false)
	await pan(true)
	check("full resolution stills saved",captures.size()==10 and captures.all(func(r):return r.result==OK))
	check("both walltime slow pans saved",film.filter(func(r):return r.condition=="original").size()>20 and film.filter(func(r):return r.condition=="new").size()>20 and film.all(func(r):return r.result==OK))
	var report := {"passed":checks.all(func(c):return c.passed),"checks":checks,"total":checks.size(),"captures":captures,"film_frames":film,"geometry":game.stadium.get_meta("far_clarity_report"),"gpu":RenderingServer.get_video_adapter_name(),"resolution":root.size,"physics_hz":Engine.physics_ticks_per_second,"time_scale":Engine.time_scale,"ticket":ticket,"scope":"Actual exported EXE scene at eye-height1.65m with original player camera lens. Paused deterministic scene for exact original-vs-new far proxy toggles; normal time scale, wall-timed3sec slow camera translation/pan each. Near/mid seat LOD/lighting/AA unchanged. Image readbacks and60fps QA cap are not gameplay performance proof; visual human review required separately."}
	FileAccess.open(evidence.path_join("native_far_011.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("NATIVE_FAR_DONE valid=",report.passed," checks=",checks.size()," frames=",film.size())
	game.shutdown_audio()
	game.queue_free()
	camera.queue_free()
	for _i in 4:await process_frame
	get_tree().quit(0 if report.passed else 1)
