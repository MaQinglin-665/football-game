extends SceneTree
# R004 deterministic AI awareness / tackle-commit checks (pure helpers + short live smoke).
var failed:=0
func check(label:String,ok:bool,info:Variant="")->void:
	if not ok:failed+=1
	print("PASS " if ok else "FAIL ",label," ",info)
func _initialize()->void:call_deferred("run")
func run()->void:
	var A:=AiAwareness
	check("reaction 0.40 low / 0.15 high",is_equal_approx(A.reaction_delay(.8),.40) and is_equal_approx(A.reaction_delay(1.2),.15))
	check("vision ±100°",A.in_vision(Vector3.ZERO,Vector3(0,0,-1),Vector3(5,0,0)) and not A.in_vision(Vector3.ZERO,Vector3(0,0,-1),Vector3(1,0,5)))
	var rng:=RandomNumberGenerator.new();rng.seed=11
	var c:=[{"key":"a","score":1.0},{"key":"b","score":1.10}]
	check("hysteresis keeps previous within 15%",A.select(c,"a",0.0,rng).key=="a")
	var c2:=[{"key":"a","score":1.0},{"key":"b","score":1.30}]
	check("switches when >15% better",A.select(c2,"a",0.0,rng).key=="b")
	var picks:={"a":0,"b":0}
	for i in 2000:picks[A.select(c2,"",A.temperature(.8),rng).key]+=1
	var precise:={"a":0,"b":0}
	for i in 2000:precise[A.select(c2,"",A.temperature(1.2),rng).key]+=1
	check("low ability softmax makes natural mistakes",picks.a>200 and picks.a<1000,picks)
	check("high ability nearly always best",precise.a<10,precise)
	check("touchline penalty 0 beyond 2m, max at line",A.touchline_penalty(Vector3(30,0,0),34,52.5)==0.0 and is_equal_approx(A.touchline_penalty(Vector3(34,0,0),34,52.5),A.TOUCHLINE_PENALTY) and is_equal_approx(A.touchline_penalty(Vector3(33,0,0),34,52.5),A.TOUCHLINE_PENALTY*.5))
	check("recover pace when far",A.recover_pace(5.8,10)==A.RECOVER_PACE and A.recover_pace(5.8,3)==5.8)
	check("behind detection",A.tackler_behind(Vector3(0,0,2),Vector3.ZERO,Vector3(0,0,-5)) and not A.tackler_behind(Vector3(0,0,-2),Vector3.ZERO,Vector3(0,0,-5)))
	check("commit: heavy touch",A.should_commit(.6,true,false,false))
	check("contain: tucked ball, open pitch",not A.should_commit(.25,false,false,false))
	check("commit: cornered",A.should_commit(.25,false,false,true))
	check("behind: only heavy touch",not A.should_commit(.4,true,true,true) and A.should_commit(.6,true,true,false))
	# live smoke: 11v11 runs with all R004 hooks, miss-slow scales motion
	var game:Node=load("res://scenes/match.tscn").instantiate();game.test_mode=true;root.add_child(game);current_scene=game
	for i in 8:await process_frame
	game.hud.menu.get_node("StartMatch").pressed.emit()
	for i in 8:await physics_frame
	game.services.rules.restart.clear();game.services.rules._become_live();game.set_phase(game.Phase.PLAY);game.ball.set_held(false)
	var agent=game.agents[3]
	agent.tackle_miss_slow_left=A.MISS_SLOW_S
	for i in 30:await physics_frame
	check("miss slow decays",agent.tackle_miss_slow_left<A.MISS_SLOW_S and agent.tackle_miss_slow_left>0.0,agent.tackle_miss_slow_left)
	for i in 600:await physics_frame
	var lt=game.tactics_bridge.local_standing_tackle
	check("11v11 5s live with awareness",game.players.size()==22 and game.tactics_bridge.refresh_count>10,{"refreshes":game.tactics_bridge.refresh_count,"tackle_checks":lt.checks,"tackle_starts":lt.starts,"contained":lt.contained})
	print("RESULT ","PASS" if failed==0 else "FAIL %d"%failed)
	quit(1 if failed else 0)
