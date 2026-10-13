extends "res://tests/integration_checks.gd"
## Separate structural/physical fixtures, never a continuous-play acceptance.
var body_events: Array[Dictionary] = []
var results: Array[Dictionary] = []

func lower(actor: Node) -> Node: return actor.get_node("LowerBallContacts")

func free_roll(tag: String, lateral: float) -> void:
	fixture()
	game.player.foot.cancel()
	game.player.refresh_pose(0)
	lower(game.player).update_from_skeleton(0)
	game.ball.position = game.player.position+Vector3(lateral,.111,1.0)
	game.ball.previous_position = game.ball.position
	game.ball.velocity = Vector3(0,0,-4.0)
	var begin_contacts: int = game.ball.body_collision_count
	var max_speed := 0.0
	var max_height := 0.0
	var min_height := INF
	for _i in 100:
		await ticks(1)
		max_speed = maxf(max_speed,game.ball.velocity.length())
		max_height = maxf(max_height,game.ball.position.y)
		min_height = minf(min_height,game.ball.position.y)
	results.append({"fixture":tag,"start_offset_x":lateral,"final_position":game.ball.position,"velocity":game.ball.velocity,"body_contacts":game.ball.body_collision_count-begin_contacts,"max_speed":max_speed,"max_height":max_height,"min_height":min_height})
	check(tag+" remains finite, grounded, no launch",game.ball.position.is_finite() and game.ball.velocity.is_finite() and max_speed<4.5 and max_height<.18 and min_height>.09,results.back())
	if tag=="shoe_interception":
		check("actual shoe sweep contacts free ball",game.ball.body_collision_count>begin_contacts and body_events.any(func(e): return e.actor==game.player and e.get("ball_contact",false)))
	else:
		check("centerline has a real free-ball passage between idle feet",game.ball.body_collision_count==begin_contacts and game.ball.position.z<game.player.position.z-.60)

func run() -> void:
	game = load("res://scenes/match.tscn").instantiate()
	game.test_mode = true
	root.add_child(game)
	await ticks(3)
	game.ai_enabled = false
	game.services.rules.state = game.Rules.State.LIVE
	game.services.rules.restart.clear()
	game.set_phase(game.Phase.PLAY)
	game.services.configuration.half_seconds = 600.0
	game.contact_hub.contact_resolved.connect(func(e: Dictionary): body_events.append(e.duplicate()))
	game.contact_hub.body_contact.connect(func(e: Dictionary): body_events.append(e.duplicate()))
	fixture()
	await ticks(3)
	var all_parts := 0
	var separated := true
	var torso_raised := true
	for actor in game.players:
		all_parts += lower(actor).parts.size()
		for part in lower(actor).parts:
			var proxy: Node = lower(actor).parts[part]
			separated = separated and proxy.collision_layer==8 and proxy.collision_mask==4 and proxy.get_ball_contact_owner()==actor
		for child in actor.get_children():
			if child is CollisionShape3D and child.shape is CapsuleShape3D:
				torso_raised = torso_raised and child.position.y-child.shape.height*.5>.65
		if actor.get_node_or_null("LowerBodyContact")!=null: torso_raised = false
	check("22 actors have separate left/right shin and boot proxies",all_parts==88 and separated,all_parts)
	check("upper motor capsule leaves ground-height ball space",torso_raised and game.player.collision_mask==3)
	var idle_geometry: Dictionary = lower(game.player).snapshot()
	await free_roll("centerline_roll",0.0)
	var right_boot: Node3D = lower(game.player).parts["boot.R"]
	await free_roll("shoe_interception",right_boot.global_position.x-game.player.position.x)

	# Ball ownership is eligibility, never invulnerability. A rear path is
	# occluded by the carrier body; an exposed front/side path can touch it.
	fixture()
	game.ball.take(game.player)
	game.ball.position = game.player.position+Vector3(0,.111,-.40)
	game.ball.previous_position = game.ball.position
	var opponent: Node3D = game.agents.filter(func(a):return a.team!=game.player.team and not a.is_goalkeeper)[0]
	opponent.position = game.player.position+Vector3(0,0,.70)
	opponent.velocity = Vector3.ZERO
	opponent.target = opponent.position
	check("rear tackle ray is blocked by carrier geometry",not game.can_reach_ball(opponent))
	opponent.position = game.player.position+Vector3(.60,0,-.40)
	opponent.target = opponent.position
	opponent.facing = Vector3.LEFT
	opponent.body_facing = Vector3.LEFT
	opponent.refresh_pose(0)
	check("exposed side of close ball remains reachable",game.can_reach_ball(opponent))
	var before_events := body_events.size()
	var accepted: bool = opponent.foot.begin("TACKLE",Vector3.LEFT)
	await ticks(70)
	var actual := body_events.slice(before_events).any(func(e): return e.actor==opponent and e.get("action","")=="TACKLE" and e.success)
	check("exposed close ball can be stolen at real opponent shoe contact",accepted and actual and game.ball.carrier!=game.player,{"began":accepted,"actual_contact":actual,"result":opponent.foot.last_result,"ball":game.ball.position})
	FileAccess.open(evidence.path_join("lower_contact_checks.json"),FileAccess.WRITE).store_string(JSON.stringify({"scope":"Headless physical fixtures; not human/whole-match or visual leg acceptance. Centerline result records actual static stance clearance, not a nutmeg feature.","checks":checks,"idle_geometry":idle_geometry,"rolls":results},"\t"))
	release_inputs()
	game.pause_match()
	game.shutdown_audio()
	game.queue_free()
	game = null
	for _i in 4: await process_frame
	quit(0 if checks.all(func(c):return c.passed) else 1)
