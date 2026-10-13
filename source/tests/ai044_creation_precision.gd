extends SceneTree
## Isolated pure producer fixture, using the failed trace's full-precision C boundary.
## Other fields isolate selection; this is not an exact World replay or contact proof.
const Director := preload("res://scripts/tactics/tactical_director.gd")
var checks: Array[Dictionary] = []
var output := ""
func check(name: String, ok: bool) -> void:
	checks.append({"name":name,"ok":ok})
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	var planner = Director.new()
	var candidate: Dictionary = {"id":5,"team":1,"active":true,"human":false,"position":Vector3(1.04568088054657,.002,.135062977671623),"velocity":Vector3(-2.380114,0,-3.367115),"facing":Vector3(-.680973,0,-.732309)}
	var origin := Vector3(-6.04794359207153,.11,-4.7864670753479)
	var snap: Dictionary = {"carrier_id":-1,"ball_position":Vector3(-7.669632,.111786,-9.237267),"ball_velocity":Vector3(3.307566,.096868,9.077769),"field_half_length":18.0,"field_half_width":12.0,"small_sided":true,"tactical_scale":.4,"capabilities":{"reaction_delay":.16,"receive_speed":6.2,"run_acceleration":6.8,"turn_speed":5.8,"brake_deceleration":7.5}}
	var opponents: Array[Dictionary] = [{"id":0,"team":0,"position":Vector3(-10,.002,14),"velocity":Vector3.ZERO},{"id":1,"team":0,"position":Vector3(4.903419,.002,13.38326),"velocity":Vector3(-2.469838,0,-3.655742)},{"id":2,"team":0,"position":Vector3(9.03867,.002,14.29934),"velocity":Vector3(-2.169108,0,-3.841843)}]
	planner.roster = {3:{"id":3,"team":1,"role":"attacking_midfielder","duty":"link"},4:{"id":4,"team":1,"role":"center_back","duty":"hold"},5:{"id":5,"team":1,"role":"striker","duty":"finish"}}
	var minimum_scalar: float = candidate.position.z+maxf(.6,1.5*.4)
	var minimum_coordinate: float = Vector2(0.0,minimum_scalar).y
	check("recorded standard-build scalar comparison falsely rejects",minimum_coordinate<minimum_scalar)
	var result: Dictionary = planner._third_man_run_point(candidate,origin,opponents,snap,1.5)
	check("recorded boundary has a production candidate",not result.is_empty())
	check("candidate still advances C by coordinate floor",not result.is_empty() and result.point.z>=minimum_coordinate)
	check("candidate still satisfies actual route and offside filters",not result.is_empty() and planner._third_man_run_route_clear(candidate.position,result.point,opponents) and planner._support_onside(result.point,1,opponents,snap))
	planner.clock = 1.0
	var middle: Dictionary = {"id":3,"team":1,"active":true,"human":false,"position":Vector3(-4.853515,.002,-2.420356)}
	var passer: Dictionary = {"id":4,"team":1,"active":true,"human":false,"position":Vector3(-7.823267,.002,-9.794357)}
	var by_id: Dictionary = {3:middle,4:passer,5:candidate,0:opponents[0],1:opponents[1],2:opponents[2]}
	var reception: Dictionary = {"pass_id":"pure_fixture_only","first_pass_action":"PASS","receiver_id":3,"passer_id":4,"receive_point":origin,"arrival_time":1.5,"deadline":6.9}
	planner._update_third_man(reception,by_id,snap)
	check("empty producer creates RUNNING C rather than seeded CONTROLLED",not planner.third_man.is_empty() and planner.third_man.state=="RUNNING" and int(planner.third_man.runner_id)==5)
	check("producer keeps distinct A B C",not planner.third_man.is_empty() and planner.third_man.passer_id==4 and planner.third_man.middle_id==3 and planner.third_man.runner_id==5)
	var near_line: Array[Dictionary] = [{"id":1,"team":0,"position":Vector3(8,0,.6),"velocity":Vector3.ZERO},{"id":2,"team":0,"position":Vector3(-8,0,1.0),"velocity":Vector3.ZERO}]
	check("temporary offside movement candidate remains available",not planner._third_man_run_point(candidate,origin,near_line,snap,1.5).is_empty())
	var close_runner := candidate.duplicate()
	close_runner.position = origin+Vector3(0,0,1.99)
	planner.third_man.runner_target = close_runner.position
	check("actual B-C below two metres still rejects",not planner._third_man_ready(close_runner,origin,opponents,snap))
	var failed: int = checks.filter(func(row):return not row.ok).size()
	var report := {"scope":"Pure coordinate and initial-producer fixture; no real PASS, shoe, World or natural-chain proof.","checks":checks,"failed":failed,"scalar_floor":minimum_scalar,"coordinate_floor":minimum_coordinate,"selected":result}
	if output!="": FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report))
	quit(0 if failed==0 else 1)
