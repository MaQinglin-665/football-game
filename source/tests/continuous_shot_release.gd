extends "res://tests/integration_checks.gd"
## One initial spatial/LIVE fixture and real RECEIVE; the whole carry/charge/
## release chain thereafter uses input and the normal22-body World, no resets.
var case_id := "forward"
var stage := "receive"
var path: Array[Dictionary] = []
var events: Array[Dictionary] = []
var held_keys: Array[int] = []
var native_images: Array[Dictionary] = []
var captured: Dictionary = {}
var observer: Camera3D
var recording := false

class FocusGuard extends Node:
	var driver
	func _physics_process(_delta: float) -> void:
		if is_instance_valid(driver.game): driver.game.input_bridge.focused=true

func _initialize() -> void:
	AudioServer.set_bus_mute(0,true)
	super._initialize()

func xyz(v: Vector3) -> Array: return [v.x,v.y,v.z]

func input_keys(keys: Array) -> void:
	for code in held_keys:
		if not keys.has(code): key(code,false)
	for code in keys:
		if not held_keys.has(code): key(code,true)
	held_keys.clear()
	for code in keys: held_keys.append(code)

func record_tick() -> void:
	var p: Node3D = game.player
	var f: FootballFootAction = p.foot
	path.append({"frame":frames,"stage":stage,"ball":xyz(game.ball.position),"actor":xyz(p.position),"ball_velocity":xyz(game.ball.velocity),"actor_velocity":xyz(p.velocity),"owned":game.ball.carrier==p,"gap_m":game.flat_distance(p.position,game.ball.position),"ball_ahead_m":(game.ball.position-p.position).dot(p.body_facing),"kind":f.kind,"phase":FootballFootAction.Phase.keys()[f.phase],"elapsed":f.elapsed,"hit":f.hit,"buffer":f.buffer.get("kind",""),"charge":game.input_bridge.charge_preview.duplicate(true),"foot_valid":f.actual_contact.get("valid",false),"reach_error":f.actual_contact.get("reach_error",-1.0),"socket":xyz(f.actual_contact.get("point",Vector3.ZERO)),"socket_ball_gap":(f.actual_contact.get("point",Vector3.ZERO) as Vector3).distance_to(game.ball.position),"target":xyz(f.contact_target),"reason":f.contact_failure,"result":f.last_result,"support":p.avatar.planted_support.duplicate(true),"pose_refresh":p.avatar.get_pose_refresh_debug(),"shot_body":p.avatar.shooting_motion.debug.duplicate(true)})

func observe(count: int) -> void:
	for _i in count:
		if native: game.input_bridge.focused=true
		await ticks(1)
		record_tick()
		if not native or recording: continue
		var f: FootballFootAction=game.player.foot
		var tag := ""
		if f.kind in ["CLOSE","TURN","PULL","SETTLE"] and f.phase==FootballFootAction.Phase.CONTACT and f.hit and f.actual_contact.get("valid",false): tag="carry_"+f.kind.to_lower()
		if f.kind=="SHOT" and f.phase==FootballFootAction.Phase.PREPARE and f.elapsed>=f.windup*.55: tag="shot_windup"
		if f.kind=="SHOT" and f.hit: tag="shot_contact"
		if tag!="" and not captured.has(tag):
			captured[tag]=true
			await capture_pose(tag)

func segment(tag: String,seconds: float,keys: Array) -> void:
	stage=tag
	input_keys(keys)
	await observe(roundi(seconds*120))

