extends SceneTree
var failures:=0
var results:Array=[]
func check(label:String,ok:bool)->void:
	results.append({"label":label,"pass":ok})
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize()->void:
	var geometry=preload("res://scripts/body_pressure.gd")
	for sign_x in [-1.,1.]:
		var owner:=Vector3(15*sign_x,0,12)
		var goal:=Vector3(0,0,52.5)
		var toward:Vector3=(goal-owner).normalized()
		var defender:Vector3=owner+toward*2.4
		var target:Vector3=geometry.target(defender,owner,Vector3.ZERO,owner-toward*.3,toward)
		check("wide carrier seals inside "+str(sign_x),(target-owner).x*sign_x<-.35 and (target-owner).dot(toward)>.7)
		check("containment does not target torso "+str(sign_x),target.distance_to(owner)>.7)
		var view:Vector3=geometry.facing(owner-defender,owner,toward)
		check("stance opens toward outside "+str(sign_x),view.x*sign_x>0)
	var owner:=Vector3.ZERO
	var target:Vector3=geometry.target(Vector3(0,0,-2),owner,Vector3.ZERO,Vector3(0,.11,.25),Vector3.BACK)
	var nearest:Vector3=Geometry3D.get_closest_point_to_segment(owner,Vector3(0,0,-2),target)
	check("beaten approach arcs around torso",nearest.length()>.60)
	var side:Vector3=geometry.target(Vector3(.8,0,.3),owner,Vector3.ZERO,Vector3(.5,.11,.4),Vector3.BACK)
	check("exposed side ball remains approachable",side.distance_to(Vector3(.5,.11,.4))<.6)
	var d=preload("res://scripts/tactics/defensive_tasks.gd").new()
	var roster:Dictionary={0:{"team":0,"role":"center_back","slot":"LCB"},1:{"team":0,"role":"full_back","slot":"RB"},2:{"team":0,"role":"midfielder","slot":"DM"},3:{"team":1,"role":"winger","slot":"LW"},4:{"team":1,"role":"striker","slot":"ST"},5:{"team":0,"role":"goalkeeper","slot":"GK"},6:{"team":0,"role":"winger","slot":"LW"}}
	d.configure(roster)
	var players:Array=[]
	for id in roster:
		players.append({"id":id,"team":roster[id].team,"position":Vector3(-6 if id==0 else 19 if id in [1,3] else 0,0,20 if id in [1,3] else 24),"velocity":Vector3.ZERO,"facing":Vector3.FORWARD,"active":true,"human":id==6})
	var s:Dictionary={"players":players,"carrier_id":3,"possession_team":1,"ball_position":Vector3(19,.11,19.6),"ball_velocity":Vector3.ZERO,"field_half_width":34.,"field_half_length":52.5,"eleven_duties":true,"tactical_scale":1.,"role_targets":{0:Vector3(-6,0,24),1:Vector3(17,0,23),2:Vector3(0,0,20),5:Vector3(0,0,50),6:Vector3(-15,0,8)}}
	check("far CB cannot chase wing outside his zone",not d._in_zone(players[0],Vector3(27,0,20),s))
	check("central box emergency may break zone",d._in_zone(players[0],Vector3(2,0,47),s))
	var output:Dictionary=d.tick(s,.2)
	var pressers:Array=output.tasks.values().filter(func(t):return t.team==0 and t.task=="PRESS")
	check("only one presser per team",pressers.size()==1)
	check("near fullback pressures instead of dragging CB",output.teams[0].presser_id==1)
	check("human and goalkeeper are never assigned AI pressure",output.teams[0].presser_id not in [5,6])
	check("cover remains behind pressure and inside",output.tasks[2].target.z>20 and output.tasks[2].target.x<19)
	var first:int=output.teams[0].presser_id
	players[3].position.x+=.15;s.ball_position.x+=.15
	output=d.tick(s,.2)
	check("minor ball movement retains pressure responsibility",output.teams[0].presser_id==first)
	var contact=preload("res://scripts/defense_contact.gd")
	var poke:Vector3=contact.poke_velocity(Vector3.ZERO,Vector3.ZERO,Vector3.RIGHT,2.4)
	check("clean poke leaves a recoverable independent ball",poke.x>1 and poke.length()<2.5 and poke.y==0)
	var moving:Vector3=contact.poke_velocity(Vector3(0,0,5),Vector3.ZERO,Vector3.RIGHT,2.4)
	check("rolling tackle preserves a tangential deflection",moving.x>0 and moving.z>1 and moving.length()<=4.5)
	FileAccess.open("res://../verification/defensive_shape_checks.json",FileAccess.WRITE).store_string(JSON.stringify(results,"  "))
	quit(1 if failures else 0)
