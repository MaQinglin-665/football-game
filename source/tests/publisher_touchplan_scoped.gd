extends "res://tests/integration_checks.gd"
## Same scripted inputs for frozen0.6.9 and candidate. Private observer only.
var label := "before"
var stage := "setup"
var path: Array[Dictionary] = []
var events: Array[Dictionary] = []
var stages: Array[Dictionary] = []
var writes: Array[Dictionary] = []
var deferred_checks: Array[Dictionary] = []
var held: Array[int] = []

func xyz(v: Vector3) -> Array: return [v.x,v.y,v.z]

func inputs(keys: Array) -> void:
	for code in held:
		if not keys.has(code):key(code,false)
	for code in keys:
		if not held.has(code):key(code,true)
	held.clear()
	for code in keys:held.append(code)

func tick() -> void:
	await physics_frame
	frames += 1
	var p = game.player
	var f = p.foot
	var plan: Dictionary = {}
	if label!="before":plan=f.touch_plan.duplicate(true)
	path.append({"frame":Engine.get_physics_frames(),"stage":stage,"t":frames/120.0,"actor":xyz(p.position),"ball":xyz(game.ball.position),"velocity":xyz(game.ball.velocity),"body_velocity":xyz(p.velocity),"kind":f.kind,"phase":FootballFootAction.Phase.keys()[f.phase],"hit":f.hit,"sequence":f.sequence,"side":f.side,"surface":f.surface,"owned":game.ball.carrier==p,"gap":game.flat_distance(p.position,game.ball.position),"toe":xyz(f.toe_world),"shoe_target":xyz(p.avatar.get("_action").get("world_target",f.toe_world)) if not f.idle() else [],"body_yaw":p.rotation.y,"close_control":p.close_control,"sprinting":p.sprinting,"style":p.semantic_move_style,"plan":plan})

func segment(tag: String, seconds: float, keys: Array) -> void:
	stage=tag
	var start := path.size()
	var event_start := events.size()
	inputs(keys)
	for _i in roundi(seconds*120):await tick()
	var rows: Array = path.slice(start)
	var hits: Array = events.slice(event_start).filter(func(e):return e.success and e.action in ["CLOSE","TURN","SHIELD"])
	var speeds: Array = rows.map(func(r):return Vector2(r.body_velocity[0],r.body_velocity[2]).length())
	var settled_speeds: Array = rows.slice(-90).map(func(r):return Vector2(r.body_velocity[0],r.body_velocity[2]).length())
	settled_speeds.sort()
	speeds.sort()
	stages.append({"stage":tag,"seconds":seconds,"successes":hits.size(),"first_contact_s":hits[0].t-rows[0].t if not hits.is_empty() else -1.0,"speed_median":speeds[speeds.size()/2],"settled_speed_median":settled_speeds[settled_speeds.size()/2],"gap_max":rows.map(func(r):return r.gap).max(),"owned_fraction":float(rows.filter(func(r):return r.owned).size())/rows.size()})

func reset_episode(offset := Vector3(0,0,-.58)) -> void:
	inputs([])
	for _i in 3: await tick() # Consume key-up commands before fixture changes input authority.
	stage="receive"
	game.ball.remove_meta("touch_trace")
	fixture()
	game.player.position.z=40
	game.ball.position=game.player.position+offset+Vector3.UP*.111
	game.ball.previous_position=game.ball.position
	for agent in game.agents:
		agent.refresh_pose(0)
		agent.pose_updates_enabled=false
	game.ball.set_meta("touch_trace",writes)
	key(KEY_SPACE,true)
	await tick()
	key(KEY_SPACE,false)
	for _i in 45:await tick()
	check("actual RECEIVE "+str(stages.size()),game.ball.carrier==game.player)

func wait_next_touch(kind: String = "") -> Dictionary:
	var start := events.size()
	for _i in 100:
		await tick()
		for e in events.slice(start):
			if e.success and (e.action==kind if kind!="" else e.action in ["CLOSE","TURN","SHIELD"]):return e
	return {}

