extends "res://tests/contact_flow_check.gd"
var results:Array=[]
func run()->void:
	game=load("res://scenes/training_3v3.tscn").instantiate();game.test_mode=true;root.add_child(game)
	await ticks(6);game.hud.menu.get_node("StartMatch").pressed.emit();await ticks(8)
	game.tactics_bridge.set_physics_process(false);game.training_mode.set_physics_process(false);game.ai_enabled=true
	game.contact_hub.contact_resolved.connect(func(e):
		if e.get("actor")==actor and e.get("success",false):events.append({"case":label,"action":e.get("action",""),"side":actor.foot.side,"sequence":actor.foot.sequence}))
	for defender in [game.player,game.agents[0]]:
		for spec in [[-.47,4.0],[.47,4.0],[-.7,6.0],[.7,6.0],[-.45,10.0],[.45,10.0],[1.6,4.0],[.5,-5.0]]:
			label=("human" if defender.is_human else "ai")+str(spec)
			stage(defender,Vector3(spec[0],0,-.9),Vector3(0,0,spec[1]))
			var initial:Vector3=actor.position;var rotation_before:Vector3=actor.rotation
			await observe(60)
			var reachable:bool=absf(spec[0])<1.0 and spec[1]>0
			check(label+" actual contact or rejection",auto_seen and hits().size()==1 if reachable else not auto_seen and hits().is_empty())
			check(label+" no automatic steering",actor.position.distance_to(initial)<.001 and actor.rotation==rotation_before)
			results.append({"case":label,"automatic":auto_seen,"hits":hits().size(),"side":actor.foot.side,"failure":actor.foot.contact_failure,"root_moved":actor.position.distance_to(initial),"rotation_changed":actor.rotation.distance_to(rotation_before)})
	var out:="res://../verification/intercepts.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):out=arg.trim_prefix("--output=")
	FileAccess.open(out,FileAccess.WRITE).store_string(JSON.stringify({"results":results,"events":events,"traces":traces}))
	var ok:bool=checks.all(func(c):return c.ok)
	game.shutdown_audio();game.queue_free();await ticks(3);quit(0 if ok else 1)
