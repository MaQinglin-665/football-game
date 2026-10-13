extends Node
## Opt-in functional observer/driver. Ordinary entry frees this node immediately.
var game: Node3D
var checks: Array[Dictionary] = []
var path: Array[Dictionary] = []
var events: Array[Dictionary] = []
var captures: Array[String] = []
var held: Array[int] = []
var evidence := ""
var stage := "setup"
var frame_count := 0
var locked: Dictionary = {}
var lock_errors := 0
var released_samples := 0
var separated_samples := 0
var native := false
var force_required := false

func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	if not "--training-touchplan-check" in OS.get_cmdline_user_args():
		queue_free()
		return
	game = get_parent() as Node3D
	game.test_mode = true
	native = DisplayServer.get_name() != "headless"
	force_required = "--training-force-observer" in OS.get_cmdline_user_args()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="): evidence = arg.trim_prefix("--evidence=")
	call_deferred("run")

func serial(value: Variant) -> Variant:
	if value is Vector3: return [value.x,value.y,value.z]
	if value is Quaternion: return [value.x,value.y,value.z,value.w]
	if value is Dictionary:
		var result: Dictionary = {}
		for k in value: result[str(k)] = serial(value[k])
		return result
	if value is Array:
		var result: Array = []
		for item in value: result.append(serial(item))
		return result
	return value

func check(label: String, ok: bool, details: Variant = null) -> void:
	checks.append({"label":label,"passed":ok,"details":serial(details)})
	print("PASS " if ok else "FAIL ",label)

