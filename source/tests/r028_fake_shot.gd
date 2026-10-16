extends SceneTree
var ok:=true
func check(label:String,value:bool)->void:
	ok=ok and value;print("PASS " if value else "FAIL ",label)
func _initialize()->void:
	var router:=preload("res://addons/football_input/intent_router.gd").new()
	router.set_context({"phase":"live","possession":"foot","capabilities":{"shoot_straight":true,"cut_ball":true,"pass_ground":true}})
	var events:Array=[]
	router.intent_emitted.connect(func(e):events.append(e.duplicate(true)))
	router.feed("left",true,"key:A")
	router.feed("shot",true,"mouse:1");router.step(.3)
	router.feed("pass",true,"mouse:2")
	var cuts:Array=events.filter(func(e):return e.phase=="commit" and e.action=="cut_ball")
	check("fake shot emits one directional cut",cuts.size()==1 and cuts[0].get("cut_direction_selected",false))
	router.feed("pass",true,"mouse:2");router.feed("shot",false,"mouse:1");router.feed("pass",false,"mouse:2")
	check("holding and releasing does not shoot or pass",events.filter(func(e):return e.phase=="commit").size()==1)
	router.feed("left",false,"key:A");router.step(.4)
	router.feed("pass",true,"mouse:2");router.step(.3);router.feed("pass",false,"mouse:2")
	check("fresh right click still passes",events.filter(func(e):return e.phase=="commit" and e.action=="pass_ground").size()==1)
	router.step(.4);router.feed("shot",true,"mouse:1");router.feed("pass",true,"mouse:2")
	cuts=events.filter(func(e):return e.phase=="commit" and e.action=="cut_ball")
	check("no direction delegates to actual ball position",cuts.size()==2 and not cuts[1].get("cut_direction_selected",true))
	router.feed("shot",false,"mouse:1");router.feed("pass",false,"mouse:2")
	FootballSemanticInputMap.install_defaults()
	var q:=InputEventKey.new();q.physical_keycode=KEY_Q;q.pressed=true
	check("Q is unbound",FootballSemanticInputMap.token_for_event(q)=="")
	quit(0 if ok else 1)
