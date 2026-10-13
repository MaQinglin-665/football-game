extends "res://tests/integration_checks.gd"
var rows:Array=[]
var observer:Camera3D
func run()->void:
	game=load("res://scenes/match.tscn" if "--eleven" in OS.get_cmdline_user_args() else "res://scenes/training_3v3.tscn").instantiate();game.test_mode=true;root.add_child(game)
	game.start_match(false);await ticks(10);game.ai_enabled=false;game.tactics_bridge.set_physics_process(false)
	game.services.rules.state=game.Rules.State.LIVE;game._sync_rule_phase()
	if native:
		observer=Camera3D.new();root.add_child(observer);observer.current=true
	for spec in (["transition"] if "--transition" in OS.get_cmdline_user_args() else ["normal","diagonal","fast","close"]):
		var diagonal:bool=spec=="diagonal"
		fixture();game.player.foot.cancel();game.ball.position=game.player.position+Vector3(.20,.11,-.43);game.ball.previous_position=game.ball.position;game.ball.take(game.player)
		game.player.refresh_pose(1.0/120);var start:Vector3=game.player.position
		var minimum:float=10;var gap:float=0;var contacts:int=0;var controlled:int=0
		var sequence:int=-1
		var speeds:Array=[]
		if spec=="fast":key(KEY_SHIFT,true);await ticks(1);key(KEY_SHIFT,false)
		if spec=="close":key(KEY_CTRL,true)
		key(KEY_S,true)
		if diagonal:key(KEY_A,true)
		for i in (600 if spec=="transition" else 360):
			if spec=="transition":
				if i==120:key(KEY_SHIFT,true);key(KEY_SHIFT,false)
				if i==240:key(KEY_CTRL,true)
				if i==360:key(KEY_CTRL,false)
				if i==480:key(KEY_S,false)
			await ticks(1)
			if i>120:speeds.append(Vector2(game.player.velocity.x,game.player.velocity.z).length())
			var relative:Vector3=game.ball.position-game.player.position;relative.y=0
			minimum=minf(minimum,relative.dot(game.player.body_facing));gap=maxf(gap,relative.length())
			if game.ball.carrier==game.player:controlled+=1
			if game.player.foot.kind=="PULL" and game.player.foot.hit and sequence!=game.player.foot.sequence:contacts+=1;sequence=game.player.foot.sequence
			if i%12==0:rows.append({"case":spec,"speed":game.player.velocity.length(),"phase":game.player.foot.phase,"diagonal":diagonal,"frame":i,"body":game.player.position,"ball":game.ball.position,"front":relative.dot(game.player.body_facing),"gap":relative.length(),"foot":game.player.foot.kind,"hit":game.player.foot.hit,"failure":game.player.foot.contact_failure})
			if native:
				observer.position=game.player.position+Vector3(2,1.3,1);observer.look_at(game.player.position+Vector3(0,.5,-.3))
				if i==180:await capture("retreat_"+spec)
		release_inputs()
		if spec=="fast":key(KEY_SHIFT,true);await ticks(1);key(KEY_SHIFT,false)
		var mean:float=0;var deviation:float=0
		for v in speeds:mean+=float(v)/speeds.size()
		for v in speeds:deviation+=pow(float(v)-mean,2)/speeds.size()
		var details:Dictionary={"case":spec,"tier":game.player.movement_tier,"close":game.player.close_control,"style":game.player.semantic_move_style,"motion":game.player.shared_last_result,"speed_mean":mean,"speed_sd":sqrt(deviation),"speed_min":speeds.min(),"speed_max":speeds.max(),"diagonal":diagonal,"front_min":minimum,"gap_max":gap,"sole_contacts":contacts,"controlled_frames":controlled,"retreat_m":game.player.position.z-start.z}
		check("ball stays in front while retreating "+spec,minimum>.10 and gap<1.25,details)
		check("retreat uses real sole contacts "+spec,contacts>=2 and controlled>300 and game.player.position.z-start.z>.5,details)
	FileAccess.open(evidence+("/retreat_transition.json" if "--transition" in OS.get_cmdline_user_args() else "/retreat_flow.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"rows":rows},"  "))
	game.shutdown_audio();quit(0 if checks.all(func(c):return c.passed) else 1)
