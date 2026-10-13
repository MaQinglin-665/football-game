extends SceneTree
func _initialize()->void:
	var director=preload("res://scripts/tactics/tactical_director.gd").new()
	director.configure([{"id":1,"team":0,"role":director.Roles.WINGER,"duty":"attack"}])
	var p:Dictionary={"id":1,"team":0,"position":Vector3.ZERO,"facing":Vector3.FORWARD}
	var snapshot:Dictionary={"field_half_width":34.0,"field_half_length":52.5}
	var opponents:Array[Dictionary]=[]
	var checks:Array=[]
	var open:Dictionary=director._open_carry_option(p,opponents,snapshot)
	checks.append({"label":"open space advances","passed":open.get("style")=="ADVANCE"})
	var gear:Dictionary={"close_control":false,"shield":false,"pace":4.8}
	director._apply_carry_gear(p,gear,open,opponents,snapshot)
	checks.append({"label":"safe forward corridor requests real carry run","passed":gear.carry_run and gear.pace==5.0})
	var edge_p:Dictionary=p.duplicate();edge_p.position=Vector3(32.5,0,0)
	director._apply_carry_gear(edge_p,gear,open,opponents,snapshot)
	checks.append({"label":"near touchline cancels running gear","passed":not gear.carry_run and gear.pace<4.0})
	director.clock=.15
	opponents.append({"position":Vector3(5,0,-4),"velocity":Vector3.ZERO})
	var retained:Dictionary=director._open_carry_option(p,opponents,snapshot)
	checks.append({"label":"safe direction remains stable","passed":retained.get("committed",false) and retained.point==open.point})
	opponents=[{"position":Vector3(0,0,-1.2),"velocity":Vector3.ZERO}]
	var exit_route:Dictionary=director._open_carry_option(p,opponents,snapshot)
	checks.append({"label":"blocked forward route immediately chooses escape","passed":not exit_route.is_empty() and exit_route.point!=open.point and absf(exit_route.point.x)>.5})
	director._apply_carry_gear(p,gear,exit_route,opponents,snapshot)
	checks.append({"label":"close pressure cancels running gear","passed":not gear.carry_run})
	director.roster[1].role=director.Roles.CENTER_BACK;director.carry_routes.clear()
	var defender:Dictionary=director._open_carry_option(p,opponents,snapshot)
	checks.append({"label":"defender uses lower risk budget","passed":not defender.is_empty() and defender.risk<exit_route.risk})
	p.velocity=Vector3.FORWARD*4.0;p.can_reach=true;p.foot_action="TURN"
	snapshot.ball_position=Vector3(.3,.12,.3);snapshot.ball_velocity=Vector3.FORWARD*3.5
	director.controlled_contacts[1]=director.clock
	director.carrier_setup={"owner_id":1,"heading":Vector3.FORWARD,"released":true}
	var members:Array[Dictionary]=[p]
	checks.append({"label":"confirmed nearby rolling turn does not restart pose gate","passed":not director._wait_for_control(p,gear,snapshot,members,opponents)})
	snapshot.ball_position=Vector3(0,.12,2.0)
	checks.append({"label":"ball beyond rolling pocket requires control again","passed":director._wait_for_control(p,gear,snapshot,members,opponents)})
	for row in checks:print("PASS " if row.passed else "FAIL ",row.label)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):FileAccess.open(arg.trim_prefix("--out="),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"open":open,"escape":exit_route,"defender":defender},"  "))
	quit(0 if checks.all(func(row):return row.passed) else 1)
