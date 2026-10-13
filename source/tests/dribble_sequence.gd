extends "res://tests/integration_checks.gd"
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

func _initialize() -> void:
	AudioServer.set_bus_mute(0,true)
	super._initialize()

func inputs(keys: Array) -> void:
	for code in held_keys:
		if not keys.has(code): key(code,false)
	for code in keys:
		if not held_keys.has(code): key(code,true)
	held_keys.clear()
	for code in keys: held_keys.append(code)

func tick() -> void:
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
	for _i in roundi(seconds*120): await tick()
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
	stage="shot_release"
	mouse(MOUSE_BUTTON_LEFT,false)
	for _i in 65:await tick()
	check("continuous control chain ends in one real shot",game.stats.shots==shots_before+1 and touch_events.filter(func(e):return e.success and e.action=="SHOT").size()==1)
	check("no restart or scoring fixture occurred",path.all(func(r):return r.epoch==fixture_epoch))
	check("all successful contact reports keep real shoe tolerance",touch_events.filter(func(e):return e.success).all(func(e):return e.reach_error>=0 and e.reach_error<=.035 or e.action=="SPRINT" and e.reach_error>=0 and e.reach_error<=.035))
	check("continuous touch cooldown is consumed only at the first contact",cooldown_renewals==0,cooldown_renewals)
	var report := {"label":label,"scope":"One initial LIVE/spatial fixture and actual RECEIVE. Real keys; low Ctrl, medium no Shift, fast held Shift, then double Shift chase and retreat. 22 physical bodies, AI decisions and distant agent pose updates off; real human skeletal contacts. No actor/ball position, velocity or ownership resets after acquisition. First-person projection is numeric and does not prove mesh visibility/occlusion/comfort. Headless only.","checks":checks,"stages":stages,"path":path,"contacts":touch_events,"simulated_seconds":frames/120.0,"cooldown_renewals":cooldown_renewals}
	FileAccess.open(evidence.path_join("dribble_"+label+".json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	for result in stages:print("DRIBBLE ",JSON.stringify(result))
	release_inputs()
	game.pause_match()
	game.shutdown_audio()
	game.queue_free()
	game=null
	for _i in 4:await process_frame
	quit(0 if checks.all(func(c):return c.passed) else 1)
