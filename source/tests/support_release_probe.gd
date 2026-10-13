extends SceneTree
const BallScript := preload("res://addons/football_physics/football_ball.gd")
const ProfileScript := preload("res://addons/football_physics/physics_profile.gd")
var cases: Array[Dictionary] = []
var checks: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("run")

func check(label: String, passed: bool) -> void:
	checks.append({"test":label,"passed":passed})
	print("PASS " if passed else "FAIL ",label)

func xyz(v: Vector3) -> Array:
	return [v.x,v.y,v.z]

func run() -> void:
	var arena := Node3D.new()
	root.add_child(arena)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200,1,200)
	shape.shape = box
	shape.position.y = -.5
	floor_body.add_child(shape)
	arena.add_child(floor_body)
	await physics_frame
	await physics_frame
	for initial in [Vector3(0,.05,-3),Vector3(0,.20,-3),Vector3(0,1.15,-8),Vector3(0,-2,-3)]:
		var ball := BallScript.new()
		ball.profile = ProfileScript.playable()
		ball.auto_step = false
		arena.add_child(ball)
		var start_y := .1125 if initial.y<0 else .111
		ball.position = Vector3(0,start_y,0)
		ball.velocity = initial
		ball.spin_rads = Vector3.UP.cross(Vector3(0,0,initial.z))/ball.radius
		var peak := start_y
		var collisions: Array[Dictionary] = []
		ball.physical_contact.connect(func(_body: Object,point: Vector3,j: Vector3): collisions.append({"point":xyz(point),"impulse_ns":xyz(j),"post_velocity":xyz(ball.velocity)}))
		var first_velocity := Vector3.ZERO
		for i in 120:
			ball.step_physics(1.0/240.0)
			peak = maxf(peak,ball.position.y)
			if i==0: first_velocity = ball.velocity
		cases.append({"initial_velocity":xyz(initial),"rise_m":peak-start_y,"collisions":collisions,"first_velocity":xyz(first_velocity),"final_velocity":xyz(ball.velocity)})
		check("finite ball state case %d" % cases.size(),ball.position.is_finite() and ball.velocity.is_finite())
		check("genuine floor collision case %d" % cases.size(),not collisions.is_empty())
		ball.free()
	check("tiny upward momentum remains airborne",cases[0].first_velocity[1]>0 and float(cases[0].rise_m)>.0001)
	check(".20mps launch retains ballistic rise",float(cases[1].rise_m)>.0018 and float(cases[1].rise_m)<.0022)
	check("1.15mps hop remains physical",float(cases[2].rise_m)>.05 and float(cases[2].rise_m)<.08)
	check("2mps descent gives physical 5-10cm bounce",float(cases[3].rise_m)>.05 and float(cases[3].rise_m)<.10)
	var failures: int = checks.filter(func(c): return not c.passed).size()
	var report := {"engine":Engine.get_version_info(),"passed":checks.size()-failures,"failed":failures,"checks":checks,"cases":cases,"ball_sha256":FileAccess.get_sha256("res://addons/football_physics/football_ball.gd"),"profile_sha256":FileAccess.get_sha256("res://addons/football_physics/physics_profile.gd"),"scope":"Release source's actual CharacterBody sphere sweeps on a Jolt static floor, 240Hz internal substeps. No input, foot action, subjective feel, full match or performance acceptance."}
	report["executable"] = OS.get_executable_path()
	report["resource_root"] = ProjectSettings.globalize_path("res://")
	var evidence_path := "res://../verification/support_release_probe.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="): evidence_path = arg.trim_prefix("--evidence=")
	FileAccess.open(evidence_path,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	for row in cases: print("SUPPORT_RELEASE initial=",row.initial_velocity," rise_m=",row.rise_m," collisions=",row.collisions.size())
	arena.free()
	quit(0 if failures==0 else 1)
