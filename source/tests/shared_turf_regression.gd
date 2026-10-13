extends SceneTree
## Queue with the complete 3v3/TouchPlan06 batch. No real input/GPU claim.
const Profile = preload("res://addons/football_physics/physics_profile.gd")
const Forces = preload("res://addons/football_physics/ball_forces.gd")
const Probe = preload("res://tests/visual_probe.gd")
var arena: Node3D
var checks: Array = []
var cases: Array = []
var physics_clock := 0.0
var outer_hz := 120

func _initialize() -> void:
	call_deferred("run")

func xyz(v: Vector3) -> Array:
	return [v.x,v.y,v.z]

func check(label: String, passed: bool, metrics: Dictionary = {}) -> void:
	checks.append({"test":label,"passed":passed,"metrics":metrics})
	print("PASS " if passed else "FAIL ",label," ",JSON.stringify(metrics))

func make_ball(extra: float):
	var ball = Probe.new()
	ball.profile = Profile.playable()
	ball.profile.low_speed_roll_extra_mps2 = extra
	arena.add_child(ball)
	ball.position = Vector3(0,.111,0)
	return ball

func state(ball: FootballPhysicsBall) -> Dictionary:
	return {"p_m":xyz(ball.position),"v_mps":xyz(ball.velocity),"w_rads":xyz(ball.spin_rads),
		"supported":ball.grounded,"contacts":ball.collision_count,"budget_hits":ball.substep_budget_hits}

func simulate(config: Dictionary, extra: float, hz: int = 120) -> Dictionary:
	var ball = make_ball(extra)
	var launch: Dictionary = {}
	if config.get("drop",false):
		ball.position.y = ball.radius+2.0
	elif config.has("power"):
		launch = ball.kick(Vector3.FORWARD,float(config.power),float(config.get("angle_deg",0)),Vector3.ZERO,"pass")
	else:
		var v := float(config.get("speed",1.2))
		ball.velocity = Vector3.FORWARD*v
		ball.spin_rads = Vector3.ZERO if config.get("sliding",false) else Vector3.UP.cross(ball.velocity)/ball.radius
		if config.get("shift",false):
			# Same frozen apply_foot_contact cap and angular impulse. This valid
			# surface point is prescribed, not a trace of a user's moving shoe.
			var target := Vector3.FORWARD*9.2
			var change: Vector3 = (target-ball.velocity).limit_length(6.0)
			var offset := Vector3(0,-.025,sqrt(ball.radius*ball.radius-.025*.025))
			ball.apply_impulse_ns(change*ball.mass_kg,offset)
	await physics_frame
	physics_clock = 0.0
	var initial := state(ball)
	var contacts: Array = []
	ball.physical_contact.connect(func(_body,point,j):
		var incoming: Vector3 = ball.velocity-j/ball.mass_kg
		contacts.append({"t_s_upper":physics_clock,"point_m":xyz(point),"j_ns":xyz(j),
			"incoming_v_mps":xyz(incoming),"outgoing_v_mps":xyz(ball.velocity),"outgoing_w_rads":xyz(ball.spin_rads)}))
	var path: Array = []
	var prefix: Array = []
	var slip_s := 0.0
	var distance_m := 0.0
	var stop_s := -1.0
	var peak_y: float = ball.position.y
	var snapshots := {}
	var previous_energy: float = .5*ball.mass_kg*ball.velocity.length_squared()+.5*ball.profile.inertia_kgm2()*ball.spin_rads.length_squared()
	var energy_increase := 0.0
	for i in range(hz*15):
		var old_position: Vector3 = ball.position
		physics_clock += 1.0/hz
		ball.step_physics(1.0/hz)
		var after := state(ball)
		var slip: Vector3 = (ball.velocity+ball.spin_rads.cross(Vector3.DOWN*ball.radius)).slide(Vector3.UP)
		if ball.grounded and slip.length()>.015: slip_s += 1.0/hz
		distance_m += Vector2(ball.position.x-old_position.x,ball.position.z-old_position.z).length()
		peak_y = maxf(peak_y,ball.position.y)
		if physics_clock<=1.0+.000001: prefix.append(after)
		if i%maxi(1,int(hz/30))==0:
			var sample := after.duplicate()
			sample["t_s"] = physics_clock
			sample["slip_mps"] = slip.length()
			path.append(sample)
		for t in [.25,.5,1.0,2.0]:
			if not snapshots.has(str(t)) and physics_clock>=float(t)-.000001:
				snapshots[str(t)] = after
		if not config.has("angle_deg") and not config.get("drop",false):
			var energy: float = .5*ball.mass_kg*ball.velocity.length_squared()+.5*ball.profile.inertia_kgm2()*ball.spin_rads.length_squared()
			energy_increase = maxf(energy_increase,energy-previous_energy)
			previous_energy = energy
		if ball.grounded and ball.velocity.length()<ball.profile.rest_speed_mps:
			stop_s = physics_clock
			break
	for t in [.25,.5,1.0,2.0]:
		if not snapshots.has(str(t)): snapshots[str(t)] = state(ball)
	var result := {"case":config.name,"extra_mps2":extra,"outer_hz":hz,"internal_hz":240,
		"launch":launch,"initial":initial,"final":state(ball),"distance_m":distance_m,"stop_s":stop_s,
		"slip_s_outer_sampled":slip_s,"peak_center_y_m":peak_y,"contacts":contacts,"path":path,
		"states_first_1s":prefix,"states_at_s":snapshots,"max_energy_increase_j":energy_increase,
		"visual_quaternion":[ball.visual.quaternion.x,ball.visual.quaternion.y,ball.visual.quaternion.z,ball.visual.quaternion.w],
		"contact_scope":"prescribed fixture; no real shoe/input/ownership"}
	check("finite/stopped "+str(config.name)+" "+str(extra)+" "+str(hz),
		ball.velocity.is_finite() and ball.spin_rads.is_finite() and stop_s>=0 and ball.substep_budget_hits==0)
	if not config.has("angle_deg") and not config.get("drop",false):
		check("ground energy dissipates "+str(config.name)+" "+str(extra),energy_increase<.0001)
	cases.append(result)
	ball.free()
	await physics_frame
	return result

