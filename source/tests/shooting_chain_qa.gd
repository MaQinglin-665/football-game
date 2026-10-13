extends "res://tests/integration_checks.gd"
## Physical fixtures; actual mouse press/hold/release; normal 22 actors and World.
var case_id := ""
var chains: Array[Dictionary] = []
var outcomes: Array[Dictionary] = []
var shot_events: Array[Dictionary] = []
var reception_events: Array[Dictionary] = []
var recorded_shot_audio: Dictionary = {}
var receive_setup: Dictionary = {}
var run_label := "baseline"
var matrix := false
var selected_cases := PackedStringArray()

func xyz(v: Vector3) -> Array: return [v.x,v.y,v.z]

func shot_geometry(p: Node3D) -> Dictionary:
	var sk: Skeleton3D = p.avatar.skeleton
	var floor_min := INF
	var length_error := 0.0
	for suffix in ["L","R"]:
		var hip := sk.get_bone_global_pose(sk.find_bone("thigh."+suffix)).origin
		var knee := sk.get_bone_global_pose(sk.find_bone("shin."+suffix)).origin
		var foot := sk.get_bone_global_pose(sk.find_bone("foot."+suffix))
		length_error = maxf(length_error,absf(hip.distance_to(knee)-sk.get_bone_rest(sk.find_bone("shin."+suffix)).origin.length()))
		length_error = maxf(length_error,absf(knee.distance_to(foot.origin)-sk.get_bone_rest(sk.find_bone("foot."+suffix)).origin.length()))
		var world := sk.global_transform*foot
		floor_min = minf(floor_min,world.origin.y+float(p.avatar._minimum_offset(suffix,world.basis.get_rotation_quaternion()))-p.avatar.global_position.y)
	return {"length_error":length_error,"boot_floor_min":floor_min}

func observe(count: int, tag: String) -> void:
	for _i in count:
		await ticks(1)
		var p: Node3D = game.player
		# The released audio history is a bounded64-record ring. Record actual
		# local shot records as they arrive; a saved array index can point past
		# the end once the normal22 actors have already filled that ring.
		var ring_counts: Dictionary = {}
		for record in game.services.audio.recent_mix:
			if record.get("cue","")!="shot" or record.get("actor_id",-1)!=p.get_instance_id(): continue
			var audio_id := String(record.get("event_id",""))
			ring_counts[audio_id] = int(ring_counts.get(audio_id,0))+1
			if not recorded_shot_audio.has(audio_id): recorded_shot_audio[audio_id] = {"case":case_id,"record":record.duplicate(true),"max_duplicates":0}
		for audio_id in ring_counts:
			recorded_shot_audio[audio_id].max_duplicates = maxi(int(recorded_shot_audio[audio_id].max_duplicates),int(ring_counts[audio_id]))
		var f: FootballFootAction = p.foot
		chains.append({"case":case_id,"frame":frames,"tag":tag,"ball":xyz(game.ball.position),"velocity":xyz(game.ball.velocity),"relative":xyz(p.global_basis.inverse()*(game.ball.position-p.position)),"actor":xyz(p.position),"owned":game.ball.carrier==p,"input_charge":game.input_bridge.charge_preview.duplicate(),"kind":f.kind,"phase":FootballFootAction.Phase.keys()[f.phase],"elapsed":f.elapsed,"hit":f.hit,"result":f.last_result,"buffer":f.buffer.get("kind",""),"cooldown":p.action_cooldown,"side":f.side,"surface":f.surface,"socket":xyz(f.actual_contact.get("point",Vector3.ZERO)),"valid":f.actual_contact.get("valid",false),"reach_error":f.actual_contact.get("reach_error",-1.0),"target":xyz(f.contact_target),"socket_ball_gap":(f.actual_contact.get("point",Vector3.ZERO) as Vector3).distance_to(game.ball.position),"weight_shift":xyz(p.avatar.weight_shift),"reason":f.get("contact_failure") if "contact_failure" in f else "","support":p.avatar.planted_support.duplicate(),"body":p.avatar.shooting_motion.debug.duplicate() if "shooting_motion" in p.avatar else {},"geometry":shot_geometry(p) if f.kind=="SHOT" else {}})

