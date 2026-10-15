extends "res://tests/r024_lateral_walk.gd"
func start()->void:
	var pace:=preload("res://scripts/steady_walk_pace.gd").new()
	var first:float=pace.update(Vector3.LEFT,true,true,1.0/120.0)
	var full:float=0.0
	for i in 180:full=pace.update(Vector3.LEFT,true,true,1.0/120.0)
	check("steady direction ramps from walk to jog",first==0.0 and full>.99)
	check("direction change resets requested pace",pace.update(Vector3.RIGHT,true,true,1.0/120.0)==0.0)
	check("release resets requested pace",pace.update(Vector3.ZERO,true,true,1.0/120.0)==0.0)
	for i in 180:pace.update(Vector3.RIGHT,true,true,1.0/120.0)
	check("explicit close control disables steady gain",pace.update(Vector3.RIGHT,false,true,1.0/120.0)==0.0)
	for i in 180:pace.update(Vector3.RIGHT,true,false,1.0/120.0)
	check("gaining possession starts control pace afresh",pace.update(Vector3.RIGHT,true,true,1.0/120.0)==0.0)
	await super.start()

func ticks(count:int)->void:
	await super.ticks(count)
	var early:Array=rows.filter(func(r):return r.case==case_name and int(r.tick)<60)
	var late:Array=rows.filter(func(r):return r.case==case_name and int(r.tick)>=360)
	var initial:float=0.0
	var final_pace:float=0.0
	for row in early:initial+=absf(float(row.actor_velocity[0]))/float(early.size())
	for row in late:final_pace+=absf(float(row.actor_velocity[0]))/float(late.size())
	check(case_name+" actual movement accelerates below sprint",final_pace>initial+.5 and final_pace>2.3 and final_pace<2.85)
	print("STEADY_ACTUAL ",case_name," early=",initial," late=",final_pace)