func run() -> void:
	arena = Node3D.new()
	root.add_child(arena)
	var turf := StaticBody3D.new()
	turf.collision_layer = 1
	turf.collision_mask = 0
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400,.2,400)
	collider.shape = box
	turf.add_child(collider)
	turf.position.y = -.1
	arena.add_child(turf)
	await physics_frame
	var p := Profile.playable()
	check("playable curve valid",p.validate() and p.low_speed_roll_extra_mps2==.75)
	check("real-scale remains legacy",Profile.real_scale().low_speed_roll_extra_mps2==0.0)
	check("low/high endpoints",is_equal_approx(Forces.rolling_deceleration_mps2(1.2,p),1.5) and
		is_equal_approx(Forces.rolling_deceleration_mps2(3.5,p),.75) and is_equal_approx(Forces.rolling_deceleration_mps2(17.0,p),.75))
	p.low_speed_roll_extra_mps2 = 0.0
	check("A toggle restores constant roll",Forces.rolling_deceleration_mps2(1.2,p)==p.roll_deceleration_mps2)
	p.low_speed_roll_extra_mps2 = -.1
	check("reject negative extra",not p.validate())
	p.low_speed_roll_extra_mps2 = NAN
	check("reject nonfinite extra",not p.validate())
	p.low_speed_roll_extra_mps2 = .75
	p.low_speed_roll_end_mps = p.low_speed_roll_full_mps
	check("reject empty transition",not p.validate())
	for cfg in [{"name":"low_roll_1.2","speed":1.2},{"name":"low_toe_slip_1.2","speed":1.2,"sliding":true},
		{"name":"normal_touch_2.8","speed":2.8},{"name":"mid_pass_0.5","power":.5},
		{"name":"shift_6delta","speed":2.8,"shift":true},
		{"name":"landing_12deg","power":.5,"angle_deg":12.0},{"name":"vertical_drop_2m","drop":true}]:
		var a: Dictionary = await simulate(cfg,0.0)
		var b: Dictionary = await simulate(cfg,.75)
		if cfg.name in ["low_roll_1.2","low_toe_slip_1.2","normal_touch_2.8","shift_6delta","landing_12deg"]:
			check("B shorter coast "+str(cfg.name),b.distance_m<a.distance_m and b.stop_s<a.stop_s,
				{"A_m":a.distance_m,"B_m":b.distance_m,"A_s":a.stop_s,"B_s":b.stop_s})
		if cfg.get("shift",false):
			check("Shift actual impulse and first second unchanged",a.initial==b.initial and a.states_first_1s==b.states_first_1s)
		if cfg.get("sliding",false):
			check("real slip duration unchanged",a.slip_s_outer_sampled==b.slip_s_outer_sampled)
		if cfg.has("angle_deg"):
			check("air launch and first landing unchanged",a.initial==b.initial and a.contacts[0]==b.contacts[0] and a.peak_center_y_m==b.peak_center_y_m)
		if cfg.has("power") and not cfg.has("angle_deg"):
			check("mapping follows updated resistance",absf(b.distance_m-float(b.launch.target_roll_distance_m))<.03,
				{"A_launch":a.launch.speed_mps,"B_launch":b.launch.speed_mps,"B_stop_m":b.distance_m})
		if cfg.get("drop",false):
			check("vertical bounce path unmodified; no artificial hops",a.path==b.path and a.contacts==b.contacts and a.final==b.final)
		if cfg.name=="normal_touch_2.8":
			check("A native legacy reference",absf(a.distance_m-4.633216381073)<.005 and absf(a.stop_s-3.416666666667)<.02)
	var dt_reference: Dictionary = {}
	for hz in [30,60,120,240]:
		var r: Dictionary = await simulate({"name":"dt_low_roll_2.8","speed":2.8},.75,int(hz))
		if dt_reference.is_empty(): dt_reference = r
		else:
			check("fixed substep dt stability "+str(hz),r.final.p_m==dt_reference.final.p_m and
				r.visual_quaternion==dt_reference.visual_quaternion and absf(r.distance_m-dt_reference.distance_m)<.0001)
	var failures := checks.filter(func(c):return not c.passed)
	var result := {"status":"PASS" if failures.is_empty() else "FAIL","engine":Engine.get_version_info(),
		"checks":checks,"passed":checks.size()-failures.size(),"failed":failures.size(),"cases":cases,
		"scope":"Isolated native module fixtures only; full 3v3 merged TouchPlan06 and human/GPU remain separate acceptance"}
	var evidence := ProjectSettings.globalize_path("res://project.godot").get_base_dir().get_base_dir().path_join("verification/physical_ab")
	var file := FileAccess.open(evidence.path_join("shared_turf_native.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	file.close()
	print("SHARED_TURF_RESULT ",result.status," ",result.passed,"/",checks.size())
	quit(0 if failures.is_empty() else 1)