func ordinary_impulses(rows: Array, minimum_frame := -1, maximum_frame := 2147483647) -> Array:
	return rows.filter(func(r):return r.source=="impulse" and r.frame>=minimum_frame and r.frame<=maximum_frame and r.kind in ["CLOSE","TURN","SHIELD"] and (r.callers.has("buffer_contact") or r.callers.has("commit_dribble_result")))

func deferred(label_text: String, ok: bool, details: Variant = null) -> void:
	check(label_text,ok,details) # Both original deferred force checks are mandatory for this finite-result candidate.

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="):label=arg.trim_prefix("--label=")
	AudioServer.set_bus_mute(0,true)
	game=load("res://scenes/match.tscn").instantiate()
	game.test_mode=true
	root.add_child(game)
	for _i in 3:await tick()
	game.ai_enabled=false
	game.services.rules.state=game.Rules.State.LIVE
	game.services.rules.restart.clear()
	game.services.configuration.half_seconds=600
	game.set_phase(game.Phase.PLAY)
	game.contact_hub.contact_resolved.connect(func(e:Dictionary):
		if e.actor==game.player:events.append({"frame":Engine.get_physics_frames(),"t":frames/120.0,"stage":stage,"action":e.action,"surface":e.surface,"side":game.player.foot.side,"success":e.success,"sequence":game.player.foot.sequence,"before":xyz(e.before_velocity),"after":xyz(e.after_velocity),"reach":e.get("reach_error",-1.0)}))
	for tier in ["low","medium","fast"]:
		await reset_episode()
		await segment(tier,2.5,[KEY_W,KEY_CTRL] if tier=="low" else [KEY_W,KEY_SHIFT] if tier=="fast" else [KEY_W])
		var result: Dictionary=stages.back()
		check(tier+" retains control and regular contacts",result.owned_fraction>.98 and result.gap_max<1.1 and result.successes>=8,result)
		check(tier+" actual movement tier reaches intended pace",result.settled_speed_median>(1.3 if tier=="low" else 2.1 if tier=="medium" else 4.2),result)
	await reset_episode(Vector3(.28,0,-.48))
	await segment("right_ball_left_cut",.8,[KEY_A])
	var cut: Array=events.filter(func(e):return e.stage=="right_ball_left_cut" and e.success and e.action=="TURN")
	check("right-side ball left cut uses right INSIDE",not cut.is_empty() and cut[0].side==1 and cut[0].surface=="INSIDE",cut.slice(0,1))

	await reset_episode()
	await segment("camera_warm",2.0,[KEY_W])
	stage="camera_free_roll"
	var contact: Dictionary=await wait_next_touch()
	check("camera probe starts from a real contact",not contact.is_empty())
	var trace_start := writes.size()
	var before: Vector3=game.ball.velocity
	game.player.turn_view(PI/2) # Production yaw setter; headless, not mouse-comfort acceptance.
	for _i in 6:await tick()
	var after: Vector3=game.ball.velocity
	var after_impulses := ordinary_impulses(writes.slice(trace_start))
	check("free roll camera90 keeps world ball direction",Vector2(before.x,before.z).normalized().dot(Vector2(after.x,after.z).normalized())>.995,{"before":xyz(before),"after":xyz(after)})
	check("camera free roll has no subsequent active dribble writes",after_impulses.is_empty(),after_impulses.size())

	await reset_episode()
	await segment("impact_warm",2.0,[KEY_W])
	stage="external_collision"
	contact=await wait_next_touch()
	check("impact probe starts from a real contact",not contact.is_empty())
	trace_start=writes.size()
	var collision_start: int=game.ball.collision_count
	var blocker := StaticBody3D.new()
	blocker.collision_layer=1
	blocker.collision_mask=4
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size=Vector3(.8,.3,.04)
	shape_node.shape=box
	blocker.add_child(shape_node)
	game.add_child(blocker)
	blocker.position=game.ball.position+Vector3(0,0,-game.ball.radius-.020-.005)
	for _i in 7:await tick()
	var collision_rows: Array=writes.slice(trace_start).filter(func(r):return r.source=="collision_response")
	check("external solid makes an actual swept collision",game.ball.collision_count>collision_start and not collision_rows.is_empty(),collision_rows.slice(0,1))
	check("external collision stays deflected during free roll",game.ball.velocity.z>.40,xyz(game.ball.velocity))
	deferred("external collision is not followed by active dribble writes",ordinary_impulses(writes.slice(trace_start)).is_empty())
	blocker.queue_free()
	await tick()

	await reset_episode()
	await segment("heavy_warm",2.0,[KEY_W])
	await segment("shift_first",.06,[KEY_W,KEY_SHIFT])
	await segment("shift_release",.07,[KEY_W])
	await segment("shift_second",.06,[KEY_W,KEY_SHIFT])
	stage="heavy_contact"
	contact=await wait_next_touch("SPRINT")
	check("double Shift makes one actual big touch",not contact.is_empty())
	if not contact.is_empty():
		before=game.ball.velocity
		trace_start=writes.size()
		await segment("heavy_sharp_right",.10,[KEY_D,KEY_SHIFT])
		after=game.ball.velocity
		check("big touch acute turn leaves ball on original world route",Vector2(before.x,before.z).normalized().dot(Vector2(after.x,after.z).normalized())>.995 and game.ball.carrier==null,{"before":xyz(before),"after":xyz(after)})
		check("big-touch free chase contains no dribble force",ordinary_impulses(writes.slice(trace_start)).is_empty())

	var impulse_groups: Dictionary={}
	for row in ordinary_impulses(writes):
		var id:=str(row.sequence) # Sequence repeats across fixtures only after same actor, not reset.
		impulse_groups[id]=int(impulse_groups.get(id,0))+1
	deferred("each ordinary touch commits one velocity impulse",impulse_groups.values().all(func(n):return n==1),impulse_groups)
	var free_rows: Array=path.filter(func(r):return r.stage in ["low","medium","fast"] and r.phase=="CONTACT" and r.plan.get("state","")=="FREE_ROLL" and not r.shoe_target.is_empty())
	check("ordinary contact explicitly enters free roll",free_rows.size()>=6,free_rows.size())
	var gaps: Array=free_rows.map(func(r):return Vector3(r.shoe_target[0],r.shoe_target[1],r.shoe_target[2]).distance_to(Vector3(r.ball[0],r.ball[1],r.ball[2]))-.11)
	gaps.sort()
	check("released shoe target separates from ball surface",not gaps.is_empty() and gaps[gaps.size()/2]>.010,gaps[gaps.size()/2] if not gaps.is_empty() else -1)
	check("no ordinary active impulse after free-roll transition",ordinary_impulses(writes).all(func(r):return r.get("plan_state","LEGACY")!="FREE_ROLL"))
	var desired_by_sequence: Dictionary={}
	var locked := true
	for row in path:
		if not row.plan.has("desired_velocity"):continue
		var id:=str(row.sequence)
		if desired_by_sequence.has(id) and desired_by_sequence[id]!=row.plan.desired_velocity:locked=false
		desired_by_sequence[id]=row.plan.desired_velocity
	check("first-contact desired result stays locked",locked and desired_by_sequence.size()>5,desired_by_sequence.size())
	var report={"label":label,"checks":checks,"deferred_checks":deferred_checks,"stages":stages,"events":events,"path":path,"velocity_writes":writes,"physics_hz":Engine.physics_ticks_per_second,"scope":"Frozen0.6.9 models and controller, 22 physical actors; AI/distant poses off. Separate reproducible initial RECEIVE fixtures for each A/B episode. Observer-only physics-write hooks. Camera uses production yaw setter; solid collision uses actual swept physics. No native GPU/comfort test.","simulated_seconds":frames/120.0}
	FileAccess.open(evidence.path_join("touchplan_"+label+".json"),FileAccess.WRITE).store_string(JSON.stringify(report))
	print("TOUCHPLAN_RESULT ",checks.filter(func(c):return c.passed).size(),"/",checks.size()," simulation_s=",frames/120.0," writes=",writes.size())
	release_inputs()
	game.ball.remove_meta("touch_trace")
	game.pause_match()
	game.shutdown_audio()
	game.queue_free()
	game=null
	for _i in 4:await process_frame
	quit(0 if checks.all(func(c):return c.passed) else 1)
