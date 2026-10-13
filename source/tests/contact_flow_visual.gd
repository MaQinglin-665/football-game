extends "res://tests/tactical_flow_visual.gd"
var challenges:Array=[]
var attempts:Dictionary={}
func begin()->void:
	super.begin()
	game.contact_hub.contact_resolved.connect(func(e):
		if e.get("action","")!="TACKLE":return
		var a=e.get("actor")
		if not is_instance_valid(a):return
		challenges.append({"t":elapsed,"actor":game.players.find(a),"team":a.team,"automatic":a.foot.touch_plan.get("automatic",false),"success":e.get("success",false),"before":e.get("before_velocity"),"after":e.get("after_velocity"),"point":e.get("point"),"failure":a.foot.contact_failure})
	)
func observe(dt:float)->void:
	if not finished:
		for a in game.players:
			if a.foot.kind=="TACKLE" and not a.foot.idle():
				var key:String=str(a.get_instance_id())+":"+str(a.foot.sequence)
				if not attempts.has(key):attempts[key]={"t":elapsed,"actor":game.players.find(a),"automatic":a.foot.touch_plan.get("automatic",false),"ball":game.ball.position,"root":a.position}
		if elapsed+dt>=duration or full_match and game.services.rules.state_name()=="FULL_TIME":
			FileAccess.open(output+".defense.json",FileAccess.WRITE).store_string(JSON.stringify({"attempts":attempts.values(),"contacts":challenges,"scope":"Natural match with unchanged opening and actual contact; rendered capture has overhead and is not an FPS benchmark."},"  "))
	super.observe(dt)
