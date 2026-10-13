extends SceneTree
# R006 headless CPU breakdown per physics tick (11v11 LIVE). No GPU cost.
# godot --headless --path . --fixed-fps 120 -s res://tests/bench_r006_cpu.gd -- --ticks=1200 --output=/tmp/c.json
const SW:=preload("res://scripts/frame_spike_watch.gd")
var n_ticks:=1200
var output:=""
const KEYS:=["world","agents","human","ball","match_phys","pose","tactics","proxy","match_process"]
func _initialize()->void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ticks="):n_ticks=int(a.trim_prefix("--ticks="))
		if a.begins_with("--output="):output=a.trim_prefix("--output=")
	seed(4004);call_deferred("run")
func _read()->Dictionary:
	return {"world":SW.world_us,"agents":SW.agents_us,"human":SW.human_us,"ball":SW.ball_us,"match_phys":SW.match_us-SW.pose_us,"pose":SW.pose_us,"tactics":SW.tactics_us,"proxy":SW.proxy_us,"match_process":SW.match_process_us}
func _reset()->void:
	SW.world_us=0;SW.agents_us=0;SW.human_us=0;SW.ball_us=0;SW.match_us=0;SW.pose_us=0;SW.tactics_us=0;SW.proxy_us=0;SW.match_process_us=0
func run()->void:
	var game:Node=load("res://scenes/match.tscn").instantiate();game.test_mode=true;root.add_child(game);current_scene=game
	for i in 8:await process_frame
	game.hud.menu.get_node("StartMatch").pressed.emit()
	for i in 8:await physics_frame
	game.services.rules.restart.clear();game.services.rules._become_live();game.set_phase(game.Phase.PLAY);game.ball.set_held(false)
	for c in game.get_children():
		if c.get_script()==SW:c.set_process(false)
	SW.enabled=true
	for i in 60:await physics_frame
	_reset()
	var sums:={};var frames:Array[int]=[];var physics_ms:Array[float]=[];var process_ms:Array[float]=[]
	for k in KEYS:sums[k]=0
	var last:=Time.get_ticks_usec()
	for i in n_ticks:
		await process_frame
		var now:=Time.get_ticks_usec();var r:=_read()
		if i>0:
			frames.append(now-last)
			for k in KEYS:sums[k]+=r[k]
			physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0);process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
		last=now;_reset()
	var n:=frames.size();var tot:=0
	for f in frames:tot+=f
	var per:={}
	var named:=0.0
	for k in KEYS:per[k]=snappedf(sums[k]/1000.0/n,.001);named+=per[k]
	per["other"]=snappedf(tot/1000.0/n-named,.001)
	frames.sort()
	var r:={"ticks":n,"frame_mean_ms":snappedf(tot/1000.0/n,.001),"frame_p99_ms":frames[int(n*.99)]/1000.0,"breakdown_ms":per,"active_agents":game.players.filter(func(p):return p.visible).size(),"objects":Performance.get_monitor(Performance.OBJECT_COUNT),"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT)}
	print("CPU ",JSON.stringify(r))
	if output!="":var f:=FileAccess.open(output,FileAccess.WRITE);f.store_string(JSON.stringify(r,"  "));f.close()
	quit(0)
