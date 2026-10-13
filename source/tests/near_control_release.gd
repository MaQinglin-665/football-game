extends "res://tests/continuous_control.gd"
## Extends supplied continuous sequence with backward pull and reach evidence.
## Adds no production correction, input shortcut or extra ownership reset.
class FocusGuard extends Node:
	var driver
	func _physics_process(_delta: float) -> void:
		if is_instance_valid(driver.game): driver.game.input_bridge.focused=true

var native_images: Array[Dictionary]=[]
var recorded_stages: Dictionary={}
var observer: Camera3D
var caption: Label
var capturing := false
var start_usec := 0

func _initialize() -> void:
	AudioServer.set_bus_mute(0,true)
	start_usec=Time.get_ticks_usec()
	super._initialize()

func run() -> void:
	if native:
		var guard:=FocusGuard.new()
		guard.driver=self
		guard.process_physics_priority=-60
		root.add_child(guard)
	await super.run()

func key(code: int,pressed: bool) -> void:
	if native and is_instance_valid(game):
		game.input_bridge.focused=true
		game.sync_input_context()
	super.key(code,pressed)

func sample_tick() -> void:
	super.sample_tick()
	var avatar:Node3D=game.player.avatar
	var sk:Skeleton3D=avatar.skeleton
	var legs:Dictionary={}
	for side in ["L","R"]:
		var hip:Vector3=sk.get_bone_global_pose(sk.find_bone("thigh."+side)).origin
		var knee:Vector3=sk.get_bone_global_pose(sk.find_bone("shin."+side)).origin
		var ankle:Vector3=sk.get_bone_global_pose(sk.find_bone("foot."+side)).origin
		var upper:float=sk.get_bone_rest(sk.find_bone("shin."+side)).origin.length()
		var lower_length:float=sk.get_bone_rest(sk.find_bone("foot."+side)).origin.length()
		legs[side]={"straightness":hip.distance_to(ankle)/(upper+lower_length),"upper_error_m":absf(hip.distance_to(knee)-upper),"lower_error_m":absf(knee.distance_to(ankle)-lower_length)}
	path[-1]["legs"]=legs
	path[-1]["actual_shoe_valid"]=game.player.foot.actual_contact.get("valid",false)
	path[-1]["body_motion"]=avatar.get_full_body_debug()
	path[-1]["body_to_contact_m"]=game.flat_distance(game.player.position,game.player.foot.actual_contact.get("point",game.player.position))
	path[-1]["ball_ahead_m"] = (game.ball.position-game.player.position).dot(game.player.body_facing)

func segment(name: String,seconds: float,keys: Array) -> void:
	await super.segment(name,seconds,keys)
	if name=="final_stop" and sequence=="near30":
		await super.segment("backward_pull",1.6,[KEY_S])
		await super.segment("backward_stop",1.5,[])
		if native: await capture_contact("backward_stop_end")
		await super.segment("side_after_pull",1.5,[KEY_D])
		await super.segment("pull_recovery_stop",1.5,[])
		var backward:Dictionary=stages.filter(func(r):return r.stage=="backward_pull")[0]
		var pull_hits:Array=touch_events.filter(func(e):return e.stage=="backward_pull" and e.action=="PULL" and e.surface=="SOLE" and e.success)
		check("continuous backward uses actual sole pull and body displacement",backward.owned_fraction==1.0 and backward.actor_travel_m>.5 and pull_hits.size()>=1,{"stage":backward,"sole_contacts":pull_hits.size()})
		var stops:Array=stages.filter(func(r):return r.stage in ["backward_stop","pull_recovery_stop"])
		check("backward and following side movement settle close",stops.all(func(r):return r.owned_fraction==1.0 and r.final_gap<.55 and r.ball_final_speed<.08),stops)
		var retreat_path: Array = path.filter(func(r):return r.stage in ["backward_pull","backward_stop"])
		check("backward ball stays in front of the heels within real reach",retreat_path.all(func(r):return r.ball_ahead_m>-.05 and r.gap_m<.60),{"minimum_forward_m":retreat_path.map(func(r):return r.ball_ahead_m).min(),"maximum_gap_m":retreat_path.map(func(r):return r.gap_m).max()})
		check("continued control preserves original leg lengths",path.all(func(r):return r.legs.L.upper_error_m<.0001 and r.legs.L.lower_error_m<.0001 and r.legs.R.upper_error_m<.0001 and r.legs.R.lower_error_m<.0001))
		write_native_report()

