extends "res://tests/integration_checks.gd"
var rows:Array=[]
var observer:Camera3D
func run()->void:
	game=load("res://scenes/match.tscn" if "--eleven" in OS.get_cmdline_user_args() else "res://scenes/training_3v3.tscn").instantiate();game.test_mode=true;root.add_child(game)
	game.start_match(false);await ticks(10);game.ai_enabled=false;game.tactics_bridge.set_physics_process(false)
	game.services.rules.state=game.Rules.State.LIVE;game._sync_rule_phase()
	if native:
		observer=Camera3D.new();root.add_child(observer);observer.current=true
	for diagonal in [false,true]:
		fixture();game.player.foot.cancel();game.ball.position=game.player.position+Vector3(.20,.11,-.43);game.ball.previous_position=game.ball.position;game.ball.take(game.player)
		game.player.refresh_pose(1.0/120);var start:Vector3=game.player.position
		var minimum:float=10;var gap:float=0;var contacts:int=0;var controlled:int=0
		var sequence:int=-1
		key(KEY_S,true)
		if diagonal:key(KEY_A,true)
		for i in 360:
			await ticks(1)
			var relative:Vector3=game.ball.position-game.player.position;relative.y=0
			minimum=minf(minimum,relative.dot(game.player.body_facing));gap=maxf(gap,relative.length())
			if game.ball.carrier==game.player:controlled+=1
			if game.player.foot.kind=="PULL" and game.player.foot.hit and sequence!=game.player.foot.sequence:contacts+=1;sequence=game.player.foot.sequence
			if i%12==0:rows.append({"diagonal":diagonal,"frame":i,"body":game.player.position,"ball":game.ball.position,"front":relative.dot(game.player.body_facing),"gap":relative.length(),"foot":game.player.foot.kind,"hit":game.player.foot.hit,"failure":game.player.foot.contact_failure})
			if native:
				observer.position=game.player.position+Vector3(2,1.3,1);observer.look_at(game.player.position+Vector3(0,.5,-.3))
				if i==180:await capture("retreat_"+str(diagonal))
		release_inputs()
		var details:Dictionary={"diagonal":diagonal,"front_min":minimum,"gap_max":gap,"sole_contacts":contacts,"controlled_frames":controlled,"retreat_m":game.player.position.z-start.z}
		check("ball stays in front while retreating "+str(diagonal),minimum>.10 and gap<1.25,details)
		check("retreat uses real sole contacts "+str(diagonal),contacts>=2 and controlled>300 and game.player.position.z-start.z>.5,details)
	FileAccess.open(evidence+"/back_pull.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"rows":rows},"  "))
	game.shutdown_audio();quit(0 if checks.all(func(c):return c.passed) else 1)