func key(code: int, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func inputs(next: Array) -> void:
	for code in held:
		if not next.has(code): key(code,false)
	for code in next:
		if not held.has(code): key(code,true)
	held.clear()
	for code in next: held.append(code)

func tick() -> void:
	await get_tree().physics_frame
	frame_count += 1
	var f: FootballFootAction = game.player.foot
	var plan: Dictionary = f.touch_plan
	if f.planned_dribble() and f.hit:
		released_samples += 1
		var stamp := {"point":plan.get("contact_point",Vector3.ZERO),"local":plan.get("contact_local",Vector3.ZERO),"normal":plan.get("normal",Vector3.ZERO),"exit":plan.get("exit_velocity",Vector3.ZERO),"elapsed":plan.get("contact_elapsed",-1.0),"desired":plan.get("desired_velocity",Vector3.ZERO)}
		if locked.has(f.sequence):
			if locked[f.sequence] != stamp: lock_errors += 1
		else: locked[f.sequence] = stamp.duplicate(true)
		var presented: Dictionary = game.player.avatar.get("_action")
		var target: Vector3 = presented.get("world_target",f.toe_world)
		var sphere_gap := absf(target.distance_to(game.ball.position)-game.ball.radius)
		if sphere_gap > .010: separated_samples += 1
	var slip: Vector3 = game.ball.velocity+game.ball.spin_rads.cross(Vector3.DOWN*game.ball.radius)
	path.append(serial({"frame":frame_count,"physics_frame":Engine.get_physics_frames(),"world_step":game.physics_world.step_serial,"stage":stage,"player":game.player.position,"player_velocity":game.player.velocity,"ball":game.ball.position,"ball_velocity":game.ball.velocity,"spin_rads":game.ball.spin_rads,"radius":game.ball.radius,"grounded":game.ball.grounded,"surface_slip_velocity":slip,"collision_count":game.ball.collision_count,"gap":game.flat_distance(game.player.position,game.ball.position),"owned":game.ball.carrier==game.player,"repetition":game.training_mode.repetitions,"rules":game.services.rules.state_name(),"kind":f.kind,"phase":f.phase,"side":f.side,"surface":f.surface,"sequence":f.sequence,"hit":f.hit,"actual_contact":f.actual_contact,"plan":plan}))

func segment(tag: String, count: int, keys: Array) -> void:
	stage = tag
	inputs(keys)
	for i in count: await tick()

func capture(tag: String) -> void:
	if not native: return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var filename := tag+".png"
	var result := get_viewport().get_texture().get_image().save_png(evidence.path_join(filename))
	check("native capture "+tag,result==OK)
	captures.append(filename)

func run() -> void:
	if evidence.is_empty():
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(evidence)
	for i in 4: await get_tree().physics_frame
	check("default small scene has six actors and one fixed human",game.players.size()==6 and game.agents.size()==5 and game.players.filter(func(p):return p.is_human).size()==1)
	check("120Hz and same real-contact World",Engine.physics_ticks_per_second==120 and game.physics_world.actors.size()==6 and not game.ball.auto_step)
	check("training dimensions36x24 and small goals",game.field_half_length==18.0 and game.field_half_width==12.0 and game.goal_width==3.0 and game.goal_height==1.5)
	check("normal camera and player implementation",game.player.camera.fov==96.0 and game.player.get_script().resource_path=="res://scripts/football_shared_player.gd")
	await capture("touchplan3v3_menu")
	game.contact_hub.contact_resolved.connect(func(event: Dictionary):
		if event.actor!=game.player: return
		events.append(serial({"frame":frame_count,"physics_frame":Engine.get_physics_frames(),"world_step":game.physics_world.step_serial,"stage":stage,"action":event.action,"sequence":event.get("action_sequence",-1),"success":event.success,"surface":event.surface,"before":event.before_velocity,"after":event.after_velocity,"point":event.point,"ball_at_contact":game.ball.position,"spin_at_contact":game.ball.spin_rads,"radius":game.ball.radius,"grounded":game.ball.grounded,"collision_count":game.ball.collision_count,"deliberate":game.player.foot.deliberate_touch}))
	)
	game.hud.menu.get_node("StartMatch").pressed.emit()
	check("menu starts live owned training round",game.phase==game.Phase.PLAY and game.services.rules.is_ball_live() and game.ball.carrier==game.player)
	check("all five AI decisions stay enabled",game.ai_enabled and game.agents.all(func(a):return a.visible))
	game.ball.set_meta("touch_trace",[])
	var repetition: int = game.training_mode.repetitions
	var starts: Array[Vector3] = []
	for actor in game.players: starts.append(actor.position)
	await segment("cruise",108,[KEY_W])
	await segment("inside_left",84,[KEY_W,KEY_A])
	await segment("cut_right",84,[KEY_W,KEY_D])
	await segment("left90",60,[KEY_A])
	await segment("right90",108,[KEY_D])
	await segment("reverse_left",60,[KEY_A])
	await segment("shift_forward",84,[KEY_W,KEY_SHIFT])
	await capture("touchplan3v3_shift")
	await segment("stop",84,[])
	inputs([])
	var ordinary: Array = events.filter(func(e):return e.success and not e.deliberate and e.action in ["CLOSE","TURN","SHIELD"])
	check("ordinary dribble makes real confirmed contacts",ordinary.size()>=3,ordinary.size())
	check("inside and outside surfaces both used",ordinary.any(func(e):return e.surface=="INSIDE") and ordinary.any(func(e):return e.surface=="OUTSIDE"))
	check("no repeated human contact event for ordinary sequence",ordinary.map(func(e):return e.sequence).size()==locked.size(),{"events":ordinary.size(),"locked_sequences":locked.size()})
	check("committed point normal result stay locked",released_samples>0 and lock_errors==0,{"released_samples":released_samples,"errors":lock_errors})
	check("released shoe target separates geometrically",separated_samples>0,{"separated_samples":separated_samples,"released_samples":released_samples})
	check("continuous input chain has no repetition reset",game.training_mode.repetitions==repetition)
	check("all recorded player ball and velocity states finite",path.all(func(row):return (Vector3(row.player[0],row.player[1],row.player[2])).is_finite() and (Vector3(row.ball[0],row.ball[1],row.ball[2])).is_finite() and (Vector3(row.ball_velocity[0],row.ball_velocity[1],row.ball_velocity[2])).is_finite()))
	var ai_displaced := 0
	for i in range(1,game.players.size()):
		if game.players[i].position.distance_to(starts[i])>.1: ai_displaced += 1
	check("five AI have actual movement",ai_displaced==5,ai_displaced)
	var writes: Array = game.ball.get_meta("touch_trace",[])
	if force_required:
		var impulse_rows: Array = writes.filter(func(row):return row.source=="impulse" and (row.callers as Array).has("commit_dribble_result") and row.kind in ["CLOSE","TURN","SHIELD"])
		var counts: Dictionary = {}
		for row in impulse_rows: counts[row.sequence]=int(counts.get(row.sequence,0))+1
		check("actual write observer has exactly one impulse per ordinary contact",not impulse_rows.is_empty() and counts.size()==ordinary.size() and counts.values().all(func(n):return n==1),counts)
		check("no active ordinary impulse after FREE_ROLL",impulse_rows.all(func(row):return row.plan_state!="FREE_ROLL"))
		var budget: float = game.physics_profile.receiver_force_budget_n*.035
		check("ordinary impulses remain within original35ms budget",impulse_rows.all(func(row):return Vector3(row.impulse_ns[0],row.impulse_ns[1],row.impulse_ns[2]).length()<=budget+.000001),budget)
	await segment("ground_pass_charge",60,[KEY_Q])
	await segment("ground_pass_release",120,[])
	check("actual Q groundPASS through unchanged input",events.any(func(e):return e.success and e.action=="PASS"))
	await capture("touchplan3v3_stop")
	var failures: Array = checks.filter(func(c):return not c.passed)
	var report := {"checks":checks,"passed":failures.is_empty(),"passed_count":checks.size()-failures.size(),"total":checks.size(),"frames":frame_count,"roster":game.players.size(),"ai_enabled":game.ai_enabled,"native":native,"events":events,"path":path,"velocity_writes":serial(writes),"force_observer_required":force_required,"force_checks_run":force_required,"captures":captures,"scope":"Actual default3v3 scene, single menu opening then real key input/AI only; no actor/ball/ownership/rules reset during live input chain. Optional separate force observer. Functional only, no11v11/22person FPS evidence, no OS/manual-feel acceptance."}
	FileAccess.open(evidence.path_join("TOUCHPLAN_3V3_FUNCTIONAL.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("TOUCHPLAN_3V3_FUNCTIONAL_DONE valid=",report.passed," checks=",checks.size())
	reparent(get_tree().root)
	game.pause_match()
	game.shutdown_audio()
	game.queue_free()
	game = null
	for i in 4: await get_tree().process_frame
	get_tree().quit(0 if report.passed else 1)
