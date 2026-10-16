extends SceneTree
var checks:Array=[]
func check(label:String,passed:bool)->void:
	checks.append({"label":label,"passed":passed});print("PASS " if passed else "FAIL ",label)
func _initialize()->void:
	var d=preload("res://scripts/tactics/tactical_director.gd").new()
	d.configure([{"id":1,"team":0,"role":d.Roles.WINGER,"duty":"width"}])
	var p:Dictionary={"id":1,"team":0,"position":Vector3.ZERO,"velocity":Vector3.FORWARD*3,"facing":Vector3.FORWARD,"stamina":100,"cut_ready":true}
	var s:Dictionary={"field_half_width":34.0,"field_half_length":52.5,"ball_position":Vector3(0,0,-.4),"ball_velocity":Vector3.FORWARD*3}
	var behind:Array[Dictionary]=[{"position":Vector3(0,0,1.6),"velocity":Vector3.FORWARD*3}]
	var carry:Dictionary=d._open_carry_option(p,behind,s)
	var gear:Dictionary={"close_control":false,"shield":false,"pace":4.8}
	d._apply_carry_gear(p,gear,carry,behind,s)
	check("trailing opponent within old2.7m threshold does not persistently cap run",gear.carry_run)
	var clear:Array[Dictionary]=[]
	var slight:Vector3=Vector3(.54,0,-.84).normalized()
	var next:Dictionary={"point":slight*5.0,"progress":4.2}
	d.carry_routes[1]={"run_active":true}
	d._apply_carry_gear(p,gear,next,clear,s)
	check("established acceleration survives modest steering",gear.carry_run)
	d.carry_routes[1]={"run_active":false}
	d._apply_carry_gear(p,gear,next,clear,s)
	check("new acceleration waits for alignment",not gear.carry_run)
	var front:Array[Dictionary]=[{"position":Vector3(0,0,-1.6),"velocity":Vector3.BACK*2}]
	d.carry_routes.clear()
	carry=d._open_carry_option(p,front,s)
	check("blocked frontal route is rejected or selects lateral exit",carry.is_empty() or absf(carry.point.x)>.5)
	var route=preload("res://scripts/tactics/pressure_route.gd")
	var crossing:Array[Dictionary]=[{"position":Vector3(2.5,0,-2),"velocity":Vector3(-5,0,0)}]
	var leaving:Array[Dictionary]=[{"position":Vector3(2.5,0,-2),"velocity":Vector3(5,0,0)}]
	check("equal distance approaching and departing opponents produce different risk",route.inspect(p,Vector3(0,0,-5),crossing).clearance<route.inspect(p,Vector3(0,0,-5),leaving).clearance)
	p.stamina=12;d.carry_routes.clear();carry=d._open_carry_option(p,behind,s);d._apply_carry_gear(p,gear,carry,behind,s)
	check("low stamina keeps run unavailable",not gear.carry_run)
	p.position=Vector3.ZERO;p.stamina=100;d.clock=2.0
	d.carry_routes[1]={"origin":Vector3.ZERO,"target":Vector3.FORWARD*5.0,"started":0.0}
	var pressure:Dictionary={"immediate":1.1,"frontal":true,"contact_time":.6}
	check("stalled pressured exit yields to safe pass comparison",d._carry_exit_stalled(p,{"point":Vector3.FORWARD*5},pressure))
	check("open lane is not forced into timed passing",not d._carry_exit_stalled(p,{"point":Vector3.FORWARD*5},{"immediate":3.0,"frontal":false,"contact_time":10.0}))
	p.position=Vector3.FORWARD*.7
	check("real progress renews escape opportunity",not d._carry_exit_stalled(p,{"point":Vector3.FORWARD*5},pressure))
	d.clock=2.6
	check("progress does not immediately become a stalled exit",not d._carry_exit_stalled(p,{"point":Vector3.FORWARD*5},pressure))
	d.clock=3.2
	check("new blockage after progress is detected",d._carry_exit_stalled(p,{"point":Vector3.FORWARD*5},pressure))
	FileAccess.open("res://../verification/r034-policy.json",FileAccess.WRITE).store_string(JSON.stringify(checks,"  "))
	quit(0 if checks.all(func(c):return c.passed) else 1)
