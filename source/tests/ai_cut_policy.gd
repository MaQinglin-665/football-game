extends SceneTree
var checks:Array=[]
func check(label:String,passed:bool)->void:
	checks.append({"label":label,"passed":passed});print("PASS " if passed else "FAIL ",label)
func _initialize()->void:
	var d=preload("res://scripts/tactics/tactical_director.gd").new()
	d.configure([{"id":1,"team":0,"role":d.Roles.WINGER,"duty":"width"}])
	var p:Dictionary={"id":1,"team":0,"position":Vector3.ZERO,"velocity":Vector3.FORWARD*3,"facing":Vector3.FORWARD,"stamina":100}
	var s:Dictionary={"field_half_width":34.0,"field_half_length":52.5}
	var behind:Array[Dictionary]=[{"position":Vector3(0,0,1.6),"velocity":Vector3.FORWARD*3}]
	var carry:Dictionary=d._open_carry_option(p,behind,s)
	var gear:Dictionary={"close_control":false,"shield":false,"pace":4.8}
	d._apply_carry_gear(p,gear,carry,behind,s)
	check("trailing opponent within old2.7m threshold does not persistently cap run",gear.carry_run)
	var front:Array[Dictionary]=[{"position":Vector3(0,0,-1.6),"velocity":Vector3.BACK*2}]
	d.carry_routes.clear()
	carry=d._open_carry_option(p,front,s)
	check("approaching frontal opponent rejects straight route",not carry.is_empty() and absf(carry.point.x)>.5)
	d._apply_carry_gear(p,gear,carry,front,s)
	print("CUT_DIAGNOSTIC ",carry," ",gear)
	check("cut requests actual cut execution before running",not gear.carry_run and gear.get("carry_cut",false))
	d.carry_routes[1]["cut_attempted"]=true
	d._apply_carry_gear(p,gear,carry,front,s)
	check("same committed route does not repeat cut",not gear.get("carry_cut",false))
	var route=preload("res://scripts/tactics/pressure_route.gd")
	var crossing:Array[Dictionary]=[{"position":Vector3(2.5,0,-2),"velocity":Vector3(-5,0,0)}]
	var leaving:Array[Dictionary]=[{"position":Vector3(2.5,0,-2),"velocity":Vector3(5,0,0)}]
	check("equal distance approaching and departing opponents produce different risk",route.inspect(p,Vector3(0,0,-5),crossing).clearance<route.inspect(p,Vector3(0,0,-5),leaving).clearance)
	p.stamina=12;d.carry_routes.clear();carry=d._open_carry_option(p,behind,s);d._apply_carry_gear(p,gear,carry,behind,s)
	check("low stamina keeps run unavailable",not gear.carry_run)
	var attack=preload("res://scripts/tactics/team_attack.gd").new()
	p.position=Vector3(20,0,0)
	var members:Array[Dictionary]=[p,{"id":2,"team":0,"position":Vector3(-4,0,2),"velocity":Vector3.ZERO},{"id":3,"team":0,"position":Vector3(14,0,6),"velocity":Vector3.ZERO}]
	var roster:Dictionary={1:{"role":"winger","lane":1},2:{"role":"midfielder","lane":-.32},3:{"role":"center_back","slot":"BACK","lane":0}}
	s.ball_position=p.position;s.role_targets={}
	var opponents:Array[Dictionary]=[]
	var offers:Dictionary=attack._support_assignments(0,p,members,opponents,s,roster,{},"SHORT")
	check("near diagonal outlet is not mirrored to remote half",offers[2].point.x>0 and offers[2].point.distance_to(p.position)<12)
	check("small team keeps a distinct rear protection outlet",offers[3].role=="SAFE" and offers[3].point.z>p.position.z)
	FileAccess.open("res://../verification/pressure_policy.json",FileAccess.WRITE).store_string(JSON.stringify(checks,"  "))
	quit(0 if checks.all(func(c):return c.passed) else 1)
