extends SceneTree
## Boundary-only read queries; no scene, physical ownership, success events or PASS.
const Director := preload("res://scripts/tactics/tactical_director.gd")
var planner = Director.new()
var checks: Array[Dictionary] = []
var output := ""
func check(name: String, ok: bool) -> void:
	checks.append({"name":name,"ok":ok})
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	var empty: Array[Dictionary] = []
	var start := Vector3.ZERO
	var target := Vector3(.217,0,0)
	var occupied: Array[Dictionary] = [{"position":Vector3(.217,0,.79)}]
	var middle: Array[Dictionary] = [{"position":Vector3(.1085,0,.797)}]
	var long_block: Array[Dictionary] = [{"position":Vector3(1,0,.79)}]
	var threshold: float = sqrt(.1)
	check("zero route empty station",planner._third_man_run_route_clear(start,start,empty))
	check("217mm empty arrival segment",planner._third_man_run_route_clear(start,target,empty))
	check("below sqrt(.1) empty",planner._third_man_run_route_clear(start,Vector3(threshold-.00001,0,0),empty))
	check("above sqrt(.1) empty",planner._third_man_run_route_clear(start,Vector3(threshold+.00001,0,0),empty))
	check("zero station occupied rejects",not planner._third_man_run_route_clear(target,target,occupied))
	check("short endpoint occupied rejects",not planner._third_man_run_route_clear(start,target,occupied))
	check("short interior blocked although both endpoints outside .8",middle[0].position.distance_to(start)>.8 and middle[0].position.distance_to(target)>.8 and not planner._third_man_run_route_clear(start,target,middle))
	check("long route obstacle rejects",not planner._third_man_run_route_clear(start,Vector3(2,0,0),long_block))
	check("long route matches existing policy",planner._third_man_run_route_clear(start,Vector3(2,0,0),empty)==planner._lane_clear(start,Vector3(2,0,0),empty,.8))
	check("generic short PASS lane still invalid",not planner._lane_clear(start,target,empty,1.2))
	var pressured: Array[Dictionary] = [{"position":Vector3(.217,0,1)}]
	check("route arrival does not waive 2.4m target openness",planner._third_man_run_route_clear(start,target,pressured) and planner._openness(target,pressured)<2.4)
	var defenders: Array[Dictionary] = [{"position":Vector3(3,0,6)},{"position":Vector3(-3,0,5)}]
	var receiver: Dictionary = {"id":5,"team":1,"position":Vector3(0,0,8)}
	var snap: Dictionary = {"ball_position":Vector3.ZERO}
	check("arrival does not waive actual C offside",not planner._onside_receiver(receiver,defenders,snap))
	check("arrival does not waive target offside",not planner._support_onside(receiver.position,1,defenders,snap))
	var pass_block: Array[Dictionary] = [{"position":Vector3.ZERO}]
	var c := Vector3(.217,0,3)
	var goal := Vector3(0,0,3)
	check("arrival clear but B-C PASS line blocked",planner._third_man_run_route_clear(c,goal,pass_block) and planner._openness(goal,pass_block)>=2.4 and not planner._lane_clear(Vector3(0,0,-3),c,pass_block,1.2))
	var failed: int = checks.filter(func(row):return not row.ok).size()
	var report := {"scope":"Pure route-boundary queries only. Does not prove a physical/natural A-B-C chain.","checks":checks,"failed":failed}
	if output!="": FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report))
	quit(0 if failed==0 else 1)
