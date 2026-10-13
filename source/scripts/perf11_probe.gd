extends Node
# Opt-in, short startup observation. No input playback or ball/actor injection.
static var sampling:=false
static var pose_usec:=0
static var pose_calls:=0
var game:Node
var output:=""
var start_usec:=0
var sample_usec:=0
var frames:=0
var ticks:=0
var last_frame:=0
var frame_ms:Array[float]=[]
var phases:Dictionary={}
var started:=false
var start_ticks:=0
var start_world:=0
var origins:Array[Vector3]=[]
func _ready()->void:
	process_physics_priority=100
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--perf11-output="):output=arg.trim_prefix("--perf11-output=")
	call_deferred("begin")
func begin()->void:
	game.start_match(false)
	start_usec=Time.get_ticks_usec()
	started=true
func _physics_process(_delta:float)->void:
	if sampling:ticks+=1
func _process(_delta:float)->void:
	if not started:return
	var now:int=Time.get_ticks_usec()
	if sample_usec==0:
		if now-start_usec<3000000:return
		sample_usec=now;last_frame=now;start_ticks=Engine.get_physics_frames();start_world=game.physics_world.step_serial
		for actor in game.players:origins.append(actor.position)
		pose_usec=0;pose_calls=0;sampling=true
		return
	frames+=1
	frame_ms.append(float(now-last_frame)/1000.0);last_frame=now
	var phase:String=str(game.phase)+":"+str(game.services.rules.state)
	phases[phase]=int(phases.get(phase,0))+1
	if now-sample_usec<6000000:return
	sampling=false
	frame_ms.sort()
	var seconds:float=float(now-sample_usec)/1000000.0
	var moved:=0
	var far:=0
	for i in game.players.size():
		if game.players[i].position.distance_to(origins[i])>.1:moved+=1
		if not game.players[i].is_human and bool(game.players[i].get("_visual_far39")):far+=1
	var report:Dictionary={"scope":"single 6-second normal match start, human idle; no input playback, no ball fixture; not sustained live-match guarantee","fps_wall":frames/seconds,"wall_seconds":seconds,"frame_p50_ms":frame_ms[int(frame_ms.size()*.5)],"frame_p95_ms":frame_ms[mini(frame_ms.size()-1,int(frame_ms.size()*.95))],"pose_total_ms":float(pose_usec)/1000,"pose_calls":pose_calls,"pose_ms_per_wall_second":float(pose_usec)/1000/seconds,"physics_ticks":Engine.get_physics_frames()-start_ticks,"sim_seconds_per_wall_second":float(Engine.get_physics_frames()-start_ticks)/Engine.physics_ticks_per_second/seconds,"world_steps":game.physics_world.step_serial-start_world,"players":game.players.size(),"ai_enabled":game.ai_enabled,"far_display_actors":far,"moved_over_10cm":moved,"phase_frame_counts":phases,"quality":game.render_quality,"physics_hz":Engine.physics_ticks_per_second}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("PERF11_OBSERVATION ",JSON.stringify(report))
	get_tree().quit()
