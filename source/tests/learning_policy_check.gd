extends SceneTree
var failures:int=0
func check(label:String,ok:bool)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize()->void:
	var P=preload("res://scripts/tactics/learned_team_policy.gd")
	var p=P.new()
	check("ordinary launch keeps baseline decision path",not p.enabled and p.tick({},.2).is_empty())
	check("missing model falls back",not p.load_model(0,"res://absent_model.json") and not p.enabled)
	check("exported model loads",p.load_model(0,"res://../learning/models/policy_0000.json"))
	var snapshot:Dictionary={"ball_position":Vector3(0,.11,0),"ball_velocity":Vector3.ZERO,"carrier_id":1,"field_half_width":34,"field_half_length":52.5,"players":[{"id":1,"team":0,"position":Vector3(0,0,1),"velocity":Vector3.ZERO},{"id":2,"team":1,"position":Vector3(0,0,-2),"velocity":Vector3.ZERO}]}
	var obs:Array=p.features(snapshot,0)
	var probs:Array=p.probabilities(obs,p.models[0])
	check("attack mask excludes defensive-only choices",float(probs[5])==0 and float(probs[6])==0)
	var total:float=0
	for v in probs:total+=float(v)
	check("finite normalized policy",is_finite(total) and absf(total-1)<.00001)
	p.training=true;p.rng.seed=12;p.tick(snapshot,.2)
	var first:int=int(p.states[0].action)
	p.tick(snapshot,.2)
	check("short commitment retains action",int(p.states[0].action)==first and p.traces[0].is_empty())
	p.credit(0,20);p.reset();p.tick(snapshot,.2)
	check("restart preserves previous goal credit",p.traces[0].size()==1 and float(p.traces[0][0].reward)>19)
	p.finish(true)
	check("terminal has no bootstrap",float(p.traces[0][-1].discount)==0 and p.traces[0][-1].terminal)
	var neutral:bool=true
	for kind in ["CARRY","PASS","ONE_TWO","THROUGH","LONG","CROSS","CUTBACK","SWITCH"]:neutral=neutral and P.bias(0,kind)==0
	check("neutral action adds no tactical bias",neutral)
	check("learned preferences affect existing scores",P.bias(1,"CARRY")>P.bias(1,"PASS") and P.bias(2,"PASS")>P.bias(2,"CARRY"))
	quit(1 if failures else 0)
