extends SceneTree
const Turn := preload("res://scripts/dribble_turn_control.gd")
const Rhythm := preload("res://scripts/dribble_rhythm.gd")
const Reference := preload("res://tests/three_turn038_reference.gd")
var straight_errors:Array=[]
var turn_marks:Array=[]
## QA fixtures only: initial ball position/velocity assigned once per case.
## No assistance, forced contact, support changes or runtime observer patches.
var game: Node3D
var evidence := ""
var tag := ""
var keys: Array = []
var rows: Array = []
var contacts: Array = []
var steps:Array=[]
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
	for fixture in [
		{"name":"slow_straight","first":[KEY_CTRL,KEY_W],"turn":[],"turn2":[],"warm":240,"ticks":0},
		{"name":"slow_turn","first":[KEY_CTRL,KEY_W],"turn":[KEY_CTRL,KEY_W,KEY_A],"turn2":[KEY_CTRL,KEY_A],"warm":120,"ticks":120},
		{"name":"medium_turn","first":[KEY_W],"turn":[KEY_W,KEY_A],"turn2":[KEY_A],"warm":180,"ticks":120},
		{"name":"fast_90","first":[KEY_SHIFT,KEY_W],"turn":[KEY_SHIFT,KEY_D],"turn2":[],"warm":180,"ticks":240},
		{"name":"fast_reverse","first":[KEY_SHIFT,KEY_W],"turn":[KEY_SHIFT,KEY_S],"turn2":[],"warm":180,"ticks":360}]:
		await reset_case(fixture.name,"B",Vector2(0,.28),true)
		set_keys(fixture.first);await ticks(fixture.warm)
		if not fixture.turn.is_empty():
			turn_marks.append({"case":case_name,"tick":case_tick,"speed":Vector2(game.player.velocity.x,game.player.velocity.z).length(),"velocity":pack(game.player.velocity),"aim":pack(game.player.get_ball_direction())})
			set_keys(fixture.turn);await ticks(fixture.ticks)
			if not fixture.turn2.is_empty():set_keys(fixture.turn2);await ticks(180)
	set_keys([])
	check("slow straight same-state037 pace formula unchanged",straight_errors.size()>=120 and straight_errors.all(func(v):return v<.000001))
	check("slow straight actual contacts",contacts.filter(func(c):return c.case=="slow_straight" and c.event.success and c.event.action in ["CLOSE","TURN"]).size()>=2)
	for label in ["slow_turn","medium_turn","fast_90"]:
		check(label+" actual directional foot contact",contacts.any(func(c):return c.case==label and c.event.success and c.plan.has("turn_prediction")))
	var reverse_mark:Dictionary=turn_marks.filter(func(m):return m.case=="fast_reverse")[0]
	var reverse_rows:Array=rows.filter(func(r):return r.case=="fast_reverse" and r.tick>int(reverse_mark.tick)+300)
	check("reverse entered above2.1mps",float(reverse_mark.speed)>2.1)
	check("reverse actual braking or pull contact after input",contacts.any(func(c):return c.case=="fast_reverse" and c.tick>int(reverse_mark.tick) and c.event.success and (c.event.action=="PULL" or c.plan.get("turn_prediction",{}).get("mode","")=="MOMENTUM_BRAKE")))
	check("reverse reacquires bounded gap and moves back",not reverse_rows.is_empty() and reverse_rows.any(func(r):return r.owned and Vector3(r.ball[0],r.ball[1],r.ball[2]).distance_to(Vector3(r.actor[0],r.actor[1],r.actor[2]))<1.8 and Vector3(r.actor_velocity[0],r.actor_velocity[1],r.actor_velocity[2]).dot(Vector3(reverse_mark.aim[0],reverse_mark.aim[1],reverse_mark.aim[2]))<-.25))
	check("all motion finite",rows.all(func(r):return Vector3(r.ball_velocity[0],r.ball_velocity[1],r.ball_velocity[2]).is_finite() and Vector3(r.actor_velocity[0],r.actor_velocity[1],r.actor_velocity[2]).is_finite()))
	check("no ordinary duplicate sequence",unique_contacts())
	DirAccess.make_dir_recursive_absolute(evidence)
	var report:String=evidence.path_join("THREE_TURN038.json")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):report=arg.trim_prefix("--output=")
	FileAccess.open(report,FileAccess.WRITE).store_string(JSON.stringify({"tag":tag,"turn_marks":turn_marks,"straight_formula_errors":straight_errors,"cases":cases,"rows":rows,"contacts":contacts,"steps":steps,"checks":checks,"passed":checks.all(func(c):return c.passed),"scope":"Five isolated declared initialfixtures: slowstraight same-state037 formula reference, low/medium45to90, Shift90/reverse. Real humaninput/motor/shoe/World; other5actors disabled/far. No wholebaselineAB/nativefeel/FPS/fullmatch acceptance."},"\t"))
	print("THREE_TURN038_DONE ",checks.all(func(c):return c.passed)," contacts=",contacts.size()," rows=",rows.size())
	game.shutdown_audio();game.queue_free()
	for i in 4:await process_frame
	quit(0 if checks.all(func(c):return c.passed) else 1)
