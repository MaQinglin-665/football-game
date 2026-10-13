extends "res://tests/integration_checks.gd"
const Attack=preload("res://scripts/tactics/team_attack.gd")
var attack=Attack.new()
var roster:Dictionary={}
var snap:Dictionary={}
var candidate_samples:Array=[]
func row(id:int,x:float,z:float,role:String="midfielder",team:int=0)->Dictionary:
	roster[id]={"id":id,"team":team,"role":role,"slot":"DM" if role=="center_back" else "CF" if role=="striker" else "LW" if role=="winger" else "LCM","lane":-.5,"duty":"support"}
	return {"id":id,"team":team,"position":Vector3(x,0,z),"velocity":Vector3.ZERO,"facing":Vector3.FORWARD,"stamina":100.0,"human":false,"foot_idle":true,"foot_hit":false,"foot_cap":100,"can_kick":true,"kick_ready":true,"active":true,"can_reach":true,"tackle_ready":true}
func candidates(owner:Dictionary,members:Array[Dictionary],opponents:Array[Dictionary],label:String)->Array[Dictionary]:
	snap.ball_position=owner.position;snap.carrier_id=int(owner.id)
	var assignments:Dictionary={}
	var result:Array[Dictionary]=attack._candidates(0,owner,members,opponents,snap,roster,assignments,"attack")
	candidate_samples.append({"label":label,"choices":result})
	return result
func has_mode(options:Array[Dictionary],mode:String)->bool:
	return options.any(func(p):return p.mode==mode)
