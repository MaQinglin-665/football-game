extends SceneTree
# R004: the staged director (tick_begin/tick_team/tick_finish) must give results identical
# to the pre-split single tick for the same live 11v11 snapshots and RNG seeds.
const Ref:=preload("res://tests/reference/director_pre_split.gd")
const Cur:=preload("res://scripts/tactics/tactical_director.gd")
var failed:=0
func check(label:String,ok:bool,info:Variant="")->void:
	if not ok:failed+=1
	print("PASS " if ok else "FAIL ",label," ",info)
func make(script:Script,game:Node)->RefCounted:
	var d:RefCounted=script.new()
	d.configure(game.roster_configuration,{0:Cur.SHORT_PASS,1:Cur.SHORT_PASS})
	d.team_attack.rng.seed=99
	d.learned_policy.rng.seed=7
	return d
func _initialize()->void:call_deferred("run")
func run()->void:
	var game:Node=load("res://scenes/match.tscn").instantiate();game.test_mode=true;root.add_child(game);current_scene=game
	for i in 8:await process_frame
	game.hud.menu.get_node("StartMatch").pressed.emit()
	for i in 8:await physics_frame
	game.services.rules.restart.clear();game.services.rules._become_live();game.set_phase(game.Phase.PLAY);game.ball.set_held(false)
	var ref:=make(Ref,game);var single:=make(Cur,game);var staged:=make(Cur,game)
	var same_single:=0;var same_staged:=0;var n:=0;var first_diff:=""
	var us_single:=0;var us_stage_max:=0;var us_ref:=0
	for k in 60:
		for i in 24:await physics_frame
		var built:Dictionary=game.tactics_bridge._build_snapshot()
		var snap:Dictionary=built.snapshot
		var t0:=Time.get_ticks_usec()
		var a:=var_to_str(ref.tick(snap.duplicate(true),.2))
		var t1:=Time.get_ticks_usec()
		var b:=var_to_str(single.tick(snap.duplicate(true),.2))
		var t2:=Time.get_ticks_usec()
		var s:Dictionary=snap.duplicate(true)
		var ctx:Dictionary=staged.tick_begin(s,.2)
		var t3:=Time.get_ticks_usec();var stage:=t3-t2
		var r:Dictionary
		if ctx.has("result"):r=ctx.result
		else:
			for team in [0,1]:
				var ts:=Time.get_ticks_usec();staged.tick_team(ctx,team);stage=maxi(stage,Time.get_ticks_usec()-ts)
			var tf:=Time.get_ticks_usec();r=staged.tick_finish(ctx);stage=maxi(stage,Time.get_ticks_usec()-tf)
		var c:=var_to_str(r)
		n+=1;us_ref+=t1-t0;us_single+=t2-t1;us_stage_max=maxi(us_stage_max,stage)
		if a==b:same_single+=1
		elif first_diff=="":first_diff="tick %d single"%k
		if a==c:same_staged+=1
		elif first_diff=="":first_diff="tick %d staged"%k
	check("single-call path identical to pre-split",same_single==n,{"same":same_single,"n":n,"first":first_diff})
	check("staged path identical to pre-split",same_staged==n,{"same":same_staged,"n":n})
	print("TIMING ref_mean_ms=%.2f split_mean_ms=%.2f worst_stage_ms=%.2f"%[us_ref/1000.0/n,us_single/1000.0/n,us_stage_max/1000.0])
	print("RESULT ","PASS" if failed==0 else "FAIL %d"%failed)
	quit(1 if failed else 0)
