extends Node
## Opt-in release validation; never activated by ordinary game startup.
var game: Node
var checks: Array[Dictionary] = []
var frames := 0
var evidence := ""
var ticket := ""
var capture_records: Array[Dictionary] = []
var focus_recoveries: Array[Dictionary] = []

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT:call_deferred("restore_fixture_focus")

func restore_fixture_focus() -> void:
	# QA-only logical context, without stealing the desktop focus or moving bodies.
	if not is_instance_valid(game) or not is_instance_valid(game.input_bridge):return
	if game.input_bridge.focused:return
	focus_recoveries.append({"frame":frames,"stage":stage,"held_keys":held_keys.duplicate()})
	game.input_bridge.focused=true
	game.sync_input_context()
	# Focus loss resets router holds; replay actual key edges for this fixture.
	for code in held_keys:key(code,false)
	for code in held_keys:key(code,true)

@onready var root: Window = get_tree().root
@onready var process_frame: Signal = get_tree().process_frame
@onready var physics_frame: Signal = get_tree().physics_frame

func _ready() -> void:
	evidence = ProjectSettings.globalize_path("res://../verification/native_dribble")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="): evidence = arg.trim_prefix("--evidence=")
		if arg.begins_with("--exclusive-render-ticket="): ticket = arg.trim_prefix("--exclusive-render-ticket=")
	if DisplayServer.get_name()=="headless" or ticket.is_empty():
		print("Native dribble validation requires a free single-renderer ticket")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(evidence)
	AudioServer.set_bus_mute(0,true)
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	call_deferred("run")

func check(name: String, ok: bool, details: Variant = null) -> void:
	checks.append({"check":name,"passed":ok,"details":details})
	print("PASS " if ok else "FAIL ",name)

func quit(code: int = 0) -> void:
	get_tree().quit(code)

