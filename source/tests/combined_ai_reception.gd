extends SceneTree
## Secondary declared fixture, separate from the mandatory untouched natural run.
## One legal opening, one rear-ball setup; no subsequent state/physics writes.
var game: Node
var actor: Node3D
var frame := 0
var scenario := "left_stationary"
var output := ""
var contacts: Array[Dictionary] = []
var samples: Array[Dictionary] = []
var acquired := -1
var owner_losses := 0
var previous_owner := false
var initial_actor := Vector3.ZERO
var control_actor := Vector3.ZERO
var control_ball := Vector3.ZERO
var safe_carry_progress := 0.0
var safe_control_frames := 0
var events: Array[Dictionary] = []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		if arg.begins_with("--scenario="): scenario = arg.trim_prefix("--scenario=")
	call_deferred("run")
func key(down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_Q
	e.physical_keycode = KEY_Q
	e.pressed = down
	Input.parse_input_event(e)
	Input.flush_buffered_events()
func v(a: Vector3) -> Array: return [a.x,a.y,a.z]
func sample() -> Dictionary:
	var offset: Vector3 = game.ball.position-actor.position
	return {"frame":frame,"actor":v(actor.position),"velocity":v(actor.velocity),"facing":v(actor.facing),"ball":v(game.ball.position),"ball_velocity":v(game.ball.velocity),"gap":Vector2(offset.x,offset.z).length(),"forward":offset.dot(actor.facing),"owner":game.players.find(game.ball.carrier),"kind":actor.foot.kind,"phase":actor.foot.phase,"misses":actor.foot.misses,"failure":actor.foot.contact_failure,"pending":not actor.pending_kick.is_empty(),"reason":actor.tactical_intent.get("reason","")}
func run() -> void:
	game = load("res://scenes/training_3v3.tscn").instantiate()
	game.test_mode = true
	root.add_child(game)
	for _i in 5: await process_frame
	game.hud.menu.get_node("StartMatch").pressed.emit()
	for _i in 8: await physics_frame
	assert(game.services.rules.state==game.Rules.State.LIVE)
	var team := 1 if scenario.begins_with("right") else 0
	var heading := Vector3.FORWARD if team==0 else Vector3.BACK
	for id in range(game.players.size()):
		var a: Node3D = game.players[id]
		a.position = Vector3(-9 if id%2 else 9,.002,-12+4*id)
		a.velocity = Vector3.ZERO
		a.foot.cancel()
		a.action_cooldown = 0
		a.set_move_intent(Vector3.ZERO)
		if not a.is_human:
			a.pending_kick.clear()
			a.target = a.position
			a.face_target = heading if a.team==team else -heading
			a.facing = a.face_target
			a.body_facing = a.face_target
		if a.team==team and not a.is_human and actor==null: actor = a
	actor.position = Vector3(0,.002,0)
	actor.facing = heading
	actor.body_facing = heading
	actor.face_target = heading
	actor.target = actor.position
	initial_actor = actor.position
	# Ball starts rear-left/rear-right. No initial ownership is asserted.
	var side := Vector3.LEFT if team==0 else Vector3.RIGHT
	game.ball.reset(actor.position-heading*.58+side*.27)
	game.ball.velocity = -heading*1.4 if scenario.ends_with("moving") else Vector3.ZERO
	if scenario.ends_with("pressure"):
		for opponent in game.agents:
			if opponent.team!=team:
				opponent.position = actor.position-heading*2.8-side*1.8
				break
	game.pass_receiver = null
	game.pass_receiver_timer = 0
	game.tactical_director.reset()
	game.tactics_bridge.refresh_now()
	game.tactics_bridge.clock = .20
	game.tactics_bridge.decision_elapsed = 0
	game.tactics_bridge.contact_refresh_requested = false
	# Single fixture relocation must not be interpreted as an 18 m/s boot
	# sweep from the prior live world. Reinitialize only fixture proxy history.
	for a in game.players:
		a.refresh_pose(0)
		a.get_node("LowerBallContacts").update_from_skeleton(0.0)
	game.services.rules_event.connect(func(e: Dictionary): events.append({"frame":frame,"event":e.duplicate(true)}))
	game.contact_hub.contact_resolved.connect(func(e: Dictionary):
		if e.get("actor",null)!=actor: return
		var r := sample()
		r.success = bool(e.get("success",false))
		r.action = String(e.get("action",""))
		r.shoe = actor.foot.actual_contact.duplicate(true)
		contacts.append(r))
	# Fixture ends here: all six actors, director, referee and physics stay active.
	for _i in 1440:
		await physics_frame
		frame += 1
		var owned: bool = game.ball.carrier==actor
		if owned and acquired<0:
			acquired = frame
			control_actor = actor.position
			control_ball = game.ball.position
		if owned:
			var offset: Vector3 = game.ball.position-actor.position
			if Vector2(offset.x,offset.z).length()<1.0 and offset.dot(actor.facing)>.03:
				safe_control_frames += 1
				safe_carry_progress = maxf(safe_carry_progress,minf((actor.position-control_actor).dot(heading),(game.ball.position-control_ball).dot(heading)))
		if previous_owner and not owned: owner_losses += 1
		previous_owner = owned
		if frame%6==0: samples.append(sample())
	var passes := contacts.filter(func(c): return c.success and c.action=="PASS")
	var successful := contacts.filter(func(c): return c.success and c.action=="RECEIVE" and c.owner==game.players.find(actor))
	var progress: float = (actor.position-initial_actor).dot(heading)
	var report := {"scenario":scenario,"declared_fixture":true,"all_six_active":game.players.size()==6 and game.ai_enabled,"post_setup_state_writes":false,"acquired_frame":acquired,"actual_control_contacts":successful.size(),"actual_passes":passes.size(),"forward_progress":progress,"safe_owned_ball_and_body_progress":safe_carry_progress,"safe_control_frames":safe_control_frames,"owner_losses":owner_losses,"contacts":contacts,"samples":samples,"events":events,"checks":[{"check":"actual_shoe_control","ok":not successful.is_empty()},{"check":"turn_then_carry_or_actual_pass","ok":safe_carry_progress>1.0 or not passes.is_empty()},{"check":"no_repeated_reacquisition_loop","ok":owner_losses<=2 or not passes.is_empty()}]}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("TARGETED_END ",scenario," control=",successful.size()," pass=",passes.size()," progress=",progress," losses=",owner_losses)
	game.pause_match()
	game.shutdown_audio()
	game.queue_free()
	game = null
	for _i in 4: await process_frame
	quit()
