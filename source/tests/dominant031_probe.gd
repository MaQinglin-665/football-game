extends SceneTree
## QA fixtures only: initial ball position/velocity assigned once per case.
## No assistance, forced contact, support changes or runtime observer patches.
var game: Node3D
var evidence := ""
var tag := ""
var keys: Array = []
var rows: Array = []
var contacts: Array = []
var cases: Array = []
var case_name := "warmup"
var case_tick := 0
var checks: Array = []
func _initialize()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="):evidence=arg.trim_prefix("--evidence=")
		elif arg.begins_with("--tag="):tag=arg.trim_prefix("--tag=")
	seed(61906)
	call_deferred("start")
func start()->void:
	game=load("res://scenes/training_3v3.tscn").instantiate()
	game.test_mode=true;root.add_child(game);current_scene=game
	for i in 4:await process_frame
	game.contact_hub.contact_resolved.connect(on_contact)
	game.hud.menu.get_node("StartMatch").pressed.emit()
	for i in 24:await physics_frame
	check("normal six actors AI on",game.players.size()==6 and game.agents.size()==5 and game.ai_enabled)
	for roll in ["A","B"]:
		for forward in [-.12,.28,.50]:
			for lateral in [-.26,0.0,.26]:
				await reset_case("%s_left_x%.2f_z%.2f"%[roll,lateral,forward],roll,Vector2(lateral,forward))
				set_keys([KEY_CTRL,KEY_A])
				await ticks(108)
		await reset_case(roll+"_light_forward",roll)
		set_keys([KEY_CTRL,KEY_W]);await ticks(240)
		await reset_case(roll+"_continuous_turn",roll)
		set_keys([KEY_CTRL,KEY_W]);await ticks(90)
		set_keys([KEY_CTRL,KEY_A]);await ticks(90)
		set_keys([KEY_CTRL,KEY_D]);await ticks(90)
		set_keys([KEY_CTRL,KEY_W,KEY_A]);await ticks(90)
		await reset_case(roll+"_coast_1.2",roll,Vector2(0.0,.5))
		game.ball.detach("")
		game.ball.velocity=game.player.body_facing*1.2
		game.ball.spin_rads=Vector3.UP.cross(game.ball.velocity)/game.ball.radius
		# Avoid a new reception obscuring standalone free rolling.
		game.ball.position+=game.player.body_facing*4.0
		await ticks(240)
	await reset_case("regression_right", "B")
	set_keys([KEY_CTRL,KEY_D]);await ticks(120)
	await reset_case("regression_pass", "B")
	set_keys([KEY_Q]);await ticks(2);set_keys([]);await ticks(144)
	set_keys([])
	check("right input actual ordinary contact",contacts.any(func(c):return c.case=="regression_right" and c.event.success and c.event.action=="TURN"))
	check("Q actual pass contact",contacts.any(func(c):return c.case=="regression_pass" and c.event.success and c.event.action=="PASS"))
	var cross:Array=contacts.filter(func(c):return c.event.success and c.plan.get("dominant_cross_body",false))
	check("cross body contacts all real planted support",not cross.is_empty() and cross.all(func(c):return c.support.support_phase.L.state=="PLANTED" and c.support.support_phase.L.sole_near_ground and c.support.support_phase.L.leg_margin_m>=0))
	check("weak side rescue retained",contacts.any(func(c):return c.event.success and c.side==-1 and c.surface=="OUTSIDE"))
	check("body input responds before first contact",cases.filter(func(c):return "_left_x" in c.name).all(func(c):
		var observed:Array=rows.filter(func(row):return row.case==c.name)
		var actual:Array=contacts.filter(func(event):return event.case==c.name and event.event.success)
		return not actual.is_empty() and observed.any(func(row):return row.tick<actual[0].tick and Vector3(row.actor_velocity[0],row.actor_velocity[1],row.actor_velocity[2]).length()>.05)))
	check("A and B actual F7 settings",cases.any(func(c):return c.roll=="A" and c.extra==0.0) and cases.any(func(c):return c.roll=="B" and c.extra==.75))
	check("actual ordinary contact",contacts.any(func(c):return c.event.success and c.event.action in ["TURN","CLOSE","SHIELD"]))
	check("finite ball and actor motion",rows.all(func(r):return Vector3(r.ball_velocity[0],r.ball_velocity[1],r.ball_velocity[2]).is_finite() and Vector3(r.actor_velocity[0],r.actor_velocity[1],r.actor_velocity[2]).is_finite()))
	check("no ordinary duplicate sequence",unique_contacts())
	DirAccess.make_dir_recursive_absolute(evidence)
	FileAccess.open(evidence.path_join("DOMINANT031.json"),FileAccess.WRITE).store_string(JSON.stringify({"tag":tag,"cases":cases,"rows":rows,"contacts":contacts,"checks":checks,"passed":checks.all(func(c):return c.passed),"scope":"031 six actor AI enabled; exact initial position/velocity fixtures once per case then actual Ctrl/W/A/D and F7/R input; no forced support/contact. Coast fixture moves ball away to isolate roll. No manual comfort or full match claim."},"\t"))
	print("DOMINANT031_DONE ",checks.all(func(c):return c.passed)," contacts=",contacts.size()," rows=",rows.size())
	game.shutdown_audio();game.queue_free()
	for i in 4:await process_frame
	quit(0 if checks.all(func(c):return c.passed) else 1)