func reset_case(label:String,roll:String,offset:Vector2=Vector2(INF,INF),isolated:bool=false)->void:
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
	if isolated:
		# QA-only isolation: keep six bodies/real motor and turf. Freeze other
		# actors far away to separate coordination from pressure/ball loss.
		for agent in game.agents:
			agent.set_physics_process(false);agent.set_move_intent(Vector3.ZERO);agent.foot.cancel()
			agent.position=Vector3(9.0+float(agent.team),0,11.0+float(agent.jersey)*.01)
	case_name=label;case_tick=0
	game.player.avatar.ground_step.connect(on_step)
	cases.append(pack({"name":label,"roll":roll,"extra":game.physics_profile.low_speed_roll_extra_mps2,"actor_start":game.player.position,"ball_start":game.ball.position,"body_facing":game.player.body_facing,"owner":game.ball.carrier==game.player,"fixture":offset.is_finite(),"isolation_others_frozen":isolated,"initial_support":game.player.avatar.get_control_support_snapshot()}))
func ticks(count:int)->void:
	for i in count:
		await physics_frame
		var a=game.player
		var f=a.foot
		rows.append(pack({"case":case_name,"tick":case_tick,"frame":Engine.get_physics_frames(),"actor":a.position,"actor_velocity":a.velocity,"semantic_motion":a.semantic_motion,"ball":game.ball.position,"ball_velocity":game.ball.velocity,"owned":game.ball.carrier==a,"phase":game.phase,"control_mode":game.ball.control_mode,"touch_timer":game.ball.touch_timer,"free_roll_remaining":game.ball.dribble_free_roll_remaining,"kind":f.kind,"side":f.side,"surface":f.surface,"foot_phase":f.phase,"sequence":f.sequence,"hit":f.hit,"foot_elapsed":f.elapsed,"failure":f.contact_failure,"decision":f.ordinary_scheduler.last_decision,"support":a.avatar.get_control_support_snapshot(),"body_control_phase":f.ordinary_scheduler.body_control_snapshot(a) if f.ordinary_scheduler.has_method("body_control_snapshot") else {},"sprinting":a.sprinting,"movement_tier":a.movement_tier,"body_debug":a.avatar.get_full_body_debug(),"motor_target":a.shared_last_result.get("motion",Vector3.ZERO),"body_facing":a.body_facing,"aim":a.get_ball_direction(),"left_sole":a.avatar.get_foot_contact(-1,"SOLE"),"right_sole":a.avatar.get_foot_contact(1,"SOLE"),"actual_socket":a.avatar.get_foot_contact(f.side,f.surface)}))
		if case_name=="slow_straight" and Turn.angle(a,a.get_ball_direction())<=deg_to_rad(15):
			straight_errors.append(Rhythm.pace(a,game.ball,a.get_ball_direction(),a.speed).distance_to(Reference.pace(a,game.ball,a.get_ball_direction(),a.speed)))
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
	contacts.append(pack({"case":case_name,"tick":case_tick,"event":e,"side":e.actor.foot.side,"surface":e.actor.foot.surface,"sequence":e.actor.foot.sequence,"plan":e.actor.foot.touch_plan,"decision":e.actor.foot.ordinary_scheduler.last_decision,"support":e.actor.avatar.get_control_support_snapshot(),"actor":game.player.position,"ball":game.ball.position}))
func on_step(event:Dictionary)->void:
	steps.append(pack({"case":case_name,"tick":case_tick,"event":event,"actor":game.player.position}))
func mouse(button:int,pressed:bool)->void:
	var event:=InputEventMouseButton.new();event.button_index=button;event.pressed=pressed
	Input.parse_input_event(event);Input.flush_buffered_events()
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
