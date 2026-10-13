extends SceneTree
## Isolated planning lifetime checks, not World or real ABC proof.
const Director := preload("res://scripts/tactics/tactical_director.gd")
var checks: Array[Dictionary] = []
var output := ""
func check(label: String, ok: bool) -> void:
	checks.append({"name":label,"ok":ok})
func seeded(at: float) -> Variant:
	var p = Director.new()
	p.clock = at
	p.roster = {3:{"id":3,"team":1,"role":"attacking_midfielder","duty":"link"},4:{"id":4,"team":1,"role":"center_back","duty":"hold"},5:{"id":5,"team":1,"role":"striker","duty":"finish"}}
	p.third_man = {"state":"RUNNING","pass_id":"1:126:4:4","first_contact":"1:126:4:4","passer_id":4,"middle_id":5,"runner_id":3,"team":1,"runner_target":Vector3(-5.115943,0,-1.267516),"origin_x":-3.515943,"origin_z":-4.067516,"rescore_at":1.7,"started_at":1.1,"deadline":5.1,"source":"confirmed_A_to_B_pass"}
	return p
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	var by_id: Dictionary = {3:{"id":3,"team":1,"position":Vector3(-7.446671,.002,-3.675488),"velocity":Vector3(.426611,0,-2.047994),"facing":Vector3(0,0,-1)},4:{"id":4,"team":1,"position":Vector3(-6,.002,-6),"velocity":Vector3.ZERO},5:{"id":5,"team":1,"position":Vector3(-2.833496,.002,-4.009881),"velocity":Vector3(-.412376,0,-2.733711),"facing":Vector3(0,0,1),"foot_idle":true},0:{"id":0,"team":0,"position":Vector3(-10,.002,14),"velocity":Vector3.ZERO},1:{"id":1,"team":0,"position":Vector3(4,.002,12),"velocity":Vector3.ZERO},2:{"id":2,"team":0,"position":Vector3(8,.002,13),"velocity":Vector3.ZERO}}
	var snap: Dictionary = {"carrier_id":-1,"ball_position":Vector3(-4.272543,.109817,-4.601555),"ball_velocity":Vector3(4.963656,0,3.503542),"field_half_length":18.0,"field_half_width":12.0,"small_sided":true,"tactical_scale":.4,"capabilities":{"reaction_delay":.16,"receive_speed":6.2,"run_acceleration":6.8,"turn_speed":5.8,"brake_deceleration":7.5}}
	var reception: Dictionary = {"pass_id":"1:126:4:4","receive_point":Vector3(7.861104,.11,3.962845),"arrival_time":4.51666666666667}
	var p = seeded(1.51666666666667)
	var target: Vector3 = p.third_man.runner_target
	p._update_third_man(reception,by_id,snap)
	check("recorded transient predicted-origin excursion keeps RUNNING until old rescore",not p.third_man.is_empty() and p.third_man.state=="RUNNING")
	check("no identity target deadline or rescore extension",not p.third_man.is_empty() and p.third_man.pass_id=="1:126:4:4" and p.third_man.runner_target==target and p.third_man.deadline==5.1 and p.third_man.rescore_at==1.7)
	p.clock = 1.64166666666667
	reception.receive_point = Vector3(-1.122977,.11,-2.193067)
	reception.arrival_time = 2.84166666666667
	p._update_third_man(reception,by_id,snap)
	check("recorded next prediction returns into original range",not p.third_man.is_empty() and p.third_man.state=="RUNNING")
	p.clock = 1.84166666666667
	reception.receive_point = Vector3(-3.337639,.11,-3.6984)
	reception.arrival_time = 2.24166666666667
	p._update_third_man(reception,by_id,snap)
	check("valid geometry still survives when old rescore is due",not p.third_man.is_empty() and p.third_man.deadline==5.1)
	p = seeded(1.7)
	reception.receive_point = Vector3(1000,.11,1000)
	reception.arrival_time = 2.0
	p._update_third_man(reception,by_id,snap)
	check("persistently invalid range cancels after failed due replan",p.third_man.is_empty() and p.third_man_last.get("cancel_reason","")=="receiver_to_target_space_closed")
	p = seeded(1.51666666666667)
	p.third_man.state = "CONTROLLED"
	var owned := snap.duplicate(true)
	owned.carrier_id = 5
	owned.ball_position = Vector3(1000,.11,1000)
	owned.ball_velocity = Vector3.ZERO
	p._update_third_man(reception,by_id,owned)
	check("actual controlled-space invalidity is not deferred",p.third_man.is_empty() and p.third_man_last.get("cancel_reason","")=="receiver_to_target_space_closed")
	p = seeded(1.51666666666667)
	var lost := snap.duplicate(true)
	lost.carrier_id = 2
	p._update_third_man(reception,by_id,lost)
	check("source ownership lost still cancels immediately",p.third_man.is_empty() and p.third_man_last.get("cancel_reason","")=="initial_receive_or_control_lost")
	p = seeded(1.51666666666667)
	var crowded := by_id.duplicate(true)
	crowded[1].position = target+Vector3(.1,0,.1)
	p._update_third_man(reception,crowded,snap)
	check("actual route or pressure danger cancels immediately",p.third_man.is_empty() and p.third_man_last.get("cancel_reason","") in ["runner_route_blocked","runner_target_pressured"])
	p = seeded(5.1)
	p.third_man.rescore_at = 5.7
	p._update_third_man(reception,by_id,snap)
	check("original deadline always cancels, even during hypothetical rescore wait",p.third_man.is_empty() and p.third_man_last.get("cancel_reason","")=="participant_unavailable_or_timeout")
	p = seeded(1.51666666666667)
	var close_runner: Dictionary = by_id[3].duplicate(true)
	close_runner.position = snap.ball_position+Vector3(0,0,1.99)
	p.third_man.runner_target = close_runner.position
	var opponents: Array[Dictionary] = [by_id[0],by_id[1],by_id[2]]
	check("real second-pass two-metre gate is unchanged",not p._third_man_ready(close_runner,snap.ball_position,opponents,snap))
	var failed: int = checks.filter(func(row):return not row.ok).size()
	var result := {"scope":"Pure finite planner lifetime; no actual foot or natural chain proof","checks":checks,"failed":failed}
	if output!="": FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result))
	quit(0 if failed==0 else 1)