func run()->void:
	game=load("res://scenes/match.tscn").instantiate();game.test_mode=true;root.add_child(game)
	await ticks(3)
	game.tactics_bridge._build_delivery_table();game.tactics_bridge._build_loft_table()
	snap={"field_half_width":34.0,"field_half_length":52.5,"ball_position":Vector3.ZERO,"ball_velocity":Vector3.ZERO,"ground_delivery":game.tactics_bridge.ground_delivery,"loft_delivery":game.tactics_bridge.loft_delivery,"aerial_delivery":game.tactics_bridge.aerial_delivery,"fixed_offside":{0:51.0,1:51.0},"capabilities":{"gravity":9.81},"role_targets":{},"carrier_id":0,"small_sided":false}
	var owner:Dictionary=row(0,0,0,"midfielder")
	var wall:Dictionary=row(1,5,-2)
	var safety:Dictionary=row(2,-5,8,"center_back")
	var chaser:Dictionary=row(11,0,3,"midfielder",1)
	var options:Array[Dictionary]=candidates(owner,[owner,wall,safety],[chaser],"one_two")
	check("one-two rejects defender winning second-leg race",not has_mode(options,"ONE_TWO"))
	chaser.position.z=4.8
	options=candidates(owner,[owner,wall,safety],[chaser],"one_two_open_return")
	check("slower short-pass profile rejects former marginal return race",not has_mode(options,"ONE_TWO"))
	# With the new short-ball travel time, use a genuinely closer wall rather
	# than weakening the defender arrival guard to preserve an old fixture.
	wall.position=Vector3(3,0,-1)
	options=candidates(owner,[owner,wall,safety],[chaser],"one_two_close_wall")
	check("one-two considers second leg space",has_mode(options,"ONE_TWO"))
	var combo:Dictionary={}
	for option in options:
		if option.mode=="ONE_TWO":combo=option.duplicate(true);break
	if not combo.is_empty():
		combo.merge({"id":1,"team":0,"owner":0,"stage":"PREPARE","runner":0,"runner_start":owner.position,"until":10.0,"assignments":{}},true)
		attack.plans[0]=combo
		check("request alone does not advance plan",attack.plans[0].stage=="PREPARE")
		attack.confirm_pass(0,0,1,1.0)
		check("real pass assigns original passer forward run",attack.plans[0].stage=="FLIGHT" and attack.plans[0].assignments[0].role=="RETURN_RUN")
		attack.control_contact({"actor_id":1,"carrier_id":1,"action":"RECEIVE"},roster,1.4)
		check("real wall reception enables return",attack.plans[0].stage=="RETURN" and int(attack.plans[0].owner)==1)
		attack.control_contact({"actor_id":11,"carrier_id":11,"action":"RECEIVE"},roster,1.5)
		check("opponent control cancels combination",not attack.plans.has(0))
	var runner:Dictionary=row(3,4,-9,"striker");runner.velocity=Vector3(0,0,-3)
	check("forward runner gets lead-space candidate",has_mode(candidates(owner,[owner,runner,safety],[],"through"),"THROUGH"))
	var lead:Dictionary=attack._delivery(owner.position,Vector3(4,0,-12),snap,false);lead.receiver=3
	snap.fixed_offside[0]=7.0
	check("offside receiver rejected before kick",not attack._feasible(owner,runner,lead,[],snap,true))
	snap.fixed_offside[0]=51.0
	runner.human=true;runner.velocity=Vector3.ZERO
	check("stationary human not assumed to chase lead",not attack._feasible(owner,runner,lead,[],snap,true))
	runner.human=false
	var obstruction:Dictionary=row(12,2,-6,"midfielder",1)
	check("interceptable pass is rejected",not attack._feasible(owner,runner,lead,[obstruction],snap,true))
	var wing:Dictionary=row(4,23,-42,"winger")
	var a:Dictionary=row(5,3,-44,"striker");var b:Dictionary=row(6,0,-42);var c:Dictionary=row(7,-5,-44,"winger");var e:Dictionary=row(8,2,-35)
	options=candidates(wing,[wing,a,b,c,e,safety],[],"cross")
	check("wide play has timed box cross candidates",has_mode(options,"CROSS"))
	wing.position.z=-47
	options=candidates(wing,[wing,a,b,c,e,safety],[],"cutback")
	check("backward cutback valued near goal line",has_mode(options,"CUTBACK"))
	var box:Dictionary=attack._box_roles(0,wing,[wing,a,b,c,e,safety],snap,roster)
	var roles:Array=[]
	for value in box.values():roles.append(value.role)
	check("box jobs are distinct including late arrival",roles.size()==4 and roles.has("LATE_EDGE") and roles.has("FAR_POST"))
	wing.position=Vector3(20,0,-33)
	check("open inside shooting route considered",has_mode(candidates(wing,[wing,a,b,c,e,safety],[],"cut_in"),"CUT_IN"))
	owner.position=Vector3(0,0,12);a.position=Vector3(0,0,-20);safety.position=Vector3(-8,0,22)
	check("supported forward loft uses measured flight table",has_mode(candidates(owner,[owner,a,safety],[],"long"),"LONG"),snap.loft_delivery)
	wing.position=Vector3(20,0,0);c.position=Vector3(-18,0,-2);safety.position=Vector3(0,0,15)
	var packed:Array[Dictionary]=[]
	for i in 6:packed.append(row(20+i,29.0,float(i)*5+9,"midfielder",1))
	check("weak side switch compares lateral arrival",has_mode(candidates(wing,[wing,c,safety],packed,"switch"),"SWITCH"))
	var pressure=preload("res://scripts/tactics/pressure_route.gd")
	owner.position=Vector3.ZERO;owner.velocity=Vector3(0,0,-4)
	chaser.position=Vector3(0,0,2);chaser.velocity=Vector3(0,0,-4)
	var chase:Dictionary=pressure.inspect(owner,Vector3(0,0,-5),[chaser])
	check("matching-speed rear chase does not force frontal shield",not chase.frontal and chase.immediate>1.0)
	chaser.position=Vector3(0,0,-2);chaser.velocity=Vector3(0,0,2)
	var front:Dictionary=pressure.inspect(owner,Vector3(0,0,-5),[chaser])
	check("head-on closing threat is immediate",front.frontal and front.contact_time<.4)
	FileAccess.open(evidence+"/team_plan_checks.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"candidate_samples":candidate_samples,"scope":"directed planner checks only; not natural or physical success evidence"},"  "))
	quit(1 if checks.any(func(c):return not c.passed) else 0)