func capture_pose(tag: String) -> void:
	recording=true
	paused=true
	var p:Node3D=game.player
	var old_pitch:float=p.head.rotation.x
	# Mesh visibility alone changes for the observer. Never call avatar.setup
	# here: setup resets motion/support state in the middle of a live action.
	var meshes: Array[MeshInstance3D]=[]
	var prior_visibility: Array[bool]=[]
	for node in p.avatar.find_children("*","MeshInstance3D",true,false):
		meshes.append(node)
		prior_visibility.append(node.visible)
	if observer==null:
		observer=Camera3D.new()
		observer.near=.015
		game.add_child(observer)
	var record:Dictionary={"tag":tag,"frame":frames,"snapshot":path.back().duplicate(true),"images":[]}
	for view in ["first_person","shoe_side"]:
		if view=="first_person":
			p.head.rotation.x=deg_to_rad(-70)
			p.camera.current=true
		else:
			for node in meshes: node.visible=true
			observer.projection=Camera3D.PROJECTION_ORTHOGONAL
			observer.size=1.45
			var aim:Vector3=p.position.lerp(game.ball.position,.5)+Vector3(0,.30,0)
			observer.global_position=aim+p.global_basis.x*1.6+Vector3.UP*.45+p.global_basis.z*.15
			observer.look_at(aim)
			observer.current=true
		await process_frame
		await RenderingServer.frame_post_draw
		var file:String="control_shot_%s_%s_%s.png"%[case_id,tag,view]
		var result:Error=root.get_texture().get_image().save_png(evidence.path_join(file))
		check("native image "+file,result==OK)
		record.images.append(file)
	for i in meshes.size(): meshes[i].visible=prior_visibility[i]
	p.head.rotation.x=old_pitch
	p.camera.current=true
	native_images.append(record)
	paused=false
	recording=false

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="): case_id=arg.trim_prefix("--case=")
	game=load("res://scenes/match.tscn").instantiate()
	game.test_mode=true
	root.add_child(game)
	if native:
		var guard:=FocusGuard.new()
		guard.driver=self
		guard.process_physics_priority=-60
		root.add_child(guard)
	await ticks(3)
	game.ai_enabled=false
	game.services.rules.state=game.Rules.State.LIVE
	game.services.rules.restart.clear()
	game.set_phase(game.Phase.PLAY)
	game.services.configuration.half_seconds=600.0
	game.contact_hub.contact_resolved.connect(func(e:Dictionary):
		if e.actor!=game.player: return
		events.append({"frame":frames,"stage":stage,"action":e.action,"surface":e.surface,"success":e.success,"point":xyz(e.point),"before":xyz(e.before_velocity),"after":xyz(e.after_velocity),"reason":e.get("failure_reason",""),"sequence":e.get("action_sequence",-1),"reach_error":e.get("reach_error",-1.0),"gap_m":game.flat_distance(game.ball.position,game.player.position),"support_valid":game.player.avatar.planted_support.get("valid",false),"foot_elapsed":game.player.foot.elapsed,"foot_windup":game.player.foot.windup,"foot_window":game.player.foot.window,"owned_at_callback":game.ball.carrier==game.player}))
	fixture()
	game.player.position.z=30.0
	game.ball.position=Vector3(0,.113,29.42)
	game.ball.previous_position=game.ball.position
	key(KEY_SPACE,true)
	await ticks(1)
	key(KEY_SPACE,false)
	await observe(45)
	check("initial possession comes from actual RECEIVE",game.ball.carrier==game.player and events.any(func(e):return e.action=="RECEIVE" and e.success))
	await segment("forward_carry",1.7,[KEY_W])
	if case_id in ["side","mixed"]:
		await segment("left_carry",1.2,[KEY_A])
		await segment("left_release",.5,[])
		await segment("right_carry",2.4,[KEY_D])
		await segment("right_release",.5,[])
	if case_id in ["backward","mixed"]:
		await segment("pre_back_stop",1.0,[])
		await segment("backward_pull",1.6,[KEY_S])
		await segment("backward_release",1.5,[])
	if case_id=="mixed":
		await segment("forward_after_retreat",1.7,[KEY_W])
	if case_id=="running":
		await segment("held_shift_carry",3.0,[KEY_W,KEY_SHIFT])
	var p:Node3D=game.player
	var start_sequence:int=game.input_bridge.last_sequence
	var shots_before:int=game.stats.shots
	var rejected_before:int=game.input_bridge.rejected_commands
	var trace_frame:int=Engine.get_physics_frames()
	var release_before:Dictionary={}
	stage="charge_hold"
	mouse(MOUSE_BUTTON_LEFT,true)
	await observe(42)
	var hold_shots:int=game.stats.shots-shots_before
	release_before=path.back().duplicate(true)
	stage="shoot_release"
	mouse(MOUSE_BUTTON_LEFT,false)
	# Real movement-key release is part of the uninterrupted gesture.
	input_keys([])
	await observe(90)
	var intents:Array=game.input_bridge.traces.filter(func(e):return int(e.sequence)>start_sequence and String(e.action).begins_with("shoot_"))
	var shots:Array=events.filter(func(e):return e.action=="SHOT")
	var real_shots:Array=shots.filter(func(e):return e.success)
	var charge_rows:Array=path.filter(func(r):return r.stage=="charge_hold")
	check("continuous carry retains possession through charging",charge_rows.all(func(r):return r.owned) and charge_rows.any(func(r):return not r.charge.is_empty()),release_before)
	check("holding mouse does not produce a shot",hold_shots==0)
	check("one release yields one physical shot",real_shots.size()==1 and game.stats.shots-shots_before==1,{"intents":intents,"events":shots,"rejected_delta":game.input_bridge.rejected_commands-rejected_before})
	check("shot comes from reachable shoe and grounded support",real_shots.size()==1 and real_shots.all(func(e):return e.reach_error>=0 and e.reach_error<=.035 and e.support_valid and e.foot_elapsed>=e.foot_windup and e.foot_elapsed<e.foot_windup+e.foot_window),real_shots)
	var report:Dictionary={"version":"0.6.7-control","case":case_id,"native":native,"scope":"One initial LIVE/spatial fixture; actual RECEIVE; AI decisions off with22 physical bodies. No actor/ball/velocity/ownership reset during forward/side/backward/run carry, key releases, charging and shooting. Native only: hidden-window focus fixture; tree pauses solely for exact-pose pictures; camera/mesh visibility changes without avatar.setup. Not human feel/FPS/full-match acceptance.","checks":checks,"release_before":release_before,"intents":intents,"shot_events":shots,"foot_trace":p.foot.action_trace.filter(func(e):return int(e.physics_frame)>=trace_frame),"path":path,"all_contacts":events,"shots_delta":game.stats.shots-shots_before,"rejected_delta":game.input_bridge.rejected_commands-rejected_before,"native_images":native_images}
	FileAccess.open(evidence.path_join("continuous_shot_%s.json"%case_id),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("CONTINUOUS_SHOT ",case_id," shots=",report.shots_delta," rejected=",report.rejected_delta," before_gap=",release_before.gap_m)
	release_inputs()
	game.pause_match()
	game.shutdown_audio()
	game.queue_free()
	game=null
	for _i in 4: await process_frame
	quit(0 if checks.all(func(c):return c.passed) else 1)
