extends SceneTree
## Pure policy checks only. Physical offside-at-kick/involvement Rules are absent in host.
const Director := preload("res://scripts/tactics/tactical_director.gd")
const GiveGo := preload("res://scripts/tactics/give_go_plan.gd")
var checks: Array[Dictionary] = []
var output := ""
func check(name: String, ok: bool) -> void:
	checks.append({"name":name,"ok":ok})
func fixture(team: int) -> Dictionary:
	var planner = Director.new()
	var face: Vector3 = planner._world(Vector2(0,1),team)
	var ball: Vector3 = planner._world(Vector2(2,1),team)+Vector3.UP*.11
	var middle: Dictionary = {"id":3,"team":team,"position":planner._flat(ball)-face*.44,"velocity":Vector3.ZERO,"facing":face,"foot_idle":true,"foot_action":"","can_reach":true,"can_kick":true,"kick_ready":true,"active":true,"human":false}
	var runner: Dictionary = {"id":5,"team":team,"position":planner._world(Vector2(2,3.8),team),"velocity":Vector3.ZERO,"facing":-face,"active":true,"human":false}
	var passer: Dictionary = {"id":4,"team":team,"position":planner._world(Vector2(2,-3),team),"velocity":Vector3.ZERO,"facing":face,"active":true,"human":false}
	var opposition: Array[Dictionary] = [{"id":0,"team":1-team,"position":planner._world(Vector2(-10,15),team),"velocity":Vector3.ZERO,"active":true},{"id":1,"team":1-team,"position":planner._world(Vector2(-8,4),team),"velocity":Vector3.ZERO,"active":true},{"id":2,"team":1-team,"position":planner._world(Vector2(8,5),team),"velocity":Vector3.ZERO,"active":true}]
	var players: Array[Dictionary] = [opposition[0],opposition[1],opposition[2],middle,passer,runner]
	var snap: Dictionary = {"players":players,"carrier_id":3,"ball_position":ball,"ball_velocity":Vector3.ZERO,"field_half_length":18.0,"field_half_width":12.0,"small_sided":true,"tactical_scale":.4,"capabilities":{"reaction_delay":.16,"receive_speed":6.2,"run_acceleration":6.8,"turn_speed":5.8,"brake_deceleration":7.5}}
	planner.roster = {3:{"id":3,"team":team,"role":"attacking_midfielder","duty":"link"},4:{"id":4,"team":team,"role":"center_back","duty":"hold"},5:{"id":5,"team":team,"role":"striker","duty":"finish"}}
	planner.clock = 1.0
	return {"planner":planner,"middle":middle,"runner":runner,"opposition":opposition,"snapshot":snap,"by_id":{0:opposition[0],1:opposition[1],2:opposition[2],3:middle,4:passer,5:runner},"team":team}
func seed_third(f: Dictionary, target_depth: float) -> void:
	var planner = f.planner
	var ball: Vector3 = f.snapshot.ball_position
	planner.third_man = {"pass_id":"pure_policy_fixture","passer_id":4,"middle_id":3,"runner_id":5,"team":f.team,"runner_target":planner._world(Vector2(2,target_depth),int(f.team)),"state":"CONTROLLED","deadline":3.2,"rescore_at":4.0,"origin_x":ball.x,"origin_z":ball.z,"preparation_origin":planner._flat(ball),"receiver_onside_now":true,"outlet_committed":false}
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	for team in [0,1]:
		var f: Dictionary = fixture(team)
		var planner = f.planner
		f.runner.position = planner._world(Vector2(2,6),team)
		var moving: Dictionary = planner._third_man_run_point(f.runner,f.snapshot.ball_position,f.opposition,f.snapshot,2.0)
		check("team%s offside runner/goal may have a movement candidate"%team,not moving.is_empty())
		f.runner.position = planner._world(Vector2(2,3.8),team)
		seed_third(f,5.3)
		planner._update_third_man({},f.by_id,f.snapshot)
		check("team%s future goal offside does not cancel plan"%team,not planner.third_man.is_empty() and planner.third_man.target_offside_now and planner.third_man.receiver_onside_now and planner.third_man.deadline==3.2)
		f.runner.velocity = planner._world(Vector2(0,5),team)
		var intent: Dictionary = {"reason":"third_man_prepare_outlet","action":"NONE"}
		planner._consider_third_man_pass(f.middle,intent,f.by_id,f.snapshot)
		check("team%s onside recipient may be led beyond current line"%team,intent.action=="PASS" and planner._local(intent.get("aim_point",Vector3.ZERO),team).y>5.0)
		f.runner.position = planner._world(Vector2(2,6),team)
		f.runner.velocity = Vector3.ZERO
		seed_third(f,6.2)
		intent = {"reason":"third_man_prepare_outlet","action":"NONE"}
		planner._consider_third_man_pass(f.middle,intent,f.by_id,f.snapshot)
		check("team%s currently offside recipient does not get PASS decision"%team,intent.action=="NONE")
		planner._update_third_man({},f.by_id,f.snapshot)
		check("team%s temporary offside chooses recovery within original deadline"%team,not planner.third_man.is_empty() and planner.third_man.recovering and not planner.third_man.receiver_onside_now and planner._local(planner.third_man.runner_target,team).y<6.0 and planner.third_man.deadline==3.2)
		planner.clock = 3.2
		planner._update_third_man({},f.by_id,f.snapshot)
		check("team%s recovery cannot extend the finite deadline"%team,planner.third_man.is_empty() and planner.third_man_last.get("cancel_reason","")=="participant_unavailable_or_timeout")
		var give_go = GiveGo.new()
		give_go.roster = planner.roster.duplicate(true)
		give_go.active = {"pass_id":"pure_policy_fixture","runner_id":5,"wall_id":3,"team":team,"state":"RUNNING","deadline":3.2,"runner_start":planner._world(Vector2(2,1),team),"runner_goal":planner._world(Vector2(2,7),team),"return_target":Vector3.ZERO,"return_pass_id":"","wall_controlled_at":.5}
		var running: Dictionary = give_go.tick(f.snapshot,{"active":{"pass_id":"pure_policy_fixture"}},1.0)
		check("team%s give-go offside run is not an automatic cancellation"%team,not running.is_empty() and running.state=="RUNNING" and running.receiver_offside_now)
		give_go.active.state = "RETURN_WINDOW"
		var waiting: Dictionary = give_go.tick(f.snapshot,{},1.1)
		check("team%s give-go waits for current recipient instead of canceling"%team,not waiting.is_empty() and not waiting.return_requested and waiting.receiver_offside_now)
		f.runner.position = planner._world(Vector2(2,3.8),team)
		f.runner.velocity = planner._world(Vector2(0,5),team)
		var returned: Dictionary = give_go.tick(f.snapshot,{},1.2)
		check("team%s give-go current recipient check permits future lead"%team,not returned.is_empty() and returned.return_requested and returned.target_offside_now and not returned.receiver_offside_now)
		give_go.tick(f.snapshot,{},3.2)
		check("team%s give-go wait is finite"%team,give_go.active.is_empty() and give_go.last_plan.get("cancel_reason","")=="deadline")
	var failed: int = checks.filter(func(row):return not row.ok).size()
	var report := {"scope":"20 mirrored pure planning decisions; no contact injection or natural chain proof.","checks":checks,"failed":failed,"physical_offside_at_kick_and_involvement":"HOST_RULES_MISSING per static audit; not implemented or validated by these checks"}
	if output!="": FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report))
	quit(0 if failed==0 else 1)
