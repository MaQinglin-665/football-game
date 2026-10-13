extends SceneTree
## Pure dictionary planning contracts; no World, contacts or success simulation.
const Director := preload("res://scripts/tactics/tactical_director.gd")
var planner = Director.new()
var checks: Array[Dictionary] = []
var output := ""
func check(name: String, ok: bool) -> void:
	checks.append({"name":name,"ok":ok})
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	var middle: Dictionary = {"id":3,"team":1,"position":Vector3(-4.734,0,-1.14),"velocity":Vector3(.745,0,3.78),"facing":Vector3(.205,0,.979),"foot_idle":false,"can_reach":true,"can_kick":true,"kick_ready":true,"active":true}
	var runner: Dictionary = {"id":5,"team":1,"position":Vector3(-6.037,0,1.638),"velocity":Vector3(-3.13,0,.782),"facing":Vector3(.275,0,-.962),"active":true,"human":false}
	var opponents: Array[Dictionary] = [{"id":1,"team":0,"position":Vector3(8,0,16),"velocity":Vector3.ZERO},{"id":2,"team":0,"position":Vector3(-10,0,17),"velocity":Vector3.ZERO}]
	var snap: Dictionary = {"carrier_id":3,"ball_position":Vector3(-5.117,.11,-.659),"ball_velocity":Vector3(-.848,0,2.986),"field_half_length":18.0,"field_half_width":12.0,"tactical_scale":.4,"small_sided":true,"capabilities":{"brake_deceleration":7.5,"reaction_delay":.16,"receive_speed":6.2,"run_acceleration":6.8,"turn_speed":5.8}}
	var prediction: Dictionary = planner._third_man_preparation(middle,runner,snap)
	check("moving outlet projects forward",prediction.origin.z>snap.ball_position.z)
	check("moving outlet follows measured lateral velocity",prediction.origin.x<snap.ball_position.x)
	check("preparation horizon bounded",prediction.seconds>=.30 and prediction.seconds<=1.20)
	var stationary := snap.duplicate(true)
	stationary.ball_velocity = Vector3.ZERO
	check("stationary ball has no invented displacement",planner._third_man_preparation(middle,runner,stationary).origin==planner._flat(stationary.ball_position))
	planner.roster = {3:{"id":3,"team":1,"role":"attacking_mid"},5:{"id":5,"team":1,"role":"striker"}}
	planner.clock = 3.0
	planner.third_man = {"pass_id":"fixture_source","middle_id":3,"runner_id":5,"team":1,"runner_target":Vector3(-6.369,0,1.645),"origin_x":-4.77,"origin_z":-1.15,"rescore_at":3.6,"deadline":5.2,"state":"CONTROLLED"}
	var old: Vector3 = planner.third_man.runner_target
	planner._update_third_man({}, {3:middle,5:runner,1:opponents[0],2:opponents[1]}, snap)
	check("first controlled tick can revise before old rescore",not planner.third_man.is_empty() and planner.third_man.runner_target!=old)
	check("revision uses preparation origin",not planner.third_man.is_empty() and planner.third_man.preparation_origin==prediction.origin)
	planner.carrier_setup = {"owner_id":3,"heading":Vector3(.249,0,.969),"stable_since":-1.0,"released":false}
	var intent: Dictionary = {}
	var members: Array[Dictionary] = [middle,runner]
	check("no real control evidence still waits",planner._wait_for_control(middle,intent,snap,members,opponents))
	check("heading changes from expired carry to C",planner.carrier_setup.heading.dot(planner._flat(runner.position-snap.ball_position).normalized())>.98)
	check("heading change does not declare control stable",planner.carrier_setup.stable_since<0 and not planner.carrier_setup.released)
	planner.third_man.runner_target = snap.ball_position+Vector3(0,0,2.1)
	planner.third_man.outlet_committed = true
	planner.clock += .25
	var committed: Vector3 = planner.third_man.runner_target
	planner._update_third_man({}, {3:middle,5:runner,1:opponents[0],2:opponents[1]}, snap)
	check("committed outlet cannot retarget",not planner.third_man.is_empty() and planner.third_man.runner_target==committed)
	var close_runner := runner.duplicate()
	close_runner.position = snap.ball_position+Vector3(0,0,1.99)
	check("actual receiver below two metres rejects",not planner._third_man_ready(close_runner,snap.ball_position,opponents,snap))
	var failed: int = checks.filter(func(row):return not row.ok).size()
	var result := {"checks":checks,"failed":failed,"scope":"Pure second-leg planning contracts. No native or real-contact proof implied."}
	if output!="": FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result))
	quit(0 if failed==0 else 1)
