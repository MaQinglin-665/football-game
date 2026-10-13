extends SceneTree
## Declared fixture: replace three command sources, retain the real World/motors.
## Off-ball motor comparison only; this does not prove foot/ball-contact parity.
const SharedMovement := preload("res://scripts/football_shared_movement.gd")
var output := ""
var game: Node
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	call_deferred("run")
func key(down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_Q
	e.physical_keycode = KEY_Q
	e.pressed = down
	Input.parse_input_event(e)
	Input.flush_buffered_events()
func vec(value: Vector3) -> Array: return [value.x,value.y,value.z]
func run() -> void:
	game = load("res://scenes/training_3v3.tscn").instantiate()
	game.test_mode = true
	root.add_child(game)
	for _i in 5: await process_frame
	game.hud.menu.get_node("StartMatch").pressed.emit()
	for _i in 8:await physics_frame
	assert(game.services.rules.state==game.Rules.State.LIVE)
	for a in game.agents:a.set_physics_process(false)
	var peers: Array[Node3D] = [game.player]
	for team in [0,1]:
		for actor in game.agents:
			if actor.team==team and not actor.is_goalkeeper:
				peers.append(actor)
				break
	assert(peers.size()==3,"Player and two opposing AI actors required")
	var initial: Array[Vector3] = []
	for i in peers.size():
		var actor: Node3D = peers[i]
		actor.set_physics_process(false)
		actor.position = Vector3((i-1)*8,.002,0)
		actor.velocity = Vector3.ZERO
		actor.facing = Vector3.FORWARD
		actor.body_facing = Vector3.FORWARD
		actor.stamina = 80.0
		actor.sprint_locked = false
		actor.stop_requested = 0.0
		actor.foot.cancel()
		actor.refresh_pose(0)
		actor.get_node("LowerBallContacts").update_from_skeleton(0.0)
		initial.append(actor.position)
	game.ball.reset(Vector3(10,.11,15))
	var command := {"enabled":true,"move":Vector3.FORWARD,"tier":"walk_jog","close_control":true,"shield":false}
	for _i in 240:
		for actor in peers:
			SharedMovement.apply(actor,game,command,{"stamina":actor.stamina,"sprint_locked":actor.sprint_locked},1.0/120.0)
		await physics_frame
	var rows: Array[Dictionary] = []
	var passed := true
	for i in peers.size():
		var actor: Node3D = peers[i]
		var displacement: Vector3 = actor.position-initial[i]
		var equal: bool = displacement.distance_to(peers[0].position-initial[0])<.03 and actor.velocity.distance_to(peers[0].velocity)<.03 and absf(actor.stamina-peers[0].stamina)<.01
		passed = passed and equal and displacement.length()>.2 and actor.close_control
		rows.append({"team":actor.team,"human":actor.is_human,"displacement":vec(displacement),"velocity":vec(actor.velocity),"stamina":actor.stamina,"close_control":actor.close_control,"equal":equal})
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"declared_fixture":true,"source_controllers_replaced":true,"scope":"offball real motor only; no ball contact parity","rows":rows},"\t"))
	game.pause_match()
	game.shutdown_audio()
	game.queue_free()
	game = null
	for _i in 4: await process_frame
	quit(0 if passed else 1)