func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func mouse(button: int, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func mouse_yaw(angle: float) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = Vector2(-angle/game.player.head.mouse_sensitivity,0)
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func release_inputs() -> void:
	inputs([])
	mouse(MOUSE_BUTTON_LEFT,false)
	mouse(MOUSE_BUTTON_RIGHT,false)

func capture(tag: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var file := tag+".png"
	var image := root.get_texture().get_image()
	var code := image.save_png(evidence.path_join(file))
	capture_records.append({"file":file,"result":code,"stage":stage,"size":image.get_size(),"camera":game.player.camera.global_transform,"ball":game.ball.position,"carrier_is_human":game.ball.carrier==game.player})

func fixture() -> void:
	release_inputs()
	game.ball.clear_control()
	game.ball.set_held(false)
	game.player.position = Vector3(0,.002,8)
	game.player.velocity = Vector3.ZERO
	game.player.reset_view(0)
	game.player.action_cooldown = 0
	game.player.tackle_cooldown = 0
	game.player.stop_requested = 0
	game.player.sole_stopped = false
	game.ball.position = Vector3(0,.113,7.42)
	game.ball.previous_position = game.ball.position
	game.ball.velocity = Vector3.ZERO
	game.ball.spin_rads = Vector3.ZERO
	game.ball.pickup_block = 0
	game.ball.touch_timer = 0
	game.ball.control_mode = "LOOSE"
	for i in game.agents.size():
		var agent: Node3D = game.agents[i]
		agent.position = Vector3(-28.0 if i%2 else 28.0,.002,-43.0+4.2*i)
		agent.velocity = Vector3.ZERO
		agent.target = agent.position
	game.sync_input_context()

## One actual RECEIVE, then continuous real-key low/medium/fast steering/chase.
## No position, velocity, ownership or rules fixture after acquisition.
var label := "before"
var stage := "receive"
var held_keys: Array[int] = []
var path: Array[Dictionary] = []
var stages: Array[Dictionary] = []
var touch_events: Array[Dictionary] = []
var stage_start := 0
var fixture_epoch := 0
var last_foot_sequence := -1
var last_foot_hit := false
var last_cooldown := 0.0
var cooldown_renewals := 0

func xyz(v: Vector3) -> Array: return [v.x,v.y,v.z]

func inputs(keys: Array) -> void:
	for code in held_keys:
		if not keys.has(code): key(code,false)
	for code in keys:
		if not held_keys.has(code): key(code,true)
	held_keys.clear()
	for code in keys: held_keys.append(code)

func tick() -> void:
	restore_fixture_focus()
	await physics_frame
	frames += 1
	var p: Node3D = game.player
	var f: FootballFootAction = p.foot
	if f.sequence==last_foot_sequence and last_foot_hit and f.hit and f.continuous_control() and game.ball.touch_timer>last_cooldown+.00001:
		cooldown_renewals += 1
	last_foot_sequence=f.sequence
	last_foot_hit=f.hit
	last_cooldown=game.ball.touch_timer
	if frames%6!=0: return
	var screen: Vector2 = p.camera.unproject_position(game.ball.global_position)
	var viewport: Rect2 = root.get_visible_rect()
	path.append({"t":frames/120.0,"stage":stage,"actor":xyz(p.position),"ball":xyz(game.ball.position),"body_velocity":xyz(p.velocity),"ball_velocity":xyz(game.ball.velocity),"relative":xyz(p.global_basis.inverse()*(game.ball.position-p.position)),"gap":game.flat_distance(p.position,game.ball.position),"owned":game.ball.carrier==p,"epoch":game.formation_serial,"kind":f.kind,"phase":FootballFootAction.Phase.keys()[f.phase],"side":f.side,"surface":f.surface,"direction":xyz(f.direction),"hit":f.hit,"foot_valid":f.actual_contact.get("valid",false),"reach_error":f.actual_contact.get("reach_error",-1.0),"failure":f.contact_failure,"motor":xyz(p.move_intent*lerpf(p.profile.jog_speed_mps,p.profile.sprint_speed_mps,p.sprint_intent)),"ball_screen":[screen.x,screen.y],"in_view":not p.camera.is_position_behind(game.ball.global_position) and viewport.has_point(screen)})

func segment(tag: String, seconds: float, keys: Array) -> void:
	stage = tag
	stage_start = frames
	var start_samples := path.size()
	var start_contacts := touch_events.size()
	inputs(keys)
	for i in roundi(seconds*120):
		await tick()
		if tag in ["low_inside_outside_right","medium_inside_outside_right","fast_inside_outside_right","mouse_right90"] and i==roundi(seconds*60): await capture(tag)
	var rows: Array = path.slice(start_samples)
	var hits: Array = touch_events.slice(start_contacts)
	var real_hits: Array = hits.filter(func(e):return e.success and e.matches_input)
	var speeds: Array = rows.map(func(r):return Vector2(r.body_velocity[0],r.body_velocity[2]).length())
	speeds.sort()
	var relative_x: Array = rows.map(func(r):return r.relative[0])
	stages.append({"stage":tag,"seconds":seconds,"owned_fraction":float(rows.filter(func(r):return r.owned).size())/maxi(1,rows.size()),"speed_median":speeds[speeds.size()/2],"gap_max":rows.map(func(r):return r.gap).max(),"relative_x_start_end":[relative_x.front(),relative_x.back()],"relative_x_minmax":[relative_x.min(),relative_x.max()],"first_touch_delay_s":real_hits[0].delay_s if not real_hits.is_empty() else -1.0,"successes":hits.filter(func(e):return e.success).size(),"matching_touches":real_hits.size(),"misses":hits.filter(func(e):return not e.success).size(),"surfaces":hits.map(func(e):return {"side":e.side,"surface":e.surface,"success":e.success}),"in_view_fraction":float(rows.filter(func(r):return r.in_view).size())/maxi(1,rows.size()),"final_gap":game.flat_distance(game.ball.position,game.player.position),"final_ball_speed":Vector2(game.ball.velocity.x,game.ball.velocity.z).length()})

func keys_for(extra: Array, movement: Array) -> Array:
	return movement+extra

func run_tier(tier: String, extra: Array) -> void:
	await segment(tier+"_cruise",2.0,keys_for(extra,[KEY_W]))
	await segment(tier+"_inside_left",.9,keys_for(extra,[KEY_W,KEY_A]))
	await segment(tier+"_cut_right",.9,keys_for(extra,[KEY_W,KEY_D]))
	await segment(tier+"_left",1.1,keys_for(extra,[KEY_A]))
	await segment(tier+"_inside_outside_right",2.0,keys_for(extra,[KEY_D]))
	await segment(tier+"_left_again",1.1,keys_for(extra,[KEY_A]))
	await segment(tier+"_forward",.9,keys_for(extra,[KEY_W]))
	await segment(tier+"_right90",1.5,keys_for(extra,[KEY_D]))
	await segment(tier+"_forward90",1.3,keys_for(extra,[KEY_W]))
	await segment(tier+"_stop",.6,[])
	var rows: Array = path.filter(func(r):return r.stage.begins_with(tier+"_"))
	var touches: Array = touch_events.filter(func(e):return e.stage.begins_with(tier+"_"))
	check(tier+" retains real control during all steering",rows.all(func(r):return r.owned and r.gap<1.1))
	for tag in ["inside_left","cut_right","inside_outside_right","right90","forward90"]:
		var result: Dictionary = stages.filter(func(s):return s.stage==tier+"_"+tag)[0]
		check(tier+" "+tag+" responds through a real touch",result.matching_touches>=1 and result.first_touch_delay_s>=0 and result.first_touch_delay_s<.50,result)
	check(tier+" inside then outside is an actual surface change",touches.any(func(e):return e.success and e.surface=="INSIDE") and touches.any(func(e):return e.success and e.surface=="OUTSIDE"))
	var right_touches: Array = touches.filter(func(e):return e.stage==tier+"_inside_outside_right" and e.success)
	var surfaces: Array = right_touches.map(func(e):return e.surface)
	check(tier+" right cut then outside push is one continuous operation",surfaces.has("INSIDE") and surfaces.has("OUTSIDE") and surfaces.find("INSIDE")<surfaces.find("OUTSIDE"),surfaces)
	var left: Dictionary = stages.filter(func(s):return s.stage==tier+"_left")[0]
	var right: Dictionary = stages.filter(func(s):return s.stage==tier+"_inside_outside_right")[0]
	check(tier+" ball crosses the body laterally",left.relative_x_minmax[0]<-.08 and right.relative_x_minmax[1]>.08,{"left":left.relative_x_minmax,"right":right.relative_x_minmax})

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="):label=arg.trim_prefix("--label=")
	game = load("res://scenes/match.tscn").instantiate()
	game.test_mode = true
	root.add_child(game)
	for _i in 3: await tick()
	game.ai_enabled = false
	game.services.rules.state = game.Rules.State.LIVE
	game.services.rules.restart.clear()
	game.set_phase(game.Phase.PLAY)
	game.services.configuration.half_seconds = 600.0
	game.contact_hub.contact_resolved.connect(func(e:Dictionary):
		if e.actor!=game.player:return
		touch_events.append({"stage":stage,"t":frames/120.0,"delay_s":(frames-stage_start)/120.0,"action":e.action,"surface":e.surface,"side":game.player.foot.side,"success":e.success,"deliberate":game.player.foot.deliberate_touch,"matches_input":game.player.foot.direction.dot(game.player.get_ball_direction())>.85,"direction":xyz(game.player.foot.direction),"input":xyz(game.player.get_ball_direction()),"before":xyz(e.before_velocity),"after":xyz(e.after_velocity),"point":xyz(e.point),"reach_error":e.get("reach_error",-1.0),"reason":game.player.foot.contact_failure,"sequence":e.get("action_sequence",-1)}))
	fixture()
	game.player.position.z = 45.0
	game.ball.position = Vector3(0,.113,44.42)
	game.ball.previous_position = game.ball.position
	for agent in game.agents:
		agent.refresh_pose(0)
		agent.pose_updates_enabled = false # Distant fixtures keep physical bodies; only human pose is under test.
	key(KEY_SPACE,true)
	await tick()
	key(KEY_SPACE,false)
	for _i in 45: await tick()
	fixture_epoch = game.formation_serial
	check("initial acquisition is actual RECEIVE",game.ball.carrier==game.player and touch_events.any(func(e):return e.success and e.action=="RECEIVE"))
	await run_tier("low",[KEY_CTRL])
	await run_tier("medium",[])
	await run_tier("fast",[KEY_SHIFT])
	await segment("full_speed_run",3.0,[KEY_W,KEY_SHIFT])
	var fast_rows: Array = path.filter(func(r):return r.stage=="full_speed_run").slice(-16)
	check("full-speed turn fixture reaches actual running pace",fast_rows.all(func(r):return Vector2(r.body_velocity[0],r.body_velocity[2]).length()>4.2),fast_rows.map(func(r):return Vector2(r.body_velocity[0],r.body_velocity[2]).length()))
	await segment("full_speed_right90",1.6,[KEY_D,KEY_SHIFT])
	var first_turn_rows: Array = path.filter(func(r):return r.stage=="full_speed_right90").slice(0,3)
	check("full-speed90 target retains reasonable pace",first_turn_rows.all(func(r):return Vector2(r.motor[0],r.motor[2]).length()>2.0),first_turn_rows.map(func(r):return r.motor))
	await segment("full_speed_forward90",1.6,[KEY_W,KEY_SHIFT])
	for tag in ["full_speed_right90","full_speed_forward90"]:
		var result: Dictionary = stages.filter(func(s):return s.stage==tag)[0]
		check(tag+" keeps control and responds through real contact",result.owned_fraction==1.0 and result.matching_touches>=2 and result.first_touch_delay_s<.35 and result.gap_max<.95,result)
	await segment("full_speed_stop",.8,[])
	await segment("double_first",.06,[KEY_W,KEY_SHIFT])
	await segment("double_release",.07,[KEY_W])
	await segment("double_second",.06,[KEY_W,KEY_SHIFT])
	await segment("big_touch_chase",3.5,[KEY_W,KEY_SHIFT])
	await segment("chase_stop",2.0,[])
	check("one actual big touch and a free chase",touch_events.filter(func(e):return e.success and e.action=="SPRINT").size()==1 and path.any(func(r):return r.stage=="big_touch_chase" and not r.owned))
	check("chase receives and stops without new fixture",game.ball.carrier==game.player and Vector2(game.ball.velocity.x,game.ball.velocity.z).length()<.08 and game.flat_distance(game.ball.position,game.player.position)<.70)
	await segment("retreat",1.2,[KEY_S])
	await segment("retreat_stop",1.2,[])
	check("backward release still stops",game.ball.carrier==game.player and Vector2(game.ball.velocity.x,game.ball.velocity.z).length()<.08 and game.flat_distance(game.ball.position,game.player.position)<.65)
	# Mouse event goes through the existing Head._input handler. No direct pose/yaw write.
	await segment("mouse_pre_roll",1.2,[KEY_W])
	# test_mode deliberately skips the normal PLAY mouse-capture transition.
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	var mouse_before: float = game.player.rotation.y
	mouse_yaw(PI/2.0)
	await tick()
	var yaw_changed := absf(angle_difference(mouse_before,game.player.rotation.y))
	check("actual mouse input turns the camera90deg",absf(yaw_changed-PI/2.0)<.01,{"yaw_delta_rad":yaw_changed,"mouse_mode":Input.get_mouse_mode()})
	await segment("mouse_right90",1.6,[KEY_W])
	var mouse_result: Dictionary = stages.back()
	check("mouse90 keeps ownership and gives a real directional touch",mouse_result.owned_fraction==1.0 and mouse_result.matching_touches>=2 and mouse_result.first_touch_delay_s<.35 and mouse_result.gap_max<.95,mouse_result)
	mouse_yaw(-PI/2.0)
	await tick()
	await segment("mouse_return90",1.6,[KEY_W])
	await segment("mouse_stop",.6,[])
	await segment("nudge_prepare",.05,[KEY_W,KEY_D])
	key(KEY_SPACE,true)
	await tick()
	key(KEY_SPACE,false)
	await segment("deliberate_nudge",.6,[KEY_W,KEY_D])
	check("direction Space keeps one deliberate physical nudge",touch_events.filter(func(e):return e.success and e.deliberate and e.action=="TURN").size()==1)
	await segment("before_shot_stop",.6,[])
	var shots_before: int = game.stats.shots
	stage="shot_charge"
	mouse(MOUSE_BUTTON_LEFT,true)
	for _i in 48:await tick()
	check("held charge does not emit a shot",game.stats.shots==shots_before)
	await capture("shot_charged")
	stage="shot_release"
	mouse(MOUSE_BUTTON_LEFT,false)
	for _i in 65:await tick()
	await capture("shot_released")
	check("continuous control chain ends in one real shot",game.stats.shots==shots_before+1 and touch_events.filter(func(e):return e.success and e.action=="SHOT").size()==1)
	check("no restart or scoring fixture occurred",path.all(func(r):return r.epoch==fixture_epoch))
	check("all successful contact reports keep real shoe tolerance",touch_events.filter(func(e):return e.success).all(func(e):return e.reach_error>=0 and e.reach_error<=.035 or e.action=="SPRINT" and e.reach_error>=0 and e.reach_error<=.035))
	check("continuous touch cooldown is consumed only at the first contact",cooldown_renewals==0,cooldown_renewals)
	var report := {"label":label,"scope":"One initial LIVE/spatial fixture and actual RECEIVE. Real keys; low Ctrl, medium no Shift, fast held Shift, then double Shift chase and retreat. 22 physical bodies, AI decisions and distant agent pose updates off; real human skeletal contacts. No actor/ball position, velocity or ownership resets after acquisition. First-person projection is numeric and does not prove mesh visibility/occlusion/comfort. Exported-EXE native controls; includes injected real MouseMotion90deg and native screenshots. AI decisions and distant poses deliberately off; not full-match FPS, human feel or occlusion acceptance.","checks":checks,"stages":stages,"path":path,"contacts":touch_events,"simulated_seconds":frames/120.0,"cooldown_renewals":cooldown_renewals}
	report["engine"] = Engine.get_version_info()
	report["GPU_used"] = true
	report["gpu"] = RenderingServer.get_video_adapter_name()
	report["ticket"] = ticket
	report["physics_hz"] = Engine.physics_ticks_per_second
	report["roster"] = game.players.size()
	report["ai_enabled"] = game.ai_enabled
	report["captures"] = capture_records
	report["focus_recoveries"] = focus_recoveries
	report["focus_scope"] = "QA-only logical focus restored for injected input; production focus cancellation preserved byte-for-byte. No actor/ball/ownership resets; raw interrupted attempt preserved."
	report["render_quality"] = game.get_node("MatchEnvironment").get_meta("daylight_profile","")
	check("native roster22 and physics120 retained",game.players.size()==22 and Engine.physics_ticks_per_second==120)
	check("native screenshots written",capture_records.size()==6 and capture_records.all(func(c):return c.result==OK))
	report["passed"] = checks.all(func(c):return c.passed)
	print("NATIVE_DRIBBLE_COMPLETE ",report.passed," checks=",checks.size())
	FileAccess.open(evidence.path_join("dribble_"+label+".json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	for result in stages:print("DRIBBLE ",JSON.stringify(result))
	release_inputs()
	game.pause_match()
	game.shutdown_audio()
	game.queue_free()
	game=null
	for _i in 4:await process_frame
	quit(0 if checks.all(func(c):return c.passed) else 1)
