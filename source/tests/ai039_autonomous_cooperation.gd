extends SceneTree
## One declared fixture; then six actors, World and rules run without writes.
var game: Node
var actor: Node3D
var scenario := "rear"
var output := ""
var frame := 0
var contacts: Array[Dictionary] = []
var samples: Array[Dictionary] = []
var checks: Array[Dictionary] = []
var control_position := Vector3.ZERO
var confirmed := false
var safe_progress := 0.0
var unforced_losses := 0
var previous_owned := false
var last_pass_frame := -100
var support_seen := false
var defense_seen := false
var return_seen := false
var third_man_states:Array=[]
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		if arg.begins_with("--scenario="): scenario = arg.trim_prefix("--scenario=")
	call_deferred("run")
func vector(v: Vector3) -> Array: return [v.x,v.y,v.z]
func run() -> void:
	game = load("res://scenes/training_3v3.tscn").instantiate()
	game.test_mode = true
	root.add_child(game)
	for _i in 5: await process_frame
	game.hud.menu.get_node("StartMatch").pressed.emit()
	for _i in 8: await physics_frame
	assert(game.services.rules.state==game.Rules.State.LIVE)
	game.training_mode.low_pressure = false
	actor = game.players[3] # Autonomous yellow carrier, not the human.
	for id in game.players.size():
		var p: Node3D = game.players[id]
		p.position = Vector3(-8+8*(id%3),.002,12 if p.team==0 else 6)
		p.velocity = Vector3.ZERO
		p.foot.cancel()
		p.action_cooldown = 0.0
		p.set_move_intent(Vector3.ZERO)
		if not p.is_human:
			p.pending_kick.clear()
			p.facing = Vector3.FORWARD if p.team==0 else Vector3.BACK
			p.body_facing = p.facing
			p.face_target = p.facing
			p.target = p.position
	actor.position = Vector3(0,.002,0)
	if scenario=="cooperation":
		# Outside shooting range: exercise a short forward combination rather
		# than treating a legitimate close-range shot as a failed pass decision.
		actor.position.z = -6.0
		game.players[4].position = Vector3(-5,.002,0)
		game.players[5].position = Vector3(5,.002,1)
	actor.facing = Vector3.FORWARD
	actor.body_facing = actor.facing
	actor.face_target = Vector3.BACK
	game.ball.reset(actor.position+Vector3(.27,.11,.58))
	game.ball.velocity = Vector3(0,0,1.0)
	game.pass_receiver = null
	game.pass_receiver_timer = 0.0
	game.tactical_director.reset()
	game.tactics_bridge.clock = .20
	game.tactics_bridge.refresh_now()
	for p in game.players:
		p.refresh_pose(0)
		p.get_node("LowerBallContacts").update_from_skeleton(0.0)
	game.contact_hub.contact_resolved.connect(func(e: Dictionary):
		var a: Variant = e.get("actor",null)
		if not is_instance_valid(a): return
		contacts.append({"frame":frame,"actor":game.players.find(a),"action":e.get("action",""),"success":e.get("success",false),"owner":game.players.find(game.ball.carrier),"ball":vector(game.ball.position),"shoe":a.foot.actual_contact.duplicate(true)})
		if a==actor and e.get("success",false):
			if e.get("action","")=="PASS": last_pass_frame = frame
			if game.ball.carrier==actor and e.get("action","") in ["RECEIVE","CLOSE","CONTROL","PULL","TURN","SETTLE"] and not confirmed:
				confirmed = true
				control_position = actor.position)
	# Fixture ends here: no subsequent position/velocity/ownership/plan edits.
	for _i in 720:
		await physics_frame
		frame += 1
		if frame%12==0:third_man_states.append({"frame":frame,"plan":game.tactical_director.third_man.duplicate(true),"last_plan":game.tactical_director.third_man_last.duplicate(true),"receive_plan":game.tactical_director.receive_plan.active.duplicate(true)})
		var owned: bool = game.ball.carrier==actor
		if previous_owned and not owned and frame-last_pass_frame>6: unforced_losses += 1
		previous_owned = owned
		if confirmed and owned and game.ball.reception_ready(actor): safe_progress = maxf(safe_progress,(actor.position-control_position).z)
		var obs: Dictionary = game.tactics_bridge.observation
		if obs.get("teams",{}).get(1,{}).get("support_ids",[]).size()>=2: support_seen = true
		var press := 0
		var cover := 0
		var holder := 0
		for task in game.tactical_director.defense_debug_snapshot().get("tasks",{}).values():
			if int(task.team)!=0: continue
			press += 1 if task.task=="PRESS" else 0
			cover += 1 if task.task=="COVER" else 0
			holder += 1 if task.task in ["HOLD","RECOVER"] else 0
		if owned and press==1 and cover==1: defense_seen = true
		var plan: Dictionary = obs.get("give_go_plan",{})
		if not plan.is_empty() and plan.get("state","") in ["RETURN_WINDOW","RETURN_READY","RETURN_IN_FLIGHT"]: return_seen = true
		if frame>=350 and frame<=650:
			var offset: Vector3 = game.ball.position-actor.position
			offset.y = 0
			var aim: Vector3 = actor.pending_kick.get("direction",Vector3.ZERO)
			samples.append({"frame":frame,"owner":game.players.find(game.ball.carrier),"actor":vector(actor.position),"ball":vector(game.ball.position),"ball_velocity":vector(game.ball.velocity),"actor_velocity":vector(actor.velocity),"relative_speed":(game.ball.velocity-actor.velocity).length(),"gap":offset.length(),"facing":vector(actor.facing),"action":actor.foot.kind,"foot_phase":actor.foot.phase,"foot_idle":actor.foot.idle(),"pending":not actor.pending_kick.is_empty(),"pending_age":actor.pending_age,"pending_aim":vector(aim),"pending_receiver_id":actor.pending_kick.get("receiver_id",-1),"pending_facing_dot":actor.facing.dot(aim),"reception_ready":game.ball.reception_ready(actor),"can_kick":game.ball.can_kick(actor),"action_cooldown":actor.action_cooldown,"reason":actor.tactical_intent.get("reason",""),"support_ids":obs.get("teams",{}).get(1,{}).get("support_ids",[]),"press":press,"cover":cover,"holder":holder})
	var passes := contacts.filter(func(c): return c.success and c.action=="PASS")
	checks.append({"name":"actual rear shoe control","ok":confirmed})
	checks.append({"name":"stable turn then advance or physical pass","ok":safe_progress>1.0 or passes.any(func(c):return c.actor==game.players.find(actor))})
	checks.append({"name":"no repeated unforced reacquisition loop","ok":unforced_losses<=2})
	if scenario=="cooperation":
		checks.append({"name":"two support offers observed","ok":support_seen})
		checks.append({"name":"physical AI pass","ok":not passes.is_empty()})
		checks.append({"name":"separate presser and cover observed","ok":defense_seen})
	var failed := checks.filter(func(c):return not c.ok).size()
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"scenario":scenario,"declared_fixture":true,"post_setup_state_writes":false,"all_six_active":game.players.size()==6 and game.ai_enabled,"safe_progress":safe_progress,"unforced_owner_losses":unforced_losses,"support_seen":support_seen,"defense_seen":defense_seen,"give_go_return_window_seen":return_seen,"completed_one_two_proven":false,"third_man_states":third_man_states,"third_man_observed":third_man_states.any(func(r):return not r.plan.is_empty()),"third_man_completed_observed":third_man_states.any(func(r):return r.get("last_plan",{}).get("state","")=="COMPLETED"),"scope":"Existing autonomous6actor/6second cooperation fixture, real control/pass and natural planner; no injected next/third_man plan. Historical checks retained. Third-man completion reported separately and not inferred from pass counts.","checks":checks,"failed":failed,"contacts":contacts,"samples":samples},"\t"))
	game.pause_match()
	game.shutdown_audio()
	game.queue_free()
	game = null
	for _i in 4: await process_frame
	quit(0 if failed==0 else 1)
