extends SceneTree
# Offline evaluation only. Ordinary launchers never load this script.
var game:Node
var elapsed:float=0
var scene_path:String="res://scenes/match.tscn"
var duration:float=45
var full_match:bool=false
var checkpoint:float=0
var seed_value:int=390109
var output:String="res://../verification/review.json"
var rows:Array=[]
var contacts:Array=[]
var incidents:Array=[]
var sampled:float=0
var stalled:Dictionary={}
var flagged:Dictionary={}
var last_state:String=""
var last_owner:int=-1
var last_ball:Vector3
var live_seconds:float=0
var setup_ok:bool=false
var finished:bool=false
var camera:Camera3D
class Observer extends Node:
	var host
	func _physics_process(dt:float)->void:host.observe(dt)
func _initialize()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scene="):scene_path=arg.trim_prefix("--scene=")
		if arg=="--full-match":full_match=true;duration=2400
		if arg.begins_with("--seed="):seed_value=int(arg.trim_prefix("--seed="))
		if arg.begins_with("--seconds="):duration=float(arg.trim_prefix("--seconds="))
		if arg.begins_with("--out="):output=arg.trim_prefix("--out=")
	seed(seed_value);call_deferred("begin")
func begin()->void:
	game=load(scene_path).instantiate();game.test_mode=true;root.add_child(game);current_scene=game
	# Keep the UI/input host inert; replace its roster entry with the same AI
	# class used by all other outfielders. No fabricated touches or ball moves.
	var human:Node3D=game.player
	human.process_mode=Node.PROCESS_MODE_DISABLED;human.hide();human.position=Vector3(0,-100,0)
	human.collision_layer=0;human.collision_mask=0
	for child in human.find_children("*","CollisionObject3D",true,false):child.collision_layer=0;child.collision_mask=0
	game.physics_world.actors.erase(human)
	var ai=game.AgentScript.new();ai.name="OfflineBlue10";ai.team=0;ai.jersey=10;ai.match_controller=game;ai.profile=game.physics_profile;ai.role=human.role;ai.lane=human.lane
	game.add_child(ai);game.players[0]=ai;game.agents.append(ai);game.physics_world.register_actor(ai);ai.body_contact.connect(game._on_actor_body_contact.bind(ai))
	preload("res://scripts/player_abilities.gd").attach(ai,game.physics_profile,game.team_size,"--abilities=off" in OS.get_cmdline_user_args())
	for row in game.roster_configuration:
		if int(row.id)==0:row.human=false
	game.tactical_director.configure(game.roster_configuration,{0:game.Director.SHORT_PASS,1:game.Director.SHORT_PASS})
	game.contact_hub.contact_resolved.connect(func(e):
		if e.get("success",false):
			var a=e.get("actor")
			contacts.append({"t":elapsed,"actor":game.players.find(a),"action":e.get("action",""),"receiver":game.players.find(a.foot.receiver) if is_instance_valid(a) else -1,"ball":game.ball.position,"velocity":game.ball.velocity,"owner":game.players.find(game.ball.carrier)})
	)
	game.settings_menu.values.volume=0;game.settings_menu.apply_values(false)
	# Training's normal opening otherwise gives the ball to the disabled input
	# host. Use its existing defensive opening, with ordinary opponent pressure.
	if is_instance_valid(game.training_mode):
		game.training_mode.defensive_opening=true;game.training_mode.low_pressure=false
	game.start_match(false)
	if seed_value%2==0 and not is_instance_valid(game.training_mode):game.services.start_match(game.rule_roster(),1);game._sync_rule_phase()
	setup_ok=game.players.size()==game.team_size*2 and game.physics_world.actors.size()==game.team_size*2 and game.players.all(func(a):return not a.is_human)
	if not setup_ok:push_error("Offline roster must have exactly the configured AI roster");quit(2);return
	if DisplayServer.get_name()!="headless":
		camera=Camera3D.new();game.add_child(camera);camera.current=true;camera.position=Vector3(0,30,42);camera.look_at(Vector3.ZERO)
	var observer:=Observer.new();observer.host=self;observer.process_physics_priority=100;root.add_child(observer)
func observe(dt:float)->void:
	if finished:return
	elapsed+=dt
	var state:String=game.services.rules.state_name()
	var live:bool=state=="LIVE"
	if live:live_seconds+=dt
	if state!=last_state:
		incidents.append({"t":elapsed,"type":"rule_state","state":state,"ball":game.ball.position,"restart":game.services.rules.restart.duplicate(true),"last_owner":last_owner})
		last_state=state
	if elapsed-sampled>=.20:
		sampled=elapsed
		var owner:int=game.players.find(game.ball.carrier)
		var plan:Dictionary=game.tactical_director.receive_plan.active
		var jobs:Array=[]
		for a in game.players:
			var id:int=game.players.find(a)
			var near:float=INF
			for enemy in game.players:
				if enemy.team!=a.team:near=minf(near,game.flat_distance(a.position,enemy.position))
			var gap:float=game.flat_distance(a.position,game.ball.position)
			var waiting:bool=live and id==owner and a.velocity.length()<.25 and not a.is_goalkeeper and a.foot.kind not in ["PASS","SHOT"]
			stalled[id]=float(stalled.get(id,0))+.20 if waiting else 0.0
			if float(stalled[id])>.8 and not flagged.get(id,false):
				incidents.append({"t":elapsed,"type":"carrier_stall_candidate","id":id,"opponent_gap":near,"ball_gap":gap,"foot":a.foot.kind,"failure":a.foot.contact_failure,"reason":a.tactical_intent.get("reason",""),"pending":a.pending_kick.duplicate(true)})
				flagged[id]=true
			if not waiting:flagged[id]=false
			if id==owner or id==int(plan.get("receiver_id",-1)) or gap<2:
				jobs.append({"id":id,"position":a.position,"velocity":a.velocity,"gap":gap,"opponent_gap":near,"target":a.target,"foot":a.foot.kind,"hit":a.foot.hit,"failure":a.foot.contact_failure,"reason":a.tactical_intent.get("reason",""),"pace":a.tactical_pace,"pending":not a.pending_kick.is_empty()})
		rows.append({"t":elapsed,"live":live,"ball":game.ball.position,"ball_velocity":game.ball.velocity,"owner":owner,"receiver":plan.get("receiver_id",-1),"jobs":jobs})
		if owner>=0:last_owner=owner
		last_ball=game.ball.position
	if elapsed-checkpoint>=60:
		checkpoint=elapsed
		print("MATCH_PROGRESS t=",elapsed," live=",live_seconds," state=",state," stats=",game.stats)
	if elapsed<duration and (not full_match or state!="FULL_TIME"):return
	finished=true
	var result:Dictionary={"full_time":state=="FULL_TIME","match_length":game.match_length,"seed":seed_value,"duration_sim_seconds":elapsed,"live_seconds":live_seconds,"kickoff_team":0 if seed_value%2 else 1,"all_ai":setup_ok,"actors":game.players.size(),"physics_actors":game.physics_world.actors.size(),"stats":game.stats,"rows":rows,"contacts":contacts,"incidents":incidents,"receive_events":game.tactical_director.receive_plan.events,"scope":"Natural regulation match, 22 AI, human host removed from physics and roster only in this offline harness. No teleport after formation, forced pass, contact or possession. Candidates are diagnostic flags, not automatically proven bugs. Fixed simulation delta; not FPS evidence."}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("REVIEW_DONE ",seed_value," live=",live_seconds," contacts=",contacts.size()," incidents=",incidents.size())
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output+".png")
	game.shutdown_audio();quit()