func reset_case(label:String,roll:String,offset:Vector2=Vector2(INF,INF))->void:
	set_keys([])
	# Recreate a normal host so A/B starts with identical completed pose phase.
	game.shutdown_audio();game.queue_free()
	for i in 4:await process_frame
	seed(61906)
	game=load("res://scenes/training_3v3.tscn").instantiate()
	game.test_mode=true;root.add_child(game);current_scene=game
	for i in 4:await process_frame
	game.contact_hub.contact_resolved.connect(on_contact)
	game.hud.menu.get_node("StartMatch").pressed.emit()
	for i in 24:await physics_frame
	key(KEY_R,true);key(KEY_R,false)
	for i in 3:await physics_frame
	if game.get_node("TurfRollAB").mode!=roll:key(KEY_F7,true);key(KEY_F7,false)
	game.player.foot.cancel()
	if offset.is_finite():
		var facing:Vector3=game.player.body_facing
		var right:=Vector3(-facing.z,0,facing.x)
		game.ball.position=game.player.position+right*offset.x+facing*offset.y
		game.ball.position.y=game.ball.radius+.001
		game.ball.velocity=Vector3.ZERO;game.ball.spin_rads=Vector3.ZERO
		game.ball.touch_timer=0.0;game.ball.dribble_free_roll_remaining=0.0
	case_name=label;case_tick=0
	cases.append(pack({"name":label,"roll":roll,"extra":game.physics_profile.low_speed_roll_extra_mps2,"actor_start":game.player.position,"ball_start":game.ball.position,"body_facing":game.player.body_facing,"owner":game.ball.carrier==game.player,"fixture":offset.is_finite(),"initial_support":game.player.avatar.get_control_support_snapshot()}))
func ticks(count:int)->void:
	for i in count:
		await physics_frame
		var a=game.player
		var f=a.foot
		rows.append(pack({"case":case_name,"tick":case_tick,"frame":Engine.get_physics_frames(),"actor":a.position,"actor_velocity":a.velocity,"semantic_motion":a.semantic_motion,"ball":game.ball.position,"ball_velocity":game.ball.velocity,"owned":game.ball.carrier==a,"phase":game.phase,"control_mode":game.ball.control_mode,"touch_timer":game.ball.touch_timer,"free_roll_remaining":game.ball.dribble_free_roll_remaining,"kind":f.kind,"side":f.side,"surface":f.surface,"foot_phase":f.phase,"sequence":f.sequence,"hit":f.hit,"foot_elapsed":f.elapsed,"failure":f.contact_failure,"decision":f.ordinary_scheduler.last_decision,"support":a.avatar.get_control_support_snapshot(),"body_control_phase":f.ordinary_scheduler.body_control_snapshot(a) if f.ordinary_scheduler.has_method("body_control_snapshot") else {},"actual_socket":a.avatar.get_foot_contact(f.side,f.surface)}))
		case_tick+=1
func key(code:int,pressed:bool)->void:
	var e:=InputEventKey.new();e.keycode=code;e.physical_keycode=code;e.pressed=pressed
	Input.parse_input_event(e);Input.flush_buffered_events()
func set_keys(wanted:Array)->void:
	for code in keys:
		if not wanted.has(code):key(code,false)
	for code in wanted:
		if not keys.has(code):key(code,true)
	keys=wanted.duplicate()
func on_contact(e:Dictionary)->void:
	if e.actor!=game.player or e.get("kind","") not in ["FOOT_TOUCH","FOOT_ACTION_FAILED"]:return
	contacts.append(pack({"case":case_name,"tick":case_tick,"event":e,"side":e.actor.foot.side,"surface":e.actor.foot.surface,"sequence":e.actor.foot.sequence,"plan":e.actor.foot.touch_plan,"support":e.actor.avatar.get_control_support_snapshot(),"actor":game.player.position,"ball":game.ball.position}))
func unique_contacts()->bool:
	var seen:Dictionary={}
	for c in contacts:
		if not c.event.success or c.event.action not in ["TURN","CLOSE","SHIELD"]:continue
		var id:=str(c.case)+":"+str(c.sequence)
		if seen.has(id):return false
		seen[id]=true
	return true
func pack(v:Variant)->Variant:
	if v is Vector3:return [v.x,v.y,v.z]
	if v is Quaternion:return [v.x,v.y,v.z,v.w]
	if v is Node:return str(v.get_path())
	if v is Dictionary:
		var d:Dictionary={}
		for k in v:d[str(k)]=pack(v[k])
		return d
	if v is Array:
		var a:Array=[]
		for x in v:a.append(pack(x))
		return a
	return v
func check(label:String,ok:bool)->void:
	checks.append({"check":label,"passed":ok});print("PASS " if ok else "FAIL ",label)
