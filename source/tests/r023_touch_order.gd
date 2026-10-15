extends "res://tests/r022_preferred_control.gd"
var first_cases:Dictionary={}
func on_contact(event:Dictionary)->void:
	super.on_contact(event)
	if event.get("actor")!=game.player or not event.get("success",false) or event.get("kind","")!="FOOT_TOUCH" or first_cases.has(case_name):return
	first_cases[case_name]=true
	var advance:float=absf(game.player.position.x)
	if case_name in ["left","left_foot_right"]:
		var prepared:bool=rows.any(func(r):return r.case==case_name and bool(r.decision.get("inside_body_first",{}).get("ready",false)) and bool(r.decision.get("inside_body_first",{}).get("loaded",false)))
		check(case_name+" body moves before inside touch",advance>=.055 and prepared)
		check(case_name+" ball not moved by body preparation",(event.before_velocity as Vector3).length()<.01)
	if case_name=="right":
		check("outside touch precedes substantial body advance",advance<.05 and game.player.foot.side==1 and game.player.foot.surface=="OUTSIDE")