func ticks(count: int,interval := 0,tag := "play") -> void:
	for i in count:
		await super.ticks(1,interval,tag)
		if not native or capturing or not is_instance_valid(game): continue
		if stage not in ["near_left","near_right","near_diagonal_left","near_diagonal_right","near_release_stop","backward_pull","backward_stop"] or recorded_stages.has(stage):continue
		if game.player.foot.phase!=FootballFootAction.Phase.CONTACT:continue
		var failed_stop:bool=stage=="backward_stop" and not game.player.foot.actual_contact.get("valid",false)
		if not failed_stop and (not game.player.foot.hit or not game.player.foot.actual_contact.get("valid",false)):continue
		if stage in ["near_release_stop","backward_stop"] and game.player.foot.kind not in ["SETTLE","STOP"]:continue
		recorded_stages[stage]=true
		await capture_contact(stage)

func capture_contact(name: String) -> void:
	capturing=true
	paused=true # Only freeze for exact-pose image capture; simulation resumes.
	var p:Node3D=game.player
	if observer==null:
		observer=Camera3D.new()
		observer.near=.015
		game.add_child(observer)
		var canvas:=CanvasLayer.new()
		root.add_child(canvas)
		caption=Label.new()
		caption.position=Vector2(12,140)
		caption.add_theme_font_size_override("font_size",16)
		canvas.add_child(caption)
	var old_pitch:float=p.head.rotation.x
	var record:Dictionary={"stage":name,"frame":frames,"ball":xyz(game.ball.position),"actor":xyz(p.position),"gap_m":game.flat_distance(game.ball.position,p.position),"actor_velocity":xyz(p.velocity),"foot_kind":p.foot.kind,"foot_phase":p.foot.phase,"actual_contact":p.foot.actual_contact.duplicate(true),"images":[]}
	for view in ["first_person","shoe_side"]:
		caption.text="0.6.5 / continuous real input / %s / %s\nNo state reset after acquisition; paused only for this image\nBody gap %.3fm / actual shoe valid %s"%[name,view,record.gap_m,str(record.actual_contact.get("valid",false))]
		if view=="first_person":
			p.avatar.setup(p.team,p.jersey,true)
			p.head.rotation.x=deg_to_rad(-70)
			p.camera.current=true
		else:
			p.avatar.setup(p.team,p.jersey,false)
			observer.projection=Camera3D.PROJECTION_ORTHOGONAL
			observer.size=maxf(1.25,float(record.gap_m)+.70)
			var aim:Vector3=p.position.lerp(game.ball.position,.55)+Vector3(0,.23,0)
			observer.global_position=aim+Vector3(1.5,.55,.35)
			observer.look_at(aim)
			observer.current=true
		await process_frame
		await RenderingServer.frame_post_draw
		var file:String="near_%s_%s.png"%[name,view]
		var error:Error=root.get_texture().get_image().save_png(evidence.path_join(file))
		check("native image "+file,error==OK)
		record.images.append(file)
	p.avatar.setup(p.team,p.jersey,true)
	p.head.rotation.x=old_pitch
	p.camera.current=true
	caption.text=""
	native_images.append(record)
	paused=false
	capturing=false
	write_native_report()

func write_native_report() -> void:
	var report:Dictionary={"version":"0.6.5 near-control on frozen0.6.4 full body/C shape","native":native,"images":native_images,"audio_driver":AudioServer.get_driver_name(),"test_audio_muted":true,"elapsed_wall_seconds":(Time.get_ticks_usec()-start_usec)/1000000.0,"scope":"Supplied continuous control sequence plus backward and following side movement. One LIVE/spatial fixture and true RECEIVE before the sequence. 22 physical bodies/real skeletons/World; AI decisions disabled. No actor/ball/ownership resets thereafter. Native only: hidden-window focus fixture, temporary -70-degree view and observer; tree paused solely to capture exact contact pose. Actual mesh separation requires image review, socket validity alone does not prove whole-shoe separation. No human feel, FPS, hearing or full-match acceptance."}
	if native:
		report.renderer=RenderingServer.get_current_rendering_method()
		report.adapter=RenderingServer.get_video_adapter_name()
	FileAccess.open(evidence.path_join("near_control_%s_extra.json"%label),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
