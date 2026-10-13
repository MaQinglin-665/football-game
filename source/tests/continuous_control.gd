extends "res://tests/integration_checks.gd"
## Isolated continuous control diagnostic: real input, real feet, sole World.
## One spatial/LIVE fixture before acquisition, no ball/actor reset afterwards.
var stage := "initial_receive"
var path: Array[Dictionary] = []
var stages: Array[Dictionary] = []
var touch_events: Array[Dictionary] = []
var held_keys: Array[int] = []
var bone_first := {}
var label := "baseline_B"
var sequence := "full"

func xyz(v: Vector3) -> Array: return [v.x,v.y,v.z]

func input_keys(keys: Array) -> void:
	for code in held_keys:
		if not keys.has(code): key(code,false)
	for code in keys:
		if not held_keys.has(code): key(code,true)
	held_keys.clear()
	for code in keys: held_keys.append(code)

func percentile(values: Array, percent: float) -> float:
	if values.is_empty(): return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return float(sorted[int(clampf(ceil((sorted.size()-1)*percent),0,sorted.size()-1))])

func sample_tick() -> void:
	var actor: Node3D = game.player
	var skeleton: Skeleton3D = actor.avatar.skeleton
	var bone_motion := {}
	for bone in ["hips","spine","chest","upper_arm.L","upper_arm.R","thigh.L","thigh.R","foot.L","foot.R"]:
		var pose := skeleton.get_bone_pose_rotation(skeleton.find_bone(bone))
		if not bone_first.has(bone): bone_first[bone] = pose
		bone_motion[bone] = rad_to_deg((bone_first[bone] as Quaternion).angle_to(pose))
	path.append({"stage":stage,"seconds":frames/120.0,"ball":xyz(game.ball.position),"ball_velocity":xyz(game.ball.velocity),"actor":xyz(actor.position),"actor_velocity":xyz(actor.velocity),"actor_yaw":actor.rotation.y,"gap_m":game.flat_distance(game.ball.position,actor.position),"relative":xyz(actor.global_basis.inverse()*(game.ball.position-actor.position)),"relative_speed_mps":Vector2(game.ball.velocity.x-actor.velocity.x,game.ball.velocity.z-actor.velocity.z).length(),"owned":game.ball.carrier==actor,"control_mode":game.ball.control_mode,"foot_kind":actor.foot.kind,"foot_phase":actor.foot.phase,"hit":actor.foot.hit,"reach_error":actor.foot.actual_contact.get("reach_error",-1.0),"socket":xyz(actor.foot.actual_contact.get("point",Vector3.ZERO)),"body_collisions":game.ball.body_collision_count,"bone_delta_deg":bone_motion,"motion":actor.avatar.get_motion_debug()})

