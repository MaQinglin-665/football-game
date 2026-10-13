extends SceneTree
var checks:Array=[]
var output:String=""
func _initialize()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):output=arg.trim_prefix("--out=")
	call_deferred("run")
func check(label:String,ok:bool)->void:
	checks.append({"label":label,"passed":ok});print("PASS " if ok else "FAIL ",label)
func run()->void:
	AudioServer.set_bus_mute(0,true)
	for small in [true,false]:
		var game:Node=load("res://scenes/training_3v3.tscn" if small else "res://scenes/match.tscn").instantiate()
		game.test_mode=true;root.add_child(game)
		await process_frame
		var identities:Array=[]
		for actor in game.players:identities.append([actor.get_instance_id(),actor.jersey])
		var slots:Array=[]
		for row in game.roster_configuration:
			if int(row.team)==0 and not row.is_goalkeeper:slots.append(row.slot)
		check("valid outfield slot count "+str(small),slots.size()==(3 if small else 10))
		check("keeper excluded "+str(small),not game.Selection.choose(game,"GK"))
		for slot in slots:
			game.show_menu()
			var picker:Control=game.hud.menu.get_node("FormationPicker")
			picker.buttons[slot].pressed.emit()
			var chosen:bool=game.Selection.human_row(game).slot==slot
			var ids:Array=[];var human_count:int=0;var stable:bool=true
			for row in game.roster_configuration:
				ids.append(int(row.id));human_count+=1 if row.human else 0
				var actor:Node=game.players[int(row.id)]
				stable=stable and actor.get_instance_id()==identities[int(row.id)][0] and actor.jersey==identities[int(row.id)][1] and row.jersey==actor.jersey
				for mesh in actor.avatar.mesh_nodes:
					if str(mesh.name)=="BodyCore":
						stable=stable and int(mesh.get_active_material(0).get_shader_parameter("jersey_number"))==actor.jersey
			check("identity/material/occupants "+str(small)+" "+slot,chosen and stable and human_count==1 and ids.size()==game.players.size() and game.Selection.human_row(game).slot==slot and game.players[0]==game.player)
			game.start_match(false)
			var start:Vector3=game.player.position
			game.restart_current()
			var context:Dictionary=game.input_bridge.authoritative_context()
			check("start/restart/input "+str(small)+" "+slot,start.is_equal_approx(game.player.position) and context.position==slot and context.actor_id.begins_with("blue-10:") and game.tactical_director.roster[0].slot==slot)
			game.show_menu()
		if not small:
			game.Selection.choose(game,"LB");game.start_match(false)
			var before:Vector3=game.tactics_bridge._kickoff_shape_target(game.player,game.attack_direction(0))
			game.services.rules._end_half()
			game.services.rules.step(game.services.configuration.half_time_seconds+.01,game.ball_snapshot(),game.rule_roster())
			var after:Vector3=game.tactics_bridge._kickoff_shape_target(game.player,game.attack_direction(0))
			check("halftime flips selected slot target and retains identity",Vector2(before.x,before.z).is_equal_approx(-Vector2(after.x,after.z)) and game.Selection.human_row(game).slot=="LB" and game.player.jersey==10)
		game.pause_match();game.shutdown_audio();game.queue_free()
		for i in 3:await process_frame
	if not output.is_empty():FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(checks,"  "))
	quit(0 if checks.all(func(row):return row.passed) else 1)
