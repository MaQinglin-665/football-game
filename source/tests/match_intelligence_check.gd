extends SceneTree
var failures:int=0
func check(label:String,passed:bool)->void:
	print("PASS " if passed else "FAIL ",label)
	if not passed:failures+=1
func _initialize()->void:
	var director=preload("res://scripts/tactics/tactical_director.gd").new()
	var attack=director.team_attack
	var empty:Array[Dictionary]=[]
	var snap:Dictionary={"field_half_length":52.5,"field_half_width":34.0,"ball_position":Vector3(0,.11,0),"ball_velocity":Vector3.ZERO}
	var open_forward:float=attack.possession_value(Vector3.ZERO,Vector3(3,0,-16),0,empty,snap)
	var short_carry:float=attack.possession_value(Vector3.ZERO,Vector3(0,0,-5),0,empty,snap)
	check("an open line-breaking destination outranks a five-metre advance",open_forward>short_carry+2.0)
	check("team reflection preserves option values",is_equal_approx(open_forward,attack.possession_value(Vector3.ZERO,Vector3(-3,0,16),1,empty,snap)))
	var blocked:Array[Dictionary]=[{"id":2,"team":1,"position":Vector3(0,0,-5),"velocity":Vector3.ZERO}]
	check("higher reward never makes a blocked pass legal",not director._lane_clear(Vector3.ZERO,Vector3(0,0,-12),blocked,1.2))
	var owner:Dictionary={"id":0,"team":0,"position":Vector3.ZERO,"velocity":Vector3.ZERO,"facing":Vector3.FORWARD}
	var receiver:Dictionary={"id":1,"team":0,"position":Vector3(4,0,-10),"velocity":Vector3.ZERO,"facing":Vector3.FORWARD}
	var race:Dictionary={"point":receiver.position,"flight":.9,"loft":0.0}
	var guard:Array[Dictionary]=[{"id":2,"team":1,"position":Vector3(3.9,0,-10),"velocity":Vector3.ZERO}]
	check("an opponent arriving first rejects the delivery",not attack._feasible(owner,receiver,race,guard,snap,true))
	var defender:Dictionary={"id":2,"team":1,"position":Vector3(0,0,1),"velocity":Vector3.ZERO,"facing":Vector3.FORWARD,"can_reach":true,"foot_idle":true,"tackle_ready":true}
	director.observed_carrier=0
	snap.carrier_id=0;snap.ball_position=Vector3(0,.11,-.4)
	var intent:Dictionary={"action":"NONE"}
	director._press(defender,intent,owner,snap)
	check("screened ball retains shoulder pressure instead of a blind tackle",intent.action=="NONE" and intent.press)
	defender.position=Vector3(0,0,-1);defender.facing=Vector3.BACK
	intent={"action":"NONE"};director._press(defender,intent,owner,snap)
	check("exposed reachable ball still permits a tackle",intent.action=="TACKLE")
	director.roster={0:{"role":director.Roles.MIDFIELDER}}
	director.carrier_setup={"owner_id":0,"heading":Vector3.FORWARD,"released":false}
	snap.ball_position=Vector3(0,.11,-1.2);snap.ball_velocity=Vector3(0,0,-4)
	owner.can_reach=false;intent={}
	check("out-of-pocket ball remains a recovery task",director._wait_for_control(owner,intent,snap,[],empty))
	check("recovery can catch a rolling ball instead of staying at 2.4 m/s",float(intent.pace)>4.0 and intent.action=="NONE")
	director.roster[0].role=director.Roles.WINGER
	owner.position=Vector3(27,0,-40);owner.facing=Vector3.FORWARD
	snap.ball_position=owner.position+Vector3(0,.11,-.4)
	var route:Dictionary=director._open_carry_option(owner,empty,snap)
	check("an unopposed winger near the byline chooses an inward route",not route.is_empty() and route.point.x<25.0)
	snap.ball_position=Vector3(25,.11,-32)
	check("an open but distant diagonal is not an automatic shot",director._shot_option(owner,empty,snap).is_empty())
	snap.ball_position=Vector3(0,.11,-34)
	check("a clear central eighteen-metre chance remains shootable",not director._shot_option(owner,empty,snap).is_empty())
	quit(1 if failures else 0)
