extends SceneTree
const Screen=preload("res://scripts/body_pressure.gd")
func _initialize()->void:
	var owner:=Vector3(5,0,0)
	var defender:=Vector3(5,0,1)
	var ball:=Vector3(5.5,0,.4)
	var target:Vector3=Screen.target(defender,owner,Vector3.ZERO,ball,Vector3.FORWARD)
	var ok:bool=(target-owner).dot(Vector3.FORWARD)>0 and target.distance_to(owner)>.6
	print("PASS " if ok else "FAIL ","beaten defender regains goal-side screen instead of chasing outside ball ",target)
	quit(0 if ok else 1)
