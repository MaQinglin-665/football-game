extends SceneTree
var ok:=true
func check(label:String,value:bool)->void:
	ok=ok and value;print("PASS " if value else "FAIL ",label)
func _initialize()->void:
	var router:=preload("res://addons/football_input/intent_router.gd").new()
	router.set_context({"phase":"live","possession":"foot","capabilities":{"shoot_straight":true,"shoot_curve":true}})
	router.feed("placed_shot",true,"key:T")
	var push:Dictionary=router._kick_params("shot")
	check("T selects placed shot without changing pass",push.style=="placed" and push.elevation_deg<=8.0 and router._kick_params("pass").style=="ground")
	router.feed("spin_left",true,"key:G")
	var left:Dictionary=router._kick_params("shot")
	check("G curve overrides T",left.style=="curve" and left.spin.y==-1)
	router.feed("spin_left",false,"key:G");router.feed("placed_shot",false,"key:T")
	check("release modifiers restores normal shot",router._kick_params("shot").style=="straight")
	var emitted:Array=[]
	router.intent_emitted.connect(func(e):emitted.append(e.duplicate(true)))
	router.feed("placed_shot",true,"key:T");router.feed("shot",true,"mouse:1")
	router.step(.4);router.feed("shot",false,"mouse:1")
	var committed:Array=emitted.filter(func(e):return e.phase=="commit" and e.action=="shoot_straight")
	check("charge and release submits placed shot once",committed.size()==1 and committed[0].style=="placed" and committed[0].power>.2)
	router.feed("placed_shot",false,"key:T");router.step(.4)
	router.feed("shot",true,"mouse:1");router.feed("cancel",true,"mouse:3");router.feed("shot",false,"mouse:1")
	check("cancelled charge does not fire",emitted.filter(func(e):return e.phase=="commit" and e.action.begins_with("shoot")).size()==1)
	var p:=FootballPhysicsProfile.playable()
	var normal:Dictionary=FootballKickMapping.from_input_intent({"action":"shoot_straight","direction":Vector3.FORWARD,"power":.8,"elevation_deg":12},p)
	push.power=.8
	var mapped_push:=FootballKickMapping.from_input_intent(push,p)
	check("placed has lower force and elevation",mapped_push.power_01<normal.power_01 and mapped_push.lift_degrees<normal.lift_degrees)
	for sign_spin in [-1.0,1.0]:
		var mapped:=FootballKickMapping.from_input_intent({"action":"shoot_curve","direction":Vector3.FORWARD,"power":.8,"elevation_deg":12,"spin":Vector3.UP*sign_spin},p)
		var v:=Vector3(0,6,-22);var w:Vector3=mapped.spin_world;var position:=Vector3.ZERO
		for i in 60:
			var step:=FootballBallForces.airborne_step(v,w,1.0/120.0,Vector3.ZERO,p)
			v=step.velocity;w=step.spin;position+=step.motion
		check("actual aerodynamic bend "+str(sign_spin),position.x*sign_spin>.03 and position.is_finite())
	quit(0 if ok else 1)
