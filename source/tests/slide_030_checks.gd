extends "res://tests/integration_checks.gd"
## Short real six-actor fixtures; no renderer, native input or full-match claim.
var mobility: Node
var slide_events: Array[Dictionary] = []
var trip_events: Array[Dictionary] = []

func reset_case() -> void:
	release_inputs()
	for code in [KEY_V,KEY_J,KEY_B]: key(code,false)
	mobility.cancel_inputs("test_fixture")
	mobility.slide_phase = "IDLE"
	mobility.pending_body_fall = ""
	mobility.boot_shape.disabled = true
	mobility.low_body.state = "IDLE"
	mobility.low_body.weight = 0.0
	mobility.low_body.apply_volume()
	mobility.phase = "GROUNDED"
	mobility.crouch = 0.0
	mobility.landing_left = 0.0
	mobility.header_used = false
	game.services.rules.state = game.Rules.State.LIVE
	game.services.rules.restart.clear()
	game.set_phase(game.Phase.PLAY)
	fixture()
	for i in game.agents.size():
		var a: Node = game.agents[i]
		a.pending_kick.clear()
		a.foot.cancel()
		if is_instance_valid(a.down_state):
			a.down_state.state = "IDLE"
			a.down_state.weight = 0.0
			a.down_state.apply_volume()
		a.position = Vector3(-10 if i%2 else 10,.002,-14+5*i)
		a.target = a.position
		a.velocity = Vector3.ZERO
	game.player.stamina = 100
	game.ball.position = Vector3(10,.113,8)
	game.ball.previous_position = game.ball.position
	game.input_bridge.adapter.router.reset("test_fixture")
	game.input_bridge.adapter.router._cooldowns.clear()
	await ticks(8)

func start_slide() -> void:
	key(KEY_V,true)
	await ticks(1)
	key(KEY_V,false)
	for i in 24:
		if mobility.slide_phase == "CONTACT": break
		await ticks(1)

func put_ball(point: Vector3, motion := Vector3.ZERO) -> void:
	game.ball.position = point
	game.ball.previous_position = point
	game.ball.velocity = motion
	game.ball.pickup_block = 1

func flight(with_slide: bool) -> Dictionary:
	await reset_case()
	put_ball(Vector3(8,3,8),Vector3(1,1,-.5))
	if with_slide: key(KEY_V,true)
	await ticks(1)
	if with_slide: key(KEY_V,false)
	await ticks(160)
	return {"position":game.ball.position,"velocity":game.ball.velocity}

func roof_at(height: float) -> StaticBody3D:
	var roof := StaticBody3D.new()
	roof.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2,.2,2)
	shape.shape = box
	roof.add_child(shape)
	game.add_child(roof)
	roof.position = game.player.position+Vector3.UP*height
	return roof

