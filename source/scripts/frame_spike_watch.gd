extends Node
# Bounded in-memory event telemetry. Disk output only on window close/scene exit.
static var enabled:=false
static var pose_us:=0
static var mid_pose_skips:=0
static var pose_calls:=0
static var post_pose_reused:=0
static var zero_pose_calls:=0
static var keeper_pose_us:=0
static var human_pose_us:=0
static var tactics_us:=0
static var world_us:=0
static var proxy_us:=0
static var promoted:=0
static var far_us:=0
static var far_count:=0
var game:Node
var events:Array[Dictionary]=[]
var last_usec:=0
var last_tick:=0
var last_record:=0
var max_frame_ms:=0.0
var output:=""
var frames:=0
func _ready()->void:
	process_priority=10000
	enabled=true
	output=ProjectSettings.globalize_path("res://").path_join("../slow_frames.json").simplify_path()
	get_window().close_requested.connect(_save)
	last_usec=Time.get_ticks_usec();last_tick=Engine.get_physics_frames()
func _process(_delta:float)->void:
	var now:int=Time.get_ticks_usec()
	var ms:float=float(now-last_usec)/1000.0
	var ticks:int=Engine.get_physics_frames()-last_tick
	if is_instance_valid(game.tactics_bridge):game.tactics_bridge.observe_receive_flow()
	frames+=1
	max_frame_ms=maxf(max_frame_ms,ms)
	if ms>=25.0 and now-last_record>=250000 and game.phase not in [game.Phase.MENU,game.Phase.PAUSED]:
		last_record=now
		var carrier=game.ball.carrier
		var owner:Dictionary={}
		if is_instance_valid(carrier):owner={"human":carrier.is_human,"position":str(carrier.position),"speed":carrier.velocity.length(),"action":carrier.foot.kind,"foot_phase":int(carrier.foot.phase),"hit":carrier.foot.hit}
		var claims:Array[int]=[0,0]
		for actor in game.players:
			if not actor.is_human and (actor.tactical_intent.get("receive",false) or actor.tactical_intent.get("press",false)):claims[actor.team]+=1
		var near:=0
		for actor in game.players:
			if actor.position.distance_squared_to(game.ball.position)<81.0:near+=1
		events.append({"elapsed_ticks":Engine.get_physics_frames(),"frame_ms":ms,"physics_ticks_in_frame":ticks,"pose_ms":float(pose_us)/1000,"pose_calls":pose_calls,"post_pose_reused":post_pose_reused,"mid_pose_skips":mid_pose_skips,"zero_delta_pose_calls":zero_pose_calls,"keeper_pose_ms":float(keeper_pose_us)/1000,"human_pose_ms":float(human_pose_us)/1000,"tactics_ms":float(tactics_us)/1000,"world_ms":float(world_us)/1000,"proxy_ms":float(proxy_us)/1000,"far_ms":float(far_us)/1000,"far_count":far_count,"promotions":promoted,"within_9m":near,"ai_ball_jobs":claims,"tactics_refreshes":game.tactics_bridge.refresh_count,"coalesced_refreshes":game.tactics_bridge.coalesced_refreshes,"carrier":owner,"ball_speed":game.ball.velocity.length(),"match_phase":int(game.phase)})
		if events.size()>120:events.pop_front()
	post_pose_reused=0
	mid_pose_skips=0;pose_us=0;pose_calls=0;zero_pose_calls=0;keeper_pose_us=0;human_pose_us=0;tactics_us=0;world_us=0;proxy_us=0;promoted=0;far_us=0;far_count=0
	last_usec=now;last_tick=Engine.get_physics_frames()
func _save()->void:
	if output.is_empty():return
	var file:=FileAccess.open(output,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify({"scope":"natural play; frame intervals and CPU regions overlap, not additive; startup/shutdown/GPU/OS work may contribute","frames":frames,"max_observed_frame_ms":max_frame_ms,"slow_frames":events,"receive_timings":game.tactics_bridge.receive_timings if is_instance_valid(game.tactics_bridge) else []},"  "))
func _exit_tree()->void:
	_save()
	enabled=false
