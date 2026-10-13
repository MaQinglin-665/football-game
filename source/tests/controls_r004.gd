extends SceneTree
# R004 deterministic checks: human motion curve, kick error model, camera comfort, HUD arrow.
const HUD:=preload("res://scripts/hud.gd")
const HEAD:=preload("res://Player/Head.gd")
const FP:=preload("res://scripts/football_player.gd")
var failed:=0
func check(label:String,ok:bool,info:Variant="")->void:
	if not ok:failed+=1
	print("PASS " if ok else "FAIL ",label," ",info)
func run_motion(m:HumanMotion,v:Vector3,desired:Vector3,sprint:float,seconds:float)->Vector3:
	for i in int(round(seconds*120)):v=m.step(v,desired,sprint,1.0/120)
	return v
func _initialize()->void:call_deferred("run")
func run()->void:
	var dt:=1.0/120
	# accel 12 m/s^2 from rest: 0.25 s -> 3 m/s ; sprint accel 6
	var m:=HumanMotion.new()
	var v:=run_motion(m,Vector3.ZERO,Vector3(0,0,-5),0,.25)
	check("jog accel ~12 m/s2",absf(v.length()-3.0)<.15,v.length())
	m=HumanMotion.new();v=run_motion(m,Vector3(0,0,-5),Vector3(0,0,-9),1,.25)
	check("sprint accel ~6 m/s2",absf(v.length()-6.5)<.15,v.length())
	m=HumanMotion.new();v=run_motion(m,Vector3(0,0,-4),Vector3.ZERO,0,.1)
	check("decel ~18 m/s2",absf(v.length()-2.2)<.15,v.length())
	check("turn rate 720/s low, 180/s sprint",is_equal_approx(rad_to_deg(m.turn_rate_rad(1.0)),720.0) and is_equal_approx(rad_to_deg(m.turn_rate_rad(9.0)),180.0))
	# sprint cut -> plant
	m=HumanMotion.new();v=run_motion(m,Vector3(0,0,-8),Vector3(0,0,-8),1,.2)
	var before:=v
	v=run_motion(m,v,Vector3(8,0,0),1,.1)
	check("sprint hard cut plants (no heading change during plant)","plant" in m.events and v.normalized().dot(before.normalized())>.99 and m.plant_left>0,{"events":m.events,"plant_left":m.plant_left})
	check("plant length 0.15-0.25s",m.plant_left+.1<=HumanMotion.PLANT_MAX_S+.001)
	# feint: slow from 6 to <60% quickly then cut -> burst
	m=HumanMotion.new();v=run_motion(m,Vector3(0,0,-6),Vector3(0,0,-6),0,.3)
	v=run_motion(m,v,Vector3(0,0,-1),0,.15) # brake to ~3.3
	var slow:=v.length()
	v=run_motion(m,v,Vector3(-6,0,0),0,dt)
	check("slow-then-cut grants feint burst","feint_burst" in m.events and m.burst_left>0,{"slow":slow,"events":m.events})
	var m2:=HumanMotion.new();var v2:=run_motion(m2,Vector3(0,0,-4),Vector3(0,0,-4),0,.5)
	v2=run_motion(m2,v2,Vector3(-6,0,0),0,dt)
	check("steady cut without slow-down: no burst","feint_burst" not in m2.events)
	var mb:=HumanMotion.new();var vb:=run_motion(mb,Vector3(0,0,-6),Vector3(0,0,-6),0,.3)
	vb=run_motion(mb,vb,Vector3(0,0,-1),0,.15);vb=run_motion(mb,vb,Vector3(-6,0,0),0,dt);mb.burst_left=0.0 # same path, burst removed
	var a:=run_motion(m,v,Vector3(-6,0,0),0,.19).length();var b:=run_motion(mb,vb,Vector3(-6,0,0),0,.19).length()
	check("burst makes exit faster",a>b,{"burst":a,"plain":b})
	# --- kick error model ---
	check("charge full at 0.6s",is_equal_approx(KickErrorModel.charge_power(.6,.2),1.0) and KickErrorModel.charge_power(.3,.2)<1.0)
	check("overcharge only beyond 0.6s",KickErrorModel.overcharge(.5)==0.0 and is_equal_approx(KickErrorModel.overcharge(.9),.3))
	var calm:=KickErrorModel.error_deg("pass",0,0,99,0,false)
	check("base error when calm",is_equal_approx(calm,1.5),calm)
	var busy:=KickErrorModel.error_deg("pass",8,45,0,0,false)
	check("speed+angle+pressure add (1+1+.5+1)",is_equal_approx(busy,1.5*3.5),busy)
	check("overcharge adds error",KickErrorModel.error_deg("pass",0,0,99,.4,false)>calm)
	check("back to target doubles",is_equal_approx(KickErrorModel.error_deg("pass",0,130,99,0,false),1.5*(1+130.0/90)*2))
	check("weak foot /0.7",is_equal_approx(KickErrorModel.error_deg("shot",0,0,99,0,true),2.5/.7))
	var aim:=Vector3(0,0,-1)
	var short_hit:=KickErrorModel.assist(aim.rotated(Vector3.UP,deg_to_rad(10)),Vector3.ZERO,Vector3(0,0,-10))
	var short_miss:=KickErrorModel.assist(aim.rotated(Vector3.UP,deg_to_rad(14)),Vector3.ZERO,Vector3(0,0,-10))
	var long_miss:=KickErrorModel.assist(aim.rotated(Vector3.UP,deg_to_rad(8)),Vector3.ZERO,Vector3(0,0,-30))
	var long_hit:=KickErrorModel.assist(aim.rotated(Vector3.UP,deg_to_rad(5)),Vector3.ZERO,Vector3(0,0,-30))
	check("assist cone short ±12°",short_hit.is_equal_approx(aim) and not short_miss.is_equal_approx(aim))
	check("assist cone long ±6°",long_hit.is_equal_approx(aim) and not long_miss.is_equal_approx(aim))
	var rng:=RandomNumberGenerator.new();rng.seed=7
	var mx:=0.0
	for i in 500:mx=maxf(mx,absf(KickErrorModel.sample(3.0,rng)))
	check("samples clamped to 2 sigma",mx<=6.0001 and mx>3.0,mx)
	# --- camera ---
	check("pad deadzone 0.12",HEAD.pad_curve(Vector2(.11,0))==Vector2.ZERO)
	check("pad quadratic",is_equal_approx(HEAD.pad_curve(Vector2(.56,0)).x,.25) and is_equal_approx(HEAD.pad_curve(Vector2(1,0)).x,1.0))
	check("bob limit 1.5cm / sprint 0.75cm",is_equal_approx(FP.limit_bob(1.65,1.60,false),1.615) and is_equal_approx(FP.limit_bob(1.55,1.60,true),1.5925))
	var game:Node=load("res://scenes/training_3v3.tscn").instantiate();game.test_mode=true;root.add_child(game);current_scene=game
	for i in 8:await process_frame
	check("lens 90 and pitch-down limit 55",is_equal_approx(game.player.camera.fov,90.0) and is_equal_approx(game.player.head.y_limit,deg_to_rad(55.0)),{"fov":game.player.camera.fov,"limit":rad_to_deg(game.player.head.y_limit)})
	check("settings default fov 90",float(preload("res://scripts/play_settings.gd").DEFAULTS.fov)==90.0)
	# --- HUD edge arrow ---
	var size:=Vector2(1280,720)
	var right:=HUD.edge_arrow(Vector3(5,0,-1),size,48)
	check("arrow on right edge",is_equal_approx(right.position.x,1280-48) and absf(right.angle)<.3,right)
	var behind:=HUD.edge_arrow(Vector3(0,0,5),size,48)
	check("behind -> bottom edge",is_equal_approx(behind.position.y,720-48),behind)
	print("RESULT ","PASS" if failed==0 else "FAIL %d"%failed)
	quit(1 if failed else 0)