func run() -> void:
	game = load("res://scenes/training_3v3.tscn").instantiate()
	game.test_mode = true
	root.add_child(game)
	mobility = game.player.interaction
	game.ai_enabled = false
	mobility.action_event.connect(func(e: Dictionary):
		if e.get("action","")=="SLIDE_TACKLE": slide_events.append(e.duplicate())
		if e.get("action","")=="LEG_CHALLENGE": trip_events.append(e.duplicate()))
	await ticks(6)
	await reset_case()
	check("V existing binding enabled, J/B no input conflicts; six actors/one120HzWorld",mobility.input_conflicts.is_empty() and game.input_bridge.capabilities.tackle_slide and binding("ff_slide",KEY_V) and binding("ff_interaction_jump",KEY_J) and binding("ff_interaction_crouch",KEY_B) and game.physics_world.actors.size()==6 and Engine.physics_ticks_per_second==120)
	var attempts: int = mobility.slide_attempts
	var launches: int = mobility.launch_count
	key(KEY_V,true)
	await ticks(1)
	var id: String = mobility.slide_id
	check("slide spends stamina and cooldown immediately",game.player.stamina<=82.1 and game.player.tackle_cooldown>1.8,{"stamina":game.player.stamina,"cooldown":game.player.tackle_cooldown})
	var phases: Array = []
	var root_low := INF
	var before_jump: int = mobility.jumps
	for i in 250:
		await ticks(1)
		if not mobility.slide_phase in phases: phases.append(mobility.slide_phase)
		root_low = minf(root_low,game.player.position.y)
		if i%8==0: key(KEY_V,true)
		if i==18: key(KEY_J,true); key(KEY_B,true)
	check("V repeat launches once and runs prepare/contact/recover",mobility.slide_attempts==attempts+1 and mobility.launch_count==launches+1 and "PREPARE" in phases and "CONTACT" in phases and "RECOVER" in phases,{"id":id,"phases":phases})
	check("protected J/B cannot replay after slide",mobility.jumps==before_jump and mobility.crouch<.001)
	check("empty slide safely gets up and preserves origin ground support",mobility.low_body.state=="IDLE" and mobility.permits_foot_action() and not mobility._shapes[0].node.disabled and root_low>-.01,{"root_low":root_low,"state":mobility.low_body.state})
	check("camera recovers without forced roll",game.player.head.position.y>1.45 and is_zero_approx(game.player.head.rotation.z))
	await reset_case()
	key(KEY_V,true)
	await ticks(1)
	key(KEY_V,false)
	launches=mobility.launch_count
	mouse(MOUSE_BUTTON_MIDDLE,true);mouse(MOUSE_BUTTON_MIDDLE,false)
	await ticks(4)
	check("prepare cancel does not launch and restores original shapes",mobility.launch_count==launches and mobility.slide_phase=="IDLE" and not mobility.low_body.blocked())
	await reset_case()
	await start_slide()
	var direction: Vector3 = mobility.slide_direction
	game.player.turn_view(.70)
	await ticks(2)
	check("view yaw free while slide direction locked",absf(game.player.rotation.y-.70)<.001 and mobility.slide_direction==direction)
	mouse(MOUSE_BUTTON_MIDDLE,true);mouse(MOUSE_BUTTON_MIDDLE,false)
	await ticks(2)
	check("launched cancellation spends recovery",mobility.slide_phase=="RECOVER")
	await ticks(220)
	check("cancelled slide exits recovery",mobility.permits_foot_action())
	var control: Dictionary = await flight(false)
	var swing: Dictionary = await flight(true)
	check("remote slide cannot change ball trajectory",(control.position as Vector3).distance_to(swing.position)<.00001 and (control.velocity as Vector3).distance_to(swing.velocity)<.00001)
	await reset_case()
	await start_slide()
	var hits: int = mobility.slide_hits
	put_ball(mobility._boot_center()+mobility.slide_direction*.155)
	await ticks(3)
	check("actual final TOE overlap makes one bounded physical contact",mobility.slide_hits==hits+1 and slide_events.back().separation<=mobility.BOOT_RADIUS+game.ball.radius+.009 and (slide_events.back().impulse as Vector3).length()<=3.601,slide_events.back() if mobility.slide_hits>hits else {"boot":mobility._boot_center(),"ball":game.ball.position,"socket":mobility._socket()})
	if mobility.slide_hits>hits:
		var event: Dictionary = slide_events.back()
		var v: Vector3 = game.ball.velocity
		for i in 6: game.player.resolve_interaction_ball_contact(game.ball,event.point)
		check("same action contact settles once and reaches rules",game.ball.velocity==v and slide_events.filter(func(e):return e.action_id==event.action_id).size()==1 and game.services.rules.last_touch.get("kind")=="slide_tackle")
	await reset_case()
	await start_slide()
	hits = mobility.slide_hits
	put_ball(mobility._boot_center()+mobility.slide_direction*.37+Vector3.UP*.025,-mobility.slide_direction*.8)
	await ticks(13)
	check("moving real boot and ball intersect",mobility.slide_hits==hits+1,slide_events.back() if mobility.slide_hits>hits else {"boot":mobility._boot_center(),"ball":game.ball.position,"phase":mobility.slide_phase})
	await reset_case()
	await start_slide()
	hits=mobility.slide_hits
	put_ball(mobility._boot_center()+Vector3.UP*.70)
	await ticks(30)
	check("high ball never remotely pulled into slide",mobility.slide_hits==hits)
	await reset_case()
	var other: Node = game.agents.filter(func(a):return a.team!=game.player.team and not a.is_goalkeeper)[0]
	other.position = game.player.position+Vector3(0,0,-2.10)
	other.target = other.position
	other.velocity = Vector3.ZERO
	other.foot.cancel()
	await ticks(8)
	put_ball(Vector3(.145,.113,6.65))
	hits=mobility.slide_hits
	var trip_start: int = mobility.leg_hits
	await start_slide()
	await ticks(48)
	check("actual boot-shin crossing reports victim trip",mobility.leg_hits==trip_start+1,trip_events.back() if mobility.leg_hits>trip_start else {"boot":mobility._boot_center(),"shin":mobility._shins(other),"ball_hits":mobility.slide_hits-hits})
	if mobility.leg_hits>trip_start:
		var e: Dictionary = trip_events.back()
		check("trip carries geometry/foul evidence even after earlier ball",e.foul_evidence.confirmed and e.foul_evidence.contact_geometry=="swept_rendered_socket" and e.foul_evidence.boot_shin_separation<=mobility.BOOT_RADIUS+mobility.SHIN_RADIUS and game.services.rules.state!=game.Rules.State.LIVE,e)
		check("winning ball does not exempt subsequent actual trip",mobility.slide_hits==hits+1 and e.foul_evidence.ball_first,e.foul_evidence)
		var down: Node=other.down_state
		var age: float=down.age
		var v: Vector3=other.velocity
		for i in 5: down.enter_hit(e.event_id,other.facing)
		check("victim duplicate cannot reset fall or apply momentum twice",down.age==age and other.velocity==v and down.duplicate_hits>=5)
	await ticks(200)
	check("hit victim safe stand and clears AI cached kicks",is_instance_valid(other.down_state) and other.down_state.state=="IDLE" and other.pending_kick.is_empty())
	await reset_case()
	var low: Node=mobility.low_body
	var v: Vector3=game.player.velocity
	check("fall posture adds no duplicate solver impulse",low.enter_hit("test:fall",game.player.facing) and game.player.velocity==v)
	var roof: StaticBody3D=roof_at(.95)
	await ticks(155)
	check("ceiling prevents forced getup and opens low crawl",low.state=="CRAWL" and low.stand_blocked)
	key(KEY_W,true)
	var p: Vector3=game.player.position
	await ticks(55)
	check("obstructed crawl moves physically under speed cap",game.player.position.distance_to(p)>.15 and Vector2(game.player.velocity.x,game.player.velocity.z).length()<=.66 and low.state=="CRAWL")
	key(KEY_W,false)
	roof.queue_free()
	await ticks(110)
	check("clearance removal restores safe stand",low.state=="IDLE" and mobility.permits_foot_action())
	await reset_case()
	await start_slide()
	var frozen: Vector3=game.player.position
	game.pause_match()
	await ticks(8)
	check("pause freezes World and closes active slide contact",game.player.position.distance_to(frozen)<.00001 and mobility.slide_phase=="RECOVER")
	attempts=mobility.slide_attempts
	key(KEY_V,true)
	game.resume_match()
	await ticks(220)
	check("resume cannot replay held V and exits low state",mobility.slide_attempts==attempts and mobility.low_body.state=="IDLE")
	key(KEY_V,false)
	await reset_case()
	key(KEY_J,true);await ticks(1);key(KEY_J,false)
	attempts=mobility.slide_attempts
	key(KEY_V,true);await ticks(2);key(KEY_V,false)
	check("airborne V is rejected without consuming a slide",mobility.slide_attempts==attempts)
	await ticks(145)
	key(KEY_B,true);await ticks(20)
	key(KEY_V,true);await ticks(2);key(KEY_V,false)
	check("crouched V cannot grow into an unsafe launch",mobility.slide_attempts==attempts and mobility.crouch>.99)
	key(KEY_B,false);await ticks(30)
	await reset_case()
	check("real RECEIVE still acquires shoe possession",await receive())
	game.player.foot.begin("CLOSE",game.player.facing)
	game.player.action_cooldown=.35
	key(KEY_SHIFT,true);await ticks(5);key(KEY_SHIFT,false);await ticks(5);key(KEY_SHIFT,true);await ticks(1)
	check("original next-foot heavy queue can still reserve",not game.input_bridge.heavy_queue.snapshot().pending.is_empty())
	mouse(MOUSE_BUTTON_LEFT,true);await ticks(1)
	var shot_count: int=game.stats.shots
	var hub_start: int=game.contact_hub.history.size()
	low.enter_hit("test:old_cache",game.player.facing)
	key(KEY_SHIFT,false)
	await ticks(160)
	mouse(MOUSE_BUTTON_LEFT,false)
	await ticks(15)
	var stale: Array=game.contact_hub.history.slice(hub_start).filter(func(e):return e.get("actor")==game.player and e.get("action") in ["SHOT","SPRINT"] and e.get("success",false))
	check("fall cancels old shot/heavy queue and cannot kick on held release",stale.is_empty() and game.stats.shots==shot_count and game.input_bridge.heavy_queue.snapshot().pending.is_empty() and mobility.permits_foot_action())
	await reset_case()
	key(KEY_J,true);await ticks(1);key(KEY_J,false)
	await ticks(20)
	put_ball(mobility.head_center()+game.player.facing*.88,-game.player.facing*6+Vector3.UP*game.player.velocity.y)
	var headers: int=mobility.headers
	mouse(MOUSE_BUTTON_LEFT,true);await ticks(1);mouse(MOUSE_BUTTON_LEFT,false)
	await ticks(35)
	check("preserved J jump and real aerial header still contact",mobility.headers==headers+1)
	await ticks(110)
	key(KEY_B,true);await ticks(25)
	check("preserved B crouch still changes real collider and skeleton",mobility.crouch>.99 and mobility.head_center().y<1.25)
	key(KEY_B,false);await ticks(30)
	var roll: Node=game.get_node("TurfRollAB")
	var audio: Node=game.get_node("AudioAB")
	var old_roll: String=roll.mode
	var old_audio: String=audio.mode
	key(KEY_F7,true);key(KEY_F7,false);key(KEY_F8,true);key(KEY_F8,false)
	await ticks(1)
	check("F7/F8 retained actual runtime controls",roll.mode!=old_roll and audio.mode!=old_audio)
	await finish()

func binding(action: String,code: int) -> bool:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey and e.physical_keycode==code:return true
	return false

func safe(v: Variant) -> Variant:
	if v is Vector3:return [v.x,v.y,v.z]
	if v is Dictionary:
		var d: Dictionary={}
		for k in v:d[str(k)]=safe(v[k])
		return d
	if v is Array:
		var a: Array=[]
		for x in v:a.append(safe(x))
		return a
	if v is Object:return v.get_instance_id() if is_instance_valid(v) else null
	return v

func finish() -> void:
	var passed: int=checks.filter(func(c):return c.passed).size()
	FileAccess.open(evidence.path_join("slide_030_checks.json"),FileAccess.WRITE).store_string(JSON.stringify(safe({"passed":passed,"failed":checks.size()-passed,"checks":checks,"slide_events":slide_events,"trip_events":trip_events,"scope":"Headless/Jolt/120Hz/6 actual actors/oneWorld. AI decisions off and positions seeded. No native/GPU/fullmatch claim."}),"\t"))
	print("SLIDE_030_CHECKS ",passed,"/",checks.size())
	game.pause_match();game.shutdown_audio();game.queue_free()
	for i in 4:await process_frame
	quit(0 if passed==checks.size() else 1)
