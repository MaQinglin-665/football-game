extends SceneTree
const Follow := preload("res://scripts/dribble_follow_step.gd")
var failures:=0
func check(label:String,value:bool)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures+=1
func _initialize()->void:
	# Identical time, different physical progress: there is no timer input.
	check("no body follow cannot earn another tap",not Follow.evaluate(Vector3(.6,0,0),Vector3.ZERO,0,.18,.20,true,true,true).ready)
	check("followed supported stride can receive next touch",Follow.evaluate(Vector3(.6,0,0),Vector3.ZERO,.21,.18,.20,true,true,true).ready)
	check("no repeated tap before shoe separates",not Follow.evaluate(Vector3(.6,0,0),Vector3.ZERO,.3,.18,.20,false,true,true).ready)
	check("ball must actually roll",not Follow.evaluate(Vector3(.6,0,0),Vector3.ZERO,.3,.02,.20,true,true,true).ready)
	check("old momentum cannot count as following new direction",not Follow.evaluate(Vector3(.6,0,0),Vector3.ZERO,.3,.18,.20,true,false,true).ready)
	check("airborne transfer can continue after enough real travel",Follow.evaluate(Vector3(.6,0,0),Vector3.ZERO,.34,.18,.20,true,true,false).ready)
	check("near escape bypass does not force waiting",Follow.evaluate(Vector3(.9,0,0),Vector3(2,0,0),0,.1,.20,true,false,false).ready)
	check("ball under body allows immediate recovery",Follow.evaluate(Vector3(.2,0,0),Vector3.ZERO,0,0,.20,false,false,false).ready)
	quit(0 if failures==0 else 1)
