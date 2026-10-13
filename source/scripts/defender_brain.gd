class_name FootballDefenderBrain
extends RefCounted

var observed_ball := Vector3.ZERO
var observed_velocity := Vector3.ZERO
var observed_attacker := Vector3.ZERO
var observed_attacker_velocity := Vector3.ZERO
var observation_clock := 0.0
var observation_age := 0.0
var state := "JOCKEY"
var pace := 4.0
var ready := false
var decisions := 0
var commitments := 0

func reset() -> void:
	ready = false
	observation_clock = 0
	observation_age = 0
	state = "JOCKEY"
	commitments = 0

func think(agent: Node3D, attacker: Node3D, game: Node, delta: float) -> Vector3:
	observation_clock -= delta
	observation_age += delta
	if observation_clock <= 0 or not ready:
		observed_ball = game.ball.position
		observed_velocity = Vector3(game.ball.velocity.x,0,game.ball.velocity.z)
		observed_attacker = attacker.position
		observed_attacker_velocity = Vector3(attacker.velocity.x,0,attacker.velocity.z)
		observation_clock = game.tuning.defender_reaction
		ready = true
		decisions += 1
	var goal_axis: Vector3 = game.target_goal(attacker.team)-observed_attacker
	goal_axis.y = 0
	goal_axis = goal_axis.normalized()
	var relative := agent.position-observed_attacker
	relative.y = 0
	var goal_side := relative.dot(goal_axis)
	var target: Vector3 = observed_attacker+goal_axis*game.tuning.defender_standoff
	var lateral := Vector3(-goal_axis.z,0,goal_axis.x)
	target += lateral*clampf((observed_ball-observed_attacker).dot(lateral)*0.45,-0.45,0.45)
	pace = game.tuning.defender_jockey_speed
	if agent.foot.kind == "TACKLE" and not agent.foot.idle():
		state = "COMMIT" if agent.foot.phase != FootballFootAction.Phase.RECOVER else "RECOVER"
		return target
	if goal_side < -0.35:
		state = "RECOVER"
		pace = game.tuning.defender_recovery_speed
		return observed_attacker+goal_axis*2.2
	var ball_distance: float = game.flat_distance(agent.position,observed_ball)
	var body_distance := relative.length()
	state = "APPROACH" if body_distance > 3.5 else "JOCKEY"
	if state == "APPROACH":
		pace = 5.4
	var owner_gap: float = game.flat_distance(observed_attacker,observed_ball)
	var toward_agent := agent.position-observed_ball
	toward_agent.y = 0
	var outward_speed := (observed_velocity-observed_attacker_velocity).dot(toward_agent.normalized())
	var exposed: bool = owner_gap > game.tuning.defender_exposed_gap or ball_distance < 0.72 or (outward_speed > 1.8 and owner_gap>0.74 and ball_distance < 1.12)
	if observation_age > 0.25 and exposed and ball_distance < 1.24 and agent.tackle_cooldown <= 0 and agent.foot.idle() and game.can_reach_ball(agent):
		var toward := observed_ball-agent.position
		toward.y = 0
		agent.facing = toward.normalized()
		if game.attempt_tackle(agent):
			state = "COMMIT"
			commitments += 1
	target.y = 0.92
	return target