func prepare_owned() -> bool:
	var reception_start := reception_events.size()
	# Isolate staged physical starting conditions between independent cases.
	# Use the game's normal pause/resume path while relocating bodies, so a
	# sweep cannot run halfway through that relocation. No ownership/rule
	# state/contact is injected, and the whole gesture runs after live resume.
	game.pause_match()
	fixture()
	# Flush staged physical transforms before the next engine sweep. Old
	# blocking-body transforms must not push the player out of the new start.
	for actor in game.players: actor.force_update_transform()
	game.ball.force_update_transform()
	await physics_frame
	await physics_frame
	game.resume_match()
	# A fixture relocates the physical actor, while the motion layer retains
	# real previous foot anchors/acceleration. Settle the new pose before the
	# raw receive key, rather than starting a swing from the previous case's
	# remote footprint. Ownership is still established by an actual receive.
	await observe(12,"fixture_settle")
	receive_setup = {"protocol":"normal pause / relocate / synchronize / live receive","phase_before_receive":game.phase,"player":xyz(game.player.position),"ball":xyz(game.ball.position),"gap_before_receive":game.flat_distance(game.player.position,game.ball.position),"normal_ai":game.ai_enabled,"world_actors":game.physics_world.actors.size()}
	key(KEY_SPACE,true)
	await ticks(1)
	key(KEY_SPACE,false)
	await ticks(31)
	receive_setup["events"] = reception_events.slice(reception_start)
	receive_setup["owned_after_receive"] = game.ball.carrier==game.player
	return game.ball.carrier==game.player and not receive_setup.events.is_empty() and game.phase==game.Phase.PLAY and game.ai_enabled and game.physics_world.actors.size()==22