func segment(name: String, seconds: float, keys: Array) -> void:
	stage = name
	var start_path := path.size()
	var start_ball: Vector3 = game.ball.position
	var start_actor: Vector3 = game.player.position
	var start_events := touch_events.size()
	input_keys(keys)
	for _i in roundi(seconds*120):
		await ticks(1)
		if frames%3==0: sample_tick()
	var rows := path.slice(start_path)
	var gaps := rows.map(func(r): return r.gap_m)
	var relative_speeds := rows.map(func(r): return r.relative_speed_mps)
	var player_speeds := rows.map(func(r): return Vector2(r.actor_velocity[0],r.actor_velocity[2]).length())
	var ball_speeds := rows.map(func(r): return Vector2(r.ball_velocity[0],r.ball_velocity[2]).length())
	var stage_events := touch_events.slice(start_events)
	stages.append({"stage":name,"seconds":seconds,"samples":rows.size(),"gap_p50":percentile(gaps,.5),"gap_p95":percentile(gaps,.95),"gap_max":percentile(gaps,1.0),"relative_speed_p95":percentile(relative_speeds,.95),"actor_speed_p50":percentile(player_speeds,.5),"ball_speed_p50":percentile(ball_speeds,.5),"owned_fraction":float(rows.filter(func(r): return r.owned).size())/maxi(1,rows.size()),"ball_travel_m":game.flat_distance(game.ball.position,start_ball),"actor_travel_m":game.flat_distance(game.player.position,start_actor),"ball_final_speed":Vector2(game.ball.velocity.x,game.ball.velocity.z).length(),"final_gap":game.flat_distance(game.ball.position,game.player.position),"real_contacts":stage_events.filter(func(e):return e.success).size(),"failed_contact_attempts":stage_events.filter(func(e):return not e.success).size()})

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
		if arg.begins_with("--sequence="): sequence = arg.trim_prefix("--sequence=")
	game = load("res://scenes/match.tscn").instantiate()
	game.test_mode = true
	root.add_child(game)
	await ticks(3)
	game.ai_enabled = false
	game.services.rules.state = game.Rules.State.LIVE
	game.services.rules.restart.clear()
	game.set_phase(game.Phase.PLAY)
	game.services.configuration.half_seconds = 600.0
	game.contact_hub.contact_resolved.connect(func(e: Dictionary):
		if e.actor==game.player: touch_events.append({"stage":stage,"seconds":frames/120.0,"action":e.action,"surface":e.surface,"success":e.success,"before":xyz(e.before_velocity),"after":xyz(e.after_velocity),"point":xyz(e.point),"gap_m":game.flat_distance(game.player.position,game.ball.position),"reach_error":e.get("reach_error",-1.0)}))
	fixture()
	game.player.position.z = 30.0
	game.ball.position = Vector3(0,.113,29.42)
	game.ball.previous_position = game.ball.position
	key(KEY_SPACE,true)
	await ticks(1)
	key(KEY_SPACE,false)
	await ticks(45)
	check("initial acquisition is actual RECEIVE contact",game.ball.carrier==game.player and touch_events.any(func(e): return e.success and e.action=="RECEIVE"))
	var sequence_start_frame: int = frames
	await segment("near_forward",5.0,[KEY_W])
	await segment("near_release_stop",1.5,[])
	if sequence=="near30":
		await segment("near_left",1.5,[KEY_A])
		await segment("left_stop",.5,[])
		await segment("near_right",3.0,[KEY_D])
		await segment("right_stop",.5,[])
		await segment("near_left_again",3.0,[KEY_A])
		await segment("left_again_stop",.5,[])
		await segment("near_diagonal_left",2.0,[KEY_W,KEY_A])
		await segment("near_diagonal_right",2.0,[KEY_W,KEY_D])
		await segment("near_forward_again",3.0,[KEY_W])
		await segment("last_stop",1.5,[])
		await segment("last_left",1.5,[KEY_A])
		await segment("final_stop",1.0,[])
	else:
		await full_tier_sequence()
	if sequence=="near30":
		check("continuous sequence keeps ownership without reset",path.all(func(r): return r.owned),stages.map(func(r): return {"stage":r.stage,"owned":r.owned_fraction}))
		check("near ball stays within 0.80m for whole sequence",path.all(func(r): return r.gap_m<=.80),percentile(path.map(func(r):return r.gap_m),1.0))
		var moving := stages.filter(func(r): return r.stage.begins_with("near_") and r.stage!="near_release_stop" or r.stage=="last_left")
		check("every direction uses multiple real touches and displacement",moving.all(func(r): return r.real_contacts>=3 and r.actor_travel_m>.5),moving)
		var resting := stages.filter(func(r): return r.stage in ["near_release_stop","last_stop","final_stop"])
		check("all long releases cushion and stop close",resting.all(func(r):return r.ball_final_speed<.08 and r.final_gap<.55 and r.real_contacts>=1),resting)
		check("contact reach uses real shoe tolerance",touch_events.filter(func(e):return e.success).all(func(e):return e.reach_error>=0 and e.reach_error<=.035))
		check("no heavy touch from plain movement",game.input_bridge.traces.filter(func(i):return i.action=="push_ball" and i.phase=="commit").is_empty())
	else:
		var sustained := stages.filter(func(r):return r.stage in ["near_forward","near_left","near_right","near_left_again","near_diagonal_left","near_diagonal_right","near_forward_again","shift_hold_dribble","shift_release_near"])
		check("ordinary and held-Shift stages remain controlled",sustained.all(func(r):return r.owned_fraction==1.0 and r.gap_max<.80 and r.real_contacts>=2),sustained.map(func(r):return {"stage":r.stage,"gap_max":r.gap_max,"contacts":r.real_contacts}))
		var running: Dictionary = stages.filter(func(r):return r.stage=="shift_hold_dribble")[0]
		# Include accelerating into the held tier, not only a steady-speed
		# sample. Verify a distinct faster controlled pace below chase speed.
		check("held Shift is continuous dribble at faster pace",running.actor_speed_p50>=4.2 and running.actor_speed_p50<=5.6 and touch_events.filter(func(e):return e.stage=="shift_hold_dribble" and e.action=="SPRINT").is_empty(),running)
		var pushes: Array = game.input_bridge.traces.filter(func(i):return i.action=="push_ball" and i.phase=="commit")
		var big_hits := touch_events.filter(func(e):return e.action=="SPRINT" and e.success)
		check("double Shift gives one commit and one actual instep contact",pushes.size()==1 and big_hits.size()==1 and big_hits[0].reach_error<=.035,{"commits":pushes.size(),"actual_contacts":big_hits})
		check("heavy touch creates space and a free-ball chase",path.any(func(r):return r.stage=="double_chase" and not r.owned and r.gap_m>.70))
		var final: Dictionary = stages.filter(func(r):return r.stage=="after_chase_stop")[0]
		check("chase can recover and stop using actual shoes",final.owned_fraction==1.0 and final.final_gap<.60 and final.ball_final_speed<.08 and final.real_contacts>=1,final)
	var bone_max := {}
	for row in path:
		for bone in row.bone_delta_deg: bone_max[bone] = maxf(float(bone_max.get(bone,0.0)),float(row.bone_delta_deg[bone]))
	var report := {"label":label,"sequence":sequence,"scope":"Isolated continuous control. Rules set LIVE once before a true RECEIVE. 22 bodies and real skeletal feet/World/grass physics; AI disabled. No position, velocity or ownership reset during sequence. Not human feel/full-match acceptance.","checks":checks,"stages":stages,"contacts":touch_events,"path":path,"bone_max_delta_deg":bone_max,"final_ball":xyz(game.ball.position),"final_actor":xyz(game.player.position),"push_commit_count":game.input_bridge.traces.filter(func(i): return i.action=="push_ball" and i.phase=="commit").size()}
	report["sequence_simulated_seconds"] = (frames-sequence_start_frame)/120.0
	report["requested_stage_seconds"] = stages.reduce(func(total,r):return total+r.seconds,0.0)
	FileAccess.open(evidence.path_join("continuous_%s.json" % label),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	for row in stages: print("STAGE ",JSON.stringify(row))
	print("BONES ",JSON.stringify(bone_max))
	release_inputs()
	game.pause_match()
	game.shutdown_audio()
	game.queue_free()
	game = null
	for _i in 4: await process_frame
	quit(0 if checks.all(func(c):return c.passed) else 1)

func full_tier_sequence() -> void:
	await segment("near_left",.8,[KEY_A])
	await segment("left_stop",.4,[])
	await segment("near_right",1.6,[KEY_D])
	await segment("right_stop",.4,[])
	await segment("near_left_again",.8,[KEY_A])
	await segment("left_again_stop",.6,[])
	await segment("near_diagonal_left",1.0,[KEY_W,KEY_A])
	await segment("near_diagonal_right",1.0,[KEY_W,KEY_D])
	await segment("near_forward_again",2.0,[KEY_W])
	await segment("shift_hold_dribble",3.0,[KEY_W,KEY_SHIFT])
	await segment("shift_release_near",1.5,[KEY_W])
	await segment("before_double_stop",1.0,[])
	await segment("double_first_press",.06,[KEY_W,KEY_SHIFT])
	await segment("double_first_release",.07,[KEY_W])
	await segment("double_second_press",.06,[KEY_W,KEY_SHIFT])
	await segment("double_chase",2.5,[KEY_W,KEY_SHIFT])
	await segment("after_chase_stop",2.0,[])
