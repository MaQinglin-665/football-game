extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var m: Node3D = load("res://scenes/match.tscn").instantiate()
	m.test_mode = true
	root.add_child(m)
	m.rng.seed = 912
	m.start_match(false)
	m.begin_play()
	for frame in range(7200):
		await physics_frame
		if frame % 600 == 0:
			var agents := []
			for a in m.agents:
				var toward: Vector3 = m.ball.position - a.position
				toward.y = 0
				agents.append({"jersey": a.jersey, "team": a.team, "p": a.position, "target": a.target, "chase": a.chase, "distance": m.flat_distance(a.position, m.ball.position), "dot": a.facing.dot(toward.normalized()), "active": a.active})
			print(JSON.stringify({"frame": frame, "phase": m.phase, "carrier": m.ball.carrier.name if m.ball.carrier != null else "free", "ball": m.ball.position, "stats": m.stats, "agents": agents}))
	quit()
