extends SceneTree
var game:Node
var camera:Camera3D
var began:=0
var started:=0
var next_sample:=0
var small:=false
var output:=""
var samples:Array=[]
var contacts:Dictionary={}
var modes:Dictionary={}
var roles:Dictionary={}
var pressure_max:=0
var captured:=false
var call_captured:=false
var night_captured:=false
var last_mode:=0
var defense_captured:=false
var physics_seconds:Array=[]
var frame_seconds:Array=[]
func _initialize()->void:call_deferred("begin")
func begin()->void:
	seed(390108)
	for arg in OS.get_cmdline_user_args():
		if arg=="--observe-small":small=true
		if arg.begins_with("--out="):output=arg.trim_prefix("--out=")
	game=load("res://scenes/training_3v3.tscn" if small else "res://scenes/match.tscn").instantiate();root.add_child(game);game.test_mode=true
	game.contact_hub.contact_resolved.connect(func(e:Dictionary):
		if bool(e.get("success",false)):
			var key:String=str(e.get("action",""));contacts[key]=int(contacts.get(key,0))+1
	)
	if small:game.training_mode.defensive_opening=true
	game.start_match(false)
	if not small:game.services.start_match(game.rule_roster(),1);game._sync_rule_phase()
	camera=Camera3D.new();root.add_child(camera);camera.fov=65;camera.current=true
	for layer in game.find_children("*","CanvasLayer",true,false):layer.hide()
	began=Time.get_ticks_usec()
func _process(_delta:float)->bool:
	if began==0:return false
	var now:int=Time.get_ticks_usec()
	game.tactics_bridge.observe_receive_flow()
	if started>0:physics_seconds.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS));frame_seconds.append(_delta)
	if started==0 and game.phase==game.Phase.PLAY:started=now
	var focus:Vector3=game.ball.position*.35
	camera.position=focus+Vector3(0,28 if small else 65,24 if small else 54)
	camera.look_at(focus)
	if now>=next_sample and started>0:
		next_sample=now+200000
		var frame:Dictionary={"time":snappedf((now-started)*.000001,.01),"carrier":game.players.find(game.ball.carrier),"ball":[game.ball.position.x,game.ball.position.z],"players":[]}
		var pressure:Dictionary={0:0,1:0}
		for actor in game.agents:
			if actor.is_goalkeeper:continue
			var intent:Dictionary=actor.tactical_intent
			var task:Dictionary=intent.get("defensive_task",{})
			var job:String=String(task.get("task",intent.get("attack_duty","NONE")))
			roles[job]=int(roles.get(job,0))+1
			modes[actor.locomotion]=int(modes.get(actor.locomotion,0))+1
			if task.get("task","")=="PRESS":pressure[actor.team]+=1
			frame.players.append({"id":game.players.find(actor),"team":actor.team,"slot":game.tactical_director.roster.get(game.players.find(actor),{}).get("slot",""),"job":job,"mark":task.get("target_id",-1),"position":[actor.position.x,actor.position.z],"receive_target_error":actor.target.distance_to(intent.receive_plan.approach_point) if intent.has("receive_plan") else 0.0,"target":[actor.target.x,actor.target.z],"gap":game.flat_distance(actor.position,actor.target),"speed":actor.velocity.length(),"carry_run":intent.get("carry_run",false),"pace":actor.tactical_pace,"sprinting":actor.sprinting,"ball_speed":game.ball.velocity.length(),"call_weight":actor.avatar.ai_body_presentation.call_weight if not actor.is_goalkeeper else 0.0,"duty":intent.get("attack_duty",""),"reason":intent.get("reason",""),"pending_age":actor.pending_age,"pending":not actor.pending_kick.is_empty(),"prepared":actor._prepared_motion.length(),"receive":intent.has("receive_plan"),"foot":actor.foot.kind,"motion":actor.locomotion,"guard":actor.guarding_lane,"feet":actor.avatar.ai_run_ankles.debug_feet,"final_gait":actor.avatar.ai_run_ankles.style,"final_gait_active":actor.avatar.ai_run_ankles.active,"foot_duty":actor.avatar.ai_run_ankles.duty,"lift":actor.avatar.ai_run_ankles.lift,"turn_weight":actor.avatar.ai_run_ankles.turn,"base_clip":actor.avatar._base_clip,"role_overlay":actor.avatar.role_batch_debug(),"phase":actor.avatar._phase,"plant_releases":actor.avatar._plant_releases,"hit":actor.foot.hit,"foot_phase":actor.foot.phase,"ball_gap":actor.position.distance_to(game.ball.position)})
		pressure_max=maxi(pressure_max,maxi(pressure[0],pressure[1]));samples.append(frame)
	if started>0 and now-started>3000000 and not defense_captured:
		for actor in game.agents:
			if not actor.is_goalkeeper and actor.guarding_lane and actor.foot.idle() and actor.velocity.length()>.10 and actor.velocity.length()<1.8 and actor.avatar.ai_body_presentation.guard_weight>.85 and actor.avatar.ai_run_ankles.weight>.85:
				defense_captured=true;call_deferred("capture_defender",actor);break
	if not call_captured:
		for actor in game.agents:
			if not actor.is_goalkeeper and actor.avatar.ai_body_presentation.call_weight>.70:
				call_captured=true;call_deferred("capture_call",actor);break
	if started>0 and now-started>8000000 and last_mode==0:
		last_mode=1;game.settings_menu.values.lighting=1;game.settings_menu.apply_values(false)
	if started>0 and now-started>10000000 and not night_captured:night_captured=true;call_deferred("capture_named","night")
	if started>0 and now-started>6000000 and not captured:captured=true;call_deferred("capture")
	if started>0 and now-started>12000000 or now-began>25000000:
		FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"physics_seconds":physics_seconds,"frame_seconds":frame_seconds,"roster":game.roster_configuration,"styles":game.tactical_director.styles,"roles":roles,"modes":modes,"max_pressers_per_team":pressure_max,"contacts":contacts,"stats":game.stats,"samples":samples,"receive_timings":game.tactics_bridge.receive_timings,"task_events":game.tactical_director.defense_debug_snapshot().events,"scope":"12s natural opponent opening, no replayed inputs; counts are samples not successful defenses"},"  "))
		began=0;quit()
	return false
func capture()->void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.trim_suffix(".json")+".png")

func capture_named(label:String)->void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.trim_suffix(".json")+"_"+label+".png")
func capture_call(actor:Node3D)->void:
	var close:=Camera3D.new();root.add_child(close);close.fov=50
	close.position=actor.position+Vector3(3.2,2.0,3.8);close.look_at(actor.position+Vector3(0,1.0,0));close.current=true
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.trim_suffix(".json")+"_call.png")
	camera.current=true;close.queue_free()

func capture_defender(actor:Node3D)->void:
	var close:=Camera3D.new();root.add_child(close);close.fov=50
	close.position=actor.position+actor.facing*3.2+Vector3(2,1.5,0);close.look_at(actor.position+Vector3(0,.8,0));close.current=true
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.trim_suffix(".json")+"_defense.png")
	camera.current=true;close.queue_free()



