extends "res://tests/integration_checks.gd"
var evidence_rows:Array=[]
var observer:Camera3D
func run()->void:
	game=load("res://scenes/training_3v3.tscn").instantiate();game.test_mode=true;root.add_child(game)
	game.settings_menu.values.volume=0;game.settings_menu.apply_values(false)
	game.training_mode.defensive_opening=true;game.start_match(false)
	await ticks(100)
	game.ai_enabled=false
	if native:
		root.mode=Window.MODE_WINDOWED;root.size=Vector2i(1280,720)
		observer=Camera3D.new();root.add_child(observer);observer.current=true
	var map=preload("res://addons/football_input/input_map.gd")
	var q:=InputEventKey.new();q.physical_keycode=KEY_Q;q.pressed=true
	var pass_mouse:=InputEventMouseButton.new();pass_mouse.button_index=MOUSE_BUTTON_RIGHT;pass_mouse.pressed=true
	check("Q maps only to cut",map.token_for_event(q)=="cut")
	check("right mouse maps to pass",map.token_for_event(pass_mouse)=="pass")
	check("no duplicate bindings",map.conflicts().is_empty())
	for item in [[.20,Vector3.LEFT,"INSIDE",1],[.20,Vector3.RIGHT,"OUTSIDE",1],[-.20,Vector3.RIGHT,"INSIDE",-1],[-.20,Vector3.LEFT,"OUTSIDE",-1],[.20,Vector3.LEFT,"INSIDE",1,true],[-.20,Vector3.LEFT,"OUTSIDE",-1,true]]:
		fixture();var actor=game.player
		actor.foot.cancel();game.ball.position=actor.position+Vector3(item[0],.11,-.43);game.ball.previous_position=game.ball.position;game.ball.velocity=Vector3.ZERO;game.ball.take(actor)
		if item.size()>4:
			actor.velocity=Vector3.FORWARD*3.0;actor.set_move_intent(Vector3.FORWARD*.54);game.ball.velocity=actor.velocity
		if native:
			observer.position=actor.position+Vector3(1.5,1.15,1.7);observer.look_at(actor.position+Vector3(0,.55,-.2))
		actor.refresh_pose(1.0/120)
		var accepted:bool=actor.foot.request_cut(item[1]);var seq:int=actor.foot.sequence
		var selected_surface:String=actor.foot.surface;var selected_side:int=actor.foot.side
		var start:Vector3=game.ball.position
		var events:Array=[]
		var callback=func(e:Dictionary):
			if e.get("actor")==actor and e.get("success",false) and int(e.get("action_sequence",-1))==seq:events.append(e.duplicate())
		game.contact_hub.contact_resolved.connect(callback)
		var hit:=false;var failure:="";var outgoing:=Vector3.ZERO
		for i in 45:
			await ticks(1)
			if actor.foot.sequence==seq:
				if actor.foot.hit:hit=true;outgoing=game.ball.velocity
				failure=actor.foot.contact_failure
			if native and item.size()==4 and i in [5,13]:
				paused=true;await capture("cut_%s_%s_%s"%[selected_side,selected_surface,i]);paused=false
		game.contact_hub.contact_resolved.disconnect(callback)
		var details:Dictionary={"accepted":accepted,"surface":selected_surface,"side":selected_side,"hit":hit,"failure":failure,"velocity":outgoing,"events":events.size(),"displacement":game.ball.position-start}
		evidence_rows.append(details)
		check("cut real contact "+str(item),accepted and selected_surface==item[2] and selected_side==item[3] and hit and outgoing.dot(item[1])>.1,details)
		check("cut at most one success notification "+str(item),events.size()<=1,events.size())
	fixture();game.player.foot.cancel();game.ball.take(game.player);game.ball.position=game.player.position+Vector3(3,.11,0)
	check("distant ball cannot cut",not game.player.foot.request_cut(Vector3.LEFT))
	fixture();game.player.foot.cancel();game.ball.take(game.player);game.sync_input_context()
	key(KEY_Q,true);await ticks(1);key(KEY_Q,false);await ticks(1)
	check("Q emits cut intent and never starts pass charge",game.input_bridge.adapter.snapshot().charge.is_empty() and (game.player.foot.touch_plan.has("cut_style") or game.player.foot.buffer.get("kind","")=="CUT"))
	fixture();game.player.foot.cancel();game.ball.take(game.player);game.sync_input_context()
	mouse(MOUSE_BUTTON_RIGHT,true);await ticks(1)
	key(KEY_Q,true);await ticks(1);key(KEY_Q,false)
	check("cut cannot interrupt pass charge",not game.input_bridge.adapter.snapshot().charge.is_empty() and not game.player.foot.touch_plan.has("cut_style") and game.player.foot.buffer.get("kind","")!="CUT")
	mouse(MOUSE_BUTTON_MIDDLE,true);mouse(MOUSE_BUTTON_MIDDLE,false);mouse(MOUSE_BUTTON_RIGHT,false)
	for direction in [Vector3.BACK,Vector3.LEFT]:
		fixture();game.player.foot.cancel();game.ball.take(game.player)
		check("legacy nudge preserved "+str(direction),game.player.foot.request_nudge(direction))
		await ticks(40)
	FileAccess.open(evidence.path_join("cut_pull.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"cuts":evidence_rows},"  "))
	game.shutdown_audio();quit(0 if checks.all(func(c):return c.passed) else 1)
