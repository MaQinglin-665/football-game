extends SceneTree
const Router=preload("res://addons/football_shift_tiers/shift_tier_router.gd")
var checks:Array=[]
func check(label:String,ok:bool)->void:
	checks.append({"label":label,"passed":ok});print("PASS " if ok else "FAIL ",label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var r=Router.new({"toggle_sprint":true,"deliberate_touch_dispatch":"host_next_contact"})
	var intents:Array=[]
	r.intent_emitted.connect(func(i):intents.append(i))
	r.set_context({"phase":"live","possession":"foot","capabilities":{"push_ball":true,"close_control":true}},0)
	r.feed_shift(true,"left",false,1000);r.feed_shift(false,"left",false,60000)
	check("tap release retains run",r.policy().tier=="run" and not r.policy().shift_held)
	r.feed_shift(true,"left",false,500000)
	r.feed_shift(true,"left",true,520000)
	r.feed_shift(false,"left",false,560000)
	check("second separate tap stops, echo ignored",r.policy().tier=="walk_jog")
	r.feed_shift(true,"left",false,1000000);r.feed_shift(false,"left",false,1050000)
	r.feed_shift(true,"left",false,1120000);r.feed_shift(false,"left",false,1170000)
	check("double requests one heavy touch and keeps run",intents.size()==1 and r.policy().tier=="run")
	r.set_context({"close_override":true},1200000)
	check("close control overrides latch",r.policy().tier=="walk_jog")
	r.set_context({"close_override":false,"possession":"none"},1300000)
	check("possession changes retain toggle",r.policy().tier=="run")
	r.set_context({"paused":true},1400000);r.set_context({"paused":false},1500000)
	check("pause clears sprint",r.policy().tier=="walk_jog")
	r.feed_shift(true,"left",false,1800000)
	r.set_context({"focused":false},1850000);r.set_context({"focused":true},1900000)
	r.feed_shift(true,"left",true,1950000);r.feed_shift(false,"left",false,2000000)
	check("focus restore cannot reenable held key",r.policy().tier=="walk_jog")
	r.feed_shift(true,"right",false,2400000);r.feed_shift(false,"right",false,2450000)
	check("right shift works",r.policy().tier=="run")
	r.set_context({"restart_id":"new"},2500000)
	check("restart clears sprint",r.policy().tier=="walk_jog")
	for scene in ["training_3v3","match_6v6","match_9v9","match"]:
		var game=load("res://scenes/"+scene+".tscn").instantiate()
		game.test_mode=true;root.add_child(game);await process_frame
		game.start_match(false);game.set_phase(game.Phase.PLAY);game.sync_input_context()
		var t:int=Time.get_ticks_usec()
		var event:=InputEventAction.new();event.action="ff_sprint";event.pressed=true
		game.input_bridge.shift_input.feed_event(event,t)
		event.pressed=false;game.input_bridge.shift_input.feed_event(event,t+10000)
		check(scene+" actual player run tier after release",game.player.movement_tier=="run")
		game.pause_match();game.sync_input_context()
		check(scene+" actual player clears on pause",game.player.movement_tier=="walk_jog")
		game.shutdown_audio();game.queue_free()
		for i in 3:await process_frame
	FileAccess.open("res://../verification/shift_toggle.json",FileAccess.WRITE).store_string(JSON.stringify(checks,"  "))
	quit(0 if checks.all(func(c):return c.passed) else 1)
