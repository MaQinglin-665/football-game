extends SceneTree
# R004 deterministic first-touch timing + receive intercept lock checks (headless).
const RC:=preload("res://scripts/receive_contact.gd")
const RP:=preload("res://scripts/tactics/receive_plan.gd")
var failed:=0
func check(label:String,ok:bool,info:Variant="")->void:
	if not ok:failed+=1
	print("PASS " if ok else "FAIL ",label," ",info)
func _initialize()->void:call_deferred("run")
func run()->void:
	var game:Node=load("res://scenes/training_3v3.tscn").instantiate();game.test_mode=true;root.add_child(game);current_scene=game
	for i in 8:await process_frame
	var actor:Node3D=game.player
	var ball:Node3D=game.ball
	# --- timing grade from simulated input onset (fixed clock, no wall time) ---
	var cases:={"early":0.60,"on_time":0.15,"late":0.03}
	var expect:={"early":"EARLY","on_time":"ON_TIME","late":"LATE"}
	var aim:=Vector3(1,0,0)
	var leads:={}
	for k in cases:
		var ft:FirstTouchTiming=FirstTouchTiming.new()
		ft.observe(aim,10.0-float(cases[k]))
		ft.observe(aim.rotated(Vector3.UP,.1),10.0-float(cases[k])/2) # small drift: no restart
		var g:Dictionary=ft.grade(10.0)
		check("grade "+k,g.grade==expect[k],g)
		# Same incoming ball for each case: rolling at 6 m/s toward a standing receiver.
		actor.velocity=Vector3.ZERO
		ball.position=actor.position+Vector3(0,.11,-.5);ball.velocity=Vector3(0,0,6)
		var dir:=FirstTouchTiming.apply_aim_error(aim,float(g.aim_error_deg),1.0)
		var v:Vector3=RC.lead_velocity(ball,actor,dir,float(g.lead_scale))
		leads[k]={"speed":v.length(),"angle_deg":rad_to_deg(Vector3(v.x,0,v.z).angle_to(aim))}
	print("LEADS ",leads)
	check("on_time touch softer than early",leads.on_time.speed<leads.early.speed)
	check("late touch heavier than on-time",leads.late.speed>leads.on_time.speed+.2)
	actor.velocity=Vector3.ZERO;ball.position=actor.position+Vector3(0,.11,-.5);ball.velocity=Vector3(0,0,6)
	var late_same_dir:Vector3=RC.lead_velocity(ball,actor,aim,FirstTouchTiming.LEAD_SCALE.LATE)
	check("late scale alone heavier than early (same aim)",late_same_dir.length()>leads.early.speed,late_same_dir.length())
	check("late touch off-line vs early",absf(leads.late.angle_deg-leads.early.angle_deg)>3.0)
	var none:=FirstTouchTiming.new();check("no input -> NONE (unchanged cushion)",none.grade(1.0).grade=="NONE" and none.grade(1.0).lead_scale==1.0)
	var turn:=FirstTouchTiming.new();turn.observe(Vector3.FORWARD,0.0);turn.observe(Vector3.RIGHT,0.9)
	check("big direction change restarts onset",turn.grade(1.0).grade=="ON_TIME")
	check("unit scale reproduces legacy lead",RC.lead_velocity(ball,actor,aim)==RC.lead_velocity(ball,actor,aim,1.0))
	# --- intercept lock ---
	var plan:=RP.new()
	plan.active={"intercept_locked":false}
	var p1:={"ball_point":Vector3(1,0,1),"body_point":Vector3(1,0,.6),"face_direction":Vector3.FORWARD,"reachable":true,"horizon":.5}
	plan._apply_lock(p1)
	check("locks when reachable within horizon",plan.active.intercept_locked)
	var p2:=p1.duplicate();p2.ball_point=Vector3(1.3,0,1.2)
	check("small drift keeps locked point",plan._apply_lock(p2).ball_point==Vector3(1,0,1))
	var p3:=p1.duplicate();p3.ball_point=Vector3(2.5,0,1)
	check("large drift releases lock",plan._apply_lock(p3).ball_point==Vector3(2.5,0,1) and not plan.active.intercept_locked)
	var plan2:=RP.new();plan2.active={};var far:=p1.duplicate();far.horizon=1.5
	plan2._apply_lock(far);check("no lock when far in time",not plan2.active.get("intercept_locked",false))
	# --- shader warmup collects materials (headless dummy renderer) ---
	var mats:=ShaderWarmup.collect(game)
	check("warmup finds materials",mats.size()>5,mats.size())
	var w:=ShaderWarmup.new();game.add_child(w);await w.run(game,actor.camera)
	check("warmup runs and frees quads",w.materials_warmed==mats.size(),w.materials_warmed)
	await process_frame
	check("warmup quads freed",actor.camera.get_node_or_null("ShaderWarmupQuads")==null)
	print("RESULT ","PASS" if failed==0 else "FAIL %d"%failed)
	quit(1 if failed else 0)
