extends SceneTree
func _initialize()->void:
	var d=preload("res://scripts/tactics/tactical_director.gd").new()
	var results:Array=[]
	for side in [-1.0,1.0]:
		var p:Dictionary={"id":10,"team":0,"position":Vector3(side*28.25,0,-23.8),"velocity":Vector3(0,0,-5)}
		var intent:Dictionary={"action":"NONE","role":d.Roles.WINGER,"move_target":Vector3(side*31.05,0,-26.94),"pace":5.0,"carry_run":true}
		d.boundary_routes.clear()
		d._guard_carry_boundary(p,intent,{"ball_position":Vector3(side*28.26,.11,-24.42),"ball_velocity":Vector3(0,0,-4.7),"field_half_width":34.0,"field_half_length":52.5})
		var ok:bool=not intent.carry_run and intent.move_target.x*side<p.position.x*side
		results.append({"side":side,"passed":ok,"intent":intent});print("PASS " if ok else "FAIL ",side," anticipates outward next touch ",intent)
	FileAccess.open("res://../verification/boundary_check.json",FileAccess.WRITE).store_string(JSON.stringify(results,"  "))
	quit(0 if results.all(func(r):return r.passed) else 1)