func shot_case(spec: Dictionary) -> void:
	case_id = spec.id
	var received := await prepare_owned()
	var p: Node3D = game.player
	# Reposition only physical fixture before the real gesture, after actual
	# shoe reception established ownership. Neither event nor ownership is faked.
	game.ball.position = p.position+Vector3(float(spec.get("x",0)),.111,-float(spec.get("z",.58)))
	game.ball.previous_position = game.ball.position
	game.ball.velocity = Vector3(float(spec.get("vx",0)),0,-float(spec.get("vz",0)))
	game.ball.spin_rads = Vector3.ZERO
	if spec.get("yaw",0.0)!=0: p.turn_view(float(spec.yaw))
	var intent_start: int = game.input_bridge.last_sequence
	var contacts_start: int = shot_events.size()
	var shots_before: int = game.stats.shots
	var audio_start: int = game.services.audio.recent_mix.size()
	var trace_start: int = Engine.get_physics_frames()
	var preparation: Dictionary = {"receive":receive_setup.duplicate(true)}
	if spec.get("move",false):
		key(KEY_CTRL,true)
		key(KEY_W,true)
		await observe(int(spec.get("move_ticks",36)),"close_run")
	if spec.get("knock_chase",false):
		key(KEY_SHIFT,true)
		key(KEY_W,true)
		var knocked := false
		for _i in 100:
			await observe(1,"knock")
			if game.ball.last_dribbler==p and game.ball.carrier!=p:
				knocked = true
				break
		key(KEY_SHIFT,false)
		var reacquired := false
		for _i in 180:
			await observe(1,"chase")
			if game.ball.carrier==p:
				reacquired = true
				break
		preparation.merge({"actual_knocked_free":knocked,"actual_reception_after_chase":reacquired})
	if spec.get("curve",false): key(KEY_Z,true)
	if spec.get("curve_right",false): key(KEY_X,true)
	if spec.get("high_shot",false):
		for _i in 6:
			mouse(MOUSE_BUTTON_WHEEL_UP,true)
			await ticks(1)
			mouse(MOUSE_BUTTON_WHEEL_UP,false)
	mouse(MOUSE_BUTTON_LEFT,true)
	await observe(int(spec.hold),"hold")
	var before_release_shots: int = game.stats.shots-shots_before
	if spec.get("cancel_middle",false):
		mouse(MOUSE_BUTTON_MIDDLE,true)
		await observe(1,"cancel_middle")
		mouse(MOUSE_BUTTON_MIDDLE,false)
	if spec.get("cancel_right",false):
		mouse(MOUSE_BUTTON_RIGHT,true)
		await observe(1,"cancel_right")
		mouse(MOUSE_BUTTON_RIGHT,false)
	if spec.get("focus_loss",false):
		game.input_bridge.focused = false
		game.sync_input_context()
		await observe(1,"focus_loss")
		game.input_bridge.focused = true
		game.sync_input_context()
	if spec.get("escape",false):
		# Deliberately out of reach at release: fail without a remote impulse.
		game.ball.velocity = p.facing*5.0
		game.ball.position = p.position+p.facing*1.20+Vector3.UP*.111
		game.ball.previous_position = game.ball.position
	if spec.get("pause",false): game.pause_match()
	if spec.get("block",false): game.agents[0].position = p.position+p.facing*.30
	mouse(MOUSE_BUTTON_LEFT,false)
	if spec.get("escape_queued",false):
		await observe(2,"queued_before_escape")
		game.ball.position = p.position+p.facing*1.60+Vector3.UP*.111
		game.ball.previous_position = game.ball.position
		game.ball.velocity = Vector3.ZERO
	if spec.get("move",false) or spec.get("knock_chase",false):
		key(KEY_W,false)
		key(KEY_CTRL,false)
	if spec.get("double",false):
		await observe(5,"first_release")
		mouse(MOUSE_BUTTON_LEFT,true)
		await observe(6,"repeat_hold")
		mouse(MOUSE_BUTTON_LEFT,false)
	if spec.get("pause_windup",false):
		await observe(5,"windup_before_pause")
		game.pause_match()
		await observe(15,"pause_windup")
		game.resume_match()
	if spec.get("cancel_committed",false):
		await observe(5,"windup_before_cancel")
		mouse(MOUSE_BUTTON_MIDDLE,true)
		await observe(1,"committed_cancel")
		mouse(MOUSE_BUTTON_MIDDLE,false)
	await observe(85,"release")
	if spec.get("pause",false):
		game.resume_match()
		await observe(40,"resume")
	key(KEY_Z,false)
	key(KEY_X,false)
	if spec.get("high_shot",false):
		for _i in 6:
			mouse(MOUSE_BUTTON_WHEEL_DOWN,true)
			await ticks(1)
			mouse(MOUSE_BUTTON_WHEEL_DOWN,false)
	var intents: Array = game.input_bridge.traces.filter(func(e):return int(e.sequence)>intent_start and String(e.action).begins_with("shoot_"))
	var events := shot_events.slice(contacts_start)
	var hits := events.filter(func(e):return e.success)
	var observed_audio: Array = recorded_shot_audio.values().filter(func(e):return e.case==case_id)
	var cues: Array = observed_audio.map(func(e):return e.record)
	var expected := int(spec.get("expected",0 if spec.get("escape",false) or spec.get("pause",false) else 1))
	var stages: Array = p.foot.action_trace.filter(func(e):return int(e.physics_frame)>=trace_start) if "action_trace" in p.foot else []
	outcomes.append({"id":case_id,"received":received,"preparation":preparation,"intents":intents,"stages":stages,"events":events,"stats_delta":game.stats.shots-shots_before,"success":hits.size()==1 and game.stats.shots-shots_before==1,"expected_shots":expected,"shot_cues":cues,"rejected_commands":game.input_bridge.rejected_commands,"final_result":p.foot.last_result,"final_ball":xyz(game.ball.position),"final_velocity":xyz(game.ball.velocity)})
	check(case_id+" real shot count",received and hits.size()==expected and game.stats.shots-shots_before==expected,{"expected":expected,"shots":game.stats.shots-shots_before,"failures":events.filter(func(e):return not e.success).map(func(e):return e.reason),"preparation":preparation})
	check(case_id+" no shot on hold",before_release_shots==0)
	check(case_id+" exactly one sound per real impulse",cues.size()==expected and observed_audio.all(func(e):return int(e.max_duplicates)==1),{"expected":expected,"cue_count":cues.size(),"observed":observed_audio})
	check(case_id+" contact-only sound",events.all(func(e):return (e.audio_received and e.audio_latest.get("cue","")=="shot" and e.audio_latest.get("actor_id",-1)==p.get_instance_id()) if e.success else not e.audio_received))
	var geometry_rows: Array = chains.filter(func(row):return row.case==case_id and not row.geometry.is_empty())
	check(case_id+" actual World leg lengths/floor/support",geometry_rows.all(func(row):return row.geometry.length_error<.00001 and row.geometry.boot_floor_min>=.0049 and (not p.avatar.has_signal("action_pose_sampled") or row.body.get("body_sampled_by_hook",false))) and hits.all(func(e):return e.support_valid))
	if spec.has("expected_failure"):
		check(case_id+" accepted swing reports one physical miss",stages.any(func(s):return s.stage=="inputaccepted") and events.size()==1 and not events[0].success and events[0].reason==String(spec.expected_failure) and not events[0].audio_received)
	print("SHOT_CASE ",case_id," received=",received," shots=",game.stats.shots-shots_before," result=",p.foot.last_result)

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): run_label = arg.trim_prefix("--label=")
		if arg=="--matrix": matrix = true
		if arg.begins_with("--cases="): selected_cases = arg.trim_prefix("--cases=").split(",")
	game = load("res://scenes/match.tscn").instantiate()
	game.test_mode = true
	root.add_child(game)
	game.contact_hub.contact_resolved.connect(func(e: Dictionary):
		if e.actor==game.player and e.action=="RECEIVE" and e.success: reception_events.append({"serial":e.serial,"frame":frames,"point":xyz(e.point),"sequence":e.sequence,"kind":e.kind,"success":e.success}))
	game.contact_hub.contact_resolved.connect(func(e: Dictionary):
		if e.actor==game.player and e.action=="SHOT": shot_events.append({"case":case_id,"frame":frames,"success":e.success,"kind":e.kind,"sequence":e.sequence,"point":xyz(e.point),"before":xyz(e.before_velocity),"after":xyz(e.after_velocity),"impulse":xyz(e.impulse),"spin":xyz(game.ball.spin_rads),"reason":e.get("failure_reason",""),"reach_error":e.get("reach_error",-1.0),"support_valid":game.player.avatar.planted_support.get("valid",false),"audio_received":game.services.audio._impact_seen.has("impact-foot:%d:%d" % [game.player.get_instance_id(),int(e.get("action_sequence",0))]),"audio_latest":game.services.audio.recent_mix.back().duplicate() if not game.services.audio.recent_mix.is_empty() else {}}))
	game.start_match(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	for _i in 2400:
		await ticks(1)
		if game.is_restart_taker(game.player):break
	key(KEY_Q,true)
	await ticks(50)
	key(KEY_Q,false)
	await ticks(650)
	check("normal kickoff enters live play",game.phase==game.Phase.PLAY)
	var specs := [
		{"id":"still_center_short","hold":6},
		{"id":"still_center_long","hold":108},
		{"id":"still_close","hold":42,"z":.38},
		{"id":"still_left","hold":42,"x":-.28},
		{"id":"still_right","hold":42,"x":.28},
		{"id":"slow_roll","hold":12,"vz":.65},
		{"id":"edge_forward","hold":24,"z":.82},
		{"id":"close_turn","hold":12,"yaw":.5},
		{"id":"close_run_release","hold":18,"move":true},
		{"id":"curve_long","hold":108,"curve":true},
		{"id":"escape_at_release","hold":36,"escape":true},
		{"id":"pause_release","hold":36,"pause":true}
	]
	if matrix:
		var basic := specs.slice(0,10)
		for repetition in [2,3]:
			for spec in basic:
				var repeat_spec: Dictionary = spec.duplicate()
				repeat_spec.id = spec.id+"_r%d" % repetition
				specs.append(repeat_spec)
		specs.append_array([
			{"id":"busy_quick_queue","hold":6,"move":true,"move_ticks":6},
			{"id":"knock_then_chase","hold":6,"knock_chase":true},
			{"id":"double_click","hold":6,"double":true},
			{"id":"cancel_middle_held","hold":36,"cancel_middle":true,"expected":0},
			{"id":"cancel_right_held","hold":36,"cancel_right":true,"expected":0},
			{"id":"focus_loss_held","hold":36,"focus_loss":true,"expected":0},
			{"id":"pause_committed_windup","hold":6,"pause_windup":true,"expected":0},
			{"id":"middle_after_commit","hold":6,"cancel_committed":true},
			{"id":"body_blocks_release","hold":6,"block":true,"expected":0},
			{"id":"high_shot_long","hold":108,"high_shot":true},
			{"id":"curve_right_long","hold":108,"curve_right":true},
			{"id":"queued_ball_escapes","hold":6,"move":true,"move_ticks":6,"escape_queued":true,"expected":0},
			{"id":"wide_unreachable","hold":6,"x":.85,"z":.10,"expected":0,"expected_failure":"foot_unreachable"},
			{"id":"ball_escapes_windup","hold":6,"vz":3.0,"expected":0,"expected_failure":"possession_changed"}
		])
	if not selected_cases.is_empty(): specs = specs.filter(func(spec):return selected_cases.has(spec.id))
	for spec in specs: await shot_case(spec)
	var passed: int = checks.filter(func(c):return c.passed).size()
	var report := {"label":run_label,"native":native,"passed":passed,"total":checks.size(),"outcomes":outcomes,"chains":chains,"checks":checks,"scope":"120Hz actual mouse input on integrated0.6.5-shot C shape/full_body_01/Shift/ImpactAudioB; real shoe reception, 22 normal AI, single physics World, rules unchanged. Independent physical initial conditions staged while normally paused, synchronized, then live resume before every actual receive/shot gesture. No contact/impulse/ownership injected. Display mode recorded by native flag; synthetic engine input, no human feel/FPS claim."}
	FileAccess.open(evidence.path_join("shooting_chain_"+run_label+".json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	game.pause_match()
	game.shutdown_audio()
	OS.delay_msec(100)
	game.queue_free()
	game = null
	for _i in 4: await process_frame
	print("SHOOT_CHAIN ",passed,"/",checks.size())
	quit(0 if passed==checks.size() else 1)
