extends SceneTree
# R004 headless CPU benchmark: 11v11 LIVE, fixed physics ticks, per-tick script cost.
# Headless only: no GPU/render cost.
# godot --headless --path . --fixed-fps 120 -s res://tests/bench_r004_11v11.gd -- --ticks=2400 --output=/tmp/b.json
const SpikeWatch:=preload("res://scripts/frame_spike_watch.gd")
var game:Node
var n_ticks:=2400
var pipeline_off:=false
var output:=""
var tick_us:Array[int]=[]
var tactics_us:Array[int]=[]
var spike_kinds:={}
var pose_us:Array[int]=[]
func _initialize()->void:
	for a in OS.get_cmdline_user_args():
		if a=="--pipeline-off":pipeline_off=true
		if a.begins_with("--ticks="):n_ticks=int(a.trim_prefix("--ticks="))
		if a.begins_with("--output="):output=a.trim_prefix("--output=")
	seed(4004);call_deferred("run")
func run()->void:
	game=load("res://scenes/match.tscn").instantiate();game.test_mode=true;root.add_child(game);current_scene=game
	game.tactics_bridge.pipeline_enabled=not pipeline_off
	for i in 8:await process_frame
	game.hud.menu.get_node("StartMatch").pressed.emit()
	for i in 8:await physics_frame
	game.services.rules.restart.clear();game.services.rules._become_live();game.set_phase(game.Phase.PLAY);game.ball.set_held(false)
	for c in game.get_children():
		if c.get_script()==SpikeWatch:c.set_process(false) # we own counter resets
	SpikeWatch.enabled=true
	SpikeWatch.seg_snapshot_us=0;SpikeWatch.seg_director_us=0
	for i in 60:await physics_frame
	SpikeWatch.seg_snapshot_us=0;SpikeWatch.seg_director_us=0
	var last:=Time.get_ticks_usec()
	for i in n_ticks:
		await physics_frame
		# physics_frame fires before node physics; counters hold the previous tick.
		var now:=Time.get_ticks_usec()
		tick_us.append(now-last);last=now
		if i>0:
			tactics_us.append(SpikeWatch.tactics_us);pose_us.append(SpikeWatch.pose_us)
		if i>0 and SpikeWatch.tactics_us>8000:spike_kinds[SpikeWatch.tactics_kind]=int(spike_kinds.get(SpikeWatch.tactics_kind,0))+1
		SpikeWatch.tactics_us=0;SpikeWatch.pose_us=0;SpikeWatch.tactics_kind=""
	var seg:={"snapshot_ms_total":SpikeWatch.seg_snapshot_us/1000.0,"director_ms_total":SpikeWatch.seg_director_us/1000.0}
	var r:={"pipeline_enabled":not pipeline_off,"scope":"Headless artificial LIVE fixture; interval includes engine and scheduling, no GPU or actual FPS conclusion", "segments":seg,"ticks":n_ticks,"frame":_stats(tick_us),"tactics":_stats(tactics_us),"pose":_stats(pose_us),"refreshes":game.tactics_bridge.refresh_count,"players":game.players.size(),"tactics_spike_kinds":spike_kinds}
	print("BENCH ",JSON.stringify(r))
	if output!="":FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(r,"  "))
	quit()
func _stats(a:Array[int])->Dictionary:
	var s:=a.duplicate();s.sort()
	var tot:=0
	for v in s:tot+=v
	return {"mean_ms":float(tot)/s.size()/1000.0,"p50_ms":s[s.size()/2]/1000.0,"p99_ms":s[int(s.size()*.99)]/1000.0,"max_ms":s[-1]/1000.0,"over_8ms":s.filter(func(v):return v>8000).size()}
