extends SceneTree
var game:Node
var events:Array=[]
var samples:Array=[]
var mode:String=""
var tick:int=0
var following_ticks:int=0
func _initialize()->void:call_deferred("run")
func run()->void:
	for spec in [{"mode":"3v3","scene":"training_3v3.tscn"},{"mode":"11v11","scene":"match.tscn"}]:
		seed(390108);mode=spec.mode
		game=load("res://scenes/"+spec.scene).instantiate();game.test_mode=true;root.add_child(game);current_scene=game
		for i in 6:await physics_frame
		game.contact_hub.contact_resolved.connect(func(e):
			if e.get("success",false):
				var a=e.get("actor")
				events.append({"mode":mode,"tick":tick,"actor":game.players.find(a),"human":a.is_human,"kind":e.get("action",""),"sequence":a.foot.sequence,"ball":game.ball.position,"ball_velocity":game.ball.velocity}))
		if mode=="3v3":game.training_mode.defensive_opening=true
		game.start_match(false)
		if mode=="11v11":game.services.start_match(game.rule_roster(),1);game._sync_rule_phase()
		for i in (2400 if mode=="11v11" else 1200):
			tick=i;await physics_frame
			var a=game.ball.carrier
			if is_instance_valid(a) and not a.is_human and not a.foot.ordinary_scheduler.follow_step.pending.is_empty():following_ticks+=1
			if i%12==0:
				samples.append({"mode":mode,"tick":i,"phase":game.phase,"ball":game.ball.position,"owner":game.players.find(a) if is_instance_valid(a) else -1,"speed":a.velocity.length() if is_instance_valid(a) else 0,"follow":is_instance_valid(a) and not a.foot.ordinary_scheduler.follow_step.pending.is_empty(),"target":a.target if is_instance_valid(a) and not a.is_human else Vector3.ZERO,"gap":game.flat_distance(a.position,game.ball.position) if is_instance_valid(a) else -1,"kind":a.foot.kind if is_instance_valid(a) else ""})
		game.pause_match();game.shutdown_audio();game.queue_free()
		for i in 4:await process_frame
	FileAccess.open(ProjectSettings.globalize_path("res://../verification/r016-natural.json"),FileAccess.WRITE).store_string(JSON.stringify({"events":events,"samples":samples,"following_ticks":following_ticks,"scope":"10 simulation seconds in 3v3, 20 in 11v11. Natural opening with original tactics/AI; human idle. No assigned ball or targets. Headless only, no visual or GPU evidence."}))
	quit()

