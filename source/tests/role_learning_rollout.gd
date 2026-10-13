extends "res://tests/learning_rollout.gd"
# Local exercise fixtures are separate from natural full matches. Only initial
# positions vary; all movement, possession, tackles and kicks then use the game.
var drill:String="match"
var local_ids:Array=[]
func begin()->void:
	super.begin()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--drill="):drill=arg.trim_prefix("--drill=")
	if drill=="match":return
	assert(game.team_size==3)
	game.training_mode.low_pressure=false
	game.training_mode.set_physics_process(false)
	var random:=RandomNumberGenerator.new();random.seed=seed_value+7711
	var attack_team:int=seed_value%2
	var attack:Vector3=Vector3(0,0,-1 if attack_team==0 else 1)
	var attacker:int=2 if attack_team==0 else 5
	var defender:int=4 if attack_team==0 else 1
	local_ids=[attacker,defender]
	if drill in ["pair","triangle"]:local_ids.append(0 if attack_team==0 else 3);local_ids.append(3 if attack_team==0 else 0)
	if drill=="triangle":local_ids=range(6)
	for id in range(game.players.size()):
		var a:Node3D=game.players[id]
		a.foot.cancel("local_exercise_start");a.pending_kick.clear();a.velocity=Vector3.ZERO
		if id not in local_ids:
			a.set_match_active(false);a.process_mode=Node.PROCESS_MODE_DISABLED;a.hide();a.position=Vector3(0,-100,0)
			a.collision_layer=0;a.collision_mask=0
			for child in a.find_children("*","CollisionObject3D",true,false):child.collision_layer=0;child.collision_mask=0
			game.physics_world.actors.erase(a)
		else:
			a.set_match_active(true);a.show()
			a.facing=attack if a.team==attack_team else -attack;a.body_facing=a.facing;a.face_target=a.facing
	var start:Vector3=Vector3(random.randf_range(-7,7),.002,-attack.z*random.randf_range(2,6))
	game.players[attacker].position=start
	game.players[defender].position=start+attack*random.randf_range(2.3,4.5)+Vector3(random.randf_range(-1.3,1.3),0,0)
	for id in local_ids:
		if id in [attacker,defender]:continue
		var a:Node3D=game.players[id]
		var flank:float=-1 if start.x>0 else 1
		a.position=start+Vector3(flank*random.randf_range(3.5,6),0,0)+attack*(random.randf_range(-2,1) if a.team==attack_team else random.randf_range(2,5))
		if drill=="triangle" and a.get_meta("abilities",{}).get("role","")=="sweeper" and a.team==attack_team:a.position=start-attack*4.0
	for id in local_ids:game.players[id].reset_physics_interpolation()
	game.ball.reset(start+attack*.5);game.ball.set_held(false)
	# Do not grant possession: the first control still needs a real shoe contact.
	game.ball.detach();game.tactical_director.reset();game.tactics_bridge.clock=0
	FileAccess.open(output+".fixture.json",FileAccess.WRITE).store_string(JSON.stringify({"drill":drill,"seed":seed_value,"active_ids":local_ids,"initial_attack_team":attack_team,"physics_actors":game.physics_world.actors.size(),"scope":"Randomized local drill, not natural-match evidence; no resets/teleports after this initial fixture."}))

func observe(dt:float)->void:
	if drill!="match" and elapsed>.1 and game.services.rules.state_name()!="LIVE":
		game.set_meta("drill_terminal",true);duration=elapsed+dt
	super.observe(dt)
