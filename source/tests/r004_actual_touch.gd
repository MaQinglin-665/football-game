extends "res://tests/contact_flow_check.gd"
var touch_grades:Array=[]
func run()->void:
	game=load("res://scenes/training_3v3.tscn").instantiate();game.test_mode=true;root.add_child(game)
	await ticks(6);game.hud.menu.get_node("StartMatch").pressed.emit();await ticks(8)
	game.tactics_bridge.set_physics_process(false);game.training_mode.set_physics_process(false)
	game.contact_hub.contact_resolved.connect(func(e):
		if e.get("actor")==actor and e.get("success",false) and e.get("action","")=="RECEIVE":
			touch_grades.append({"case":label,"grade":actor.foot.touch_plan.get("first_touch_grade",{}).duplicate(),"velocity":game.ball.velocity})
	)
	for spec in [["ON_TIME",.15],["EARLY",.60],["LATE",.03]]:
		label=spec[0];stage(game.player,Vector3(.30,0,-.38),Vector3(0,0,2),false)
		actor.first_touch_clock_override=10.0;actor.first_touch_timing=FirstTouchTiming.new()
		actor.first_touch_timing.observe(Vector3.RIGHT,10.0-float(spec[1]))
		actor.move_requested=true;actor.ball_direction=Vector3.RIGHT
		actor.foot.begin("RECEIVE",Vector3.FORWARD,Vector3.ZERO,0,.18)
		await observe(60)
		var hits:Array=touch_grades.filter(func(r):return r.case==label and r.grade.get("grade","")==label)
		check(label+" grading is present at real shoe reception",not hits.is_empty())
	var passed:bool=checks.all(func(c):return c.ok)
	FileAccess.open("res://../verification/r004_actual_touch.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"contacts":touch_grades,"scope":"Declared positions and fixed onset clock; actual shoe contact, not user timing or full-match evidence"},"  "))
	game.shutdown_audio();game.queue_free();await ticks(3);quit(0 if passed else 1)
