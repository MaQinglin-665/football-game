extends Node
## Training orchestration only. No continuous position/velocity/possession edits.
var game: Node
var low_pressure := true
var defensive_opening := false
var preserve_scores := false
var reset_age := 0.0
var repetitions := 0
var session_seconds := 0.0
var last_goal_team := -1

func _ready() -> void:
	name = "TrainingMode"
	process_physics_priority = 50
	low_pressure = game.training_configuration.low_pressure
	game.services.rules_event.connect(func(event: Dictionary):
		if event.type == "goal": last_goal_team = int(event.team)
	)

func begin_round() -> void:
	game.services.rules.preserve_scores = preserve_scores
	game.services.start_match(game.rule_roster(), 0)
	if not preserve_scores:
		repetitions = 0
		session_seconds = 0.0
	repetitions += 1
	reset_age = 0.0
	game.restart_taker = null
	game.restart_plan.clear()
	game.tactics_bridge.clock = 0.0
	game.tactics_bridge.restart_kick_setup.clear()
	game.tactics_bridge.restart_waypoints.clear()
	# Explicit repetition fixture; live control resumes through the shared feet.
	var owner: Node3D = game.player
	if defensive_opening:
		owner = game.players[3]
		owner.position.z = -game.field_half_length * .32
	game.ball.reset(owner.position + owner.facing * .50)
	game.ball.set_held(false)
	game.ball.take(owner)
	game.set_phase(game.Phase.PLAY)
	game.message("%s · R 重置 · F5 压力 · F6 攻防起点" % opening_label(), 3.0)

func reset_repetition() -> void:
	preserve_scores = true
	game.start_match(false)
	preserve_scores = false

func _physics_process(delta: float) -> void:
	if game.phase in [game.Phase.MENU, game.Phase.PAUSED]:
		return
	if game.services.rules.state == game.Rules.State.LIVE:
		session_seconds += delta
		reset_age = 0.0
		return
	# Freeze the actors during the brief result banner; the rules held the ball.
	game.player.set_match_active(false)
	for actor in game.agents:
		actor.set_match_active(false)
	reset_age += delta
	if reset_age >= game.training_configuration.reset_seconds:
		reset_repetition()

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if game.hud.help.visible or game.hud.credits.visible:
		return
	if event.physical_keycode == KEY_F5:
		low_pressure = not low_pressure
		game.message("黄队防守压力：" + pressure_label(), 2.0)
	elif event.physical_keycode == KEY_F6:
		defensive_opening = not defensive_opening
		if game.phase not in [game.Phase.MENU, game.Phase.PAUSED]:
			reset_repetition()
	elif event.physical_keycode == KEY_R and game.phase not in [game.Phase.MENU, game.Phase.PAUSED]:
		reset_repetition()

func pressure_label() -> String:
	return "低" if low_pressure else "普通"

func opening_label() -> String:
	return "无球防守" if defensive_opening else "持球进攻"

func adapt_intent(actor: Node3D, intent: Dictionary) -> Dictionary:
	# Ordinary pressure is the unchanged stable AI. Low pressure reduces only
	# yellow defensive approach speed and tackle decisions, never kick physics.
	if not low_pressure or actor.team != 1:
		return intent
	var defending: bool = is_instance_valid(game.ball.carrier) and game.ball.carrier.team == 0
	defending = defending or (not is_instance_valid(game.ball.carrier) and is_instance_valid(game.pass_receiver) and game.pass_receiver.team == 0)
	if not defending:
		return intent
	intent.pace = minf(float(intent.pace), 2.6)
	if String(intent.action) == "TACKLE":
		intent.action = "NONE"
		intent.press = true
		intent.primary_action = "PRESS"
	if intent.has("defensive_task"): intent.defensive_task.target = intent.move_target
	intent.training_pressure = "low"
	return intent
