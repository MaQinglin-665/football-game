extends "res://tests/three_turn043_contact_completion.gd"
var balance_samples:Array=[]
func ticks(count:int)->void:
	for i in count:
		await super.ticks(1)
		balance_samples.append({"case":case_name,"tick":case_tick,"load":game.player.dribble_balance.load,"cue":game.player.dribble_balance.cue,"velocity":game.player.velocity,"foot":game.player.foot.kind})
func start()->void:
	game=load("res://scenes/training_3v3.tscn").instantiate();game.test_mode=true;root.add_child(game)
	for i in 4:await process_frame
	await reset_case("probe_cut_exit","B",Vector2(0,.28),true)
	set_keys([KEY_CTRL,KEY_W]);await ticks(90)
	set_keys([KEY_CTRL,KEY_A]);await ticks(24)
	set_keys([KEY_CTRL,KEY_D]);await ticks(12)
	key(KEY_Q,true);await ticks(1);key(KEY_Q,false);await ticks(60)
	set_keys([KEY_W]);key(KEY_SHIFT,true);await ticks(1);key(KEY_SHIFT,false);await ticks(100)
	var left:bool=balance_samples.any(func(x):return x.load.y<-.05)
	var right:bool=balance_samples.any(func(x):return x.load.y>.05)
	check("actual left and right steps produce opposite visible weight transfer",left and right)
	check("visible shoulder cue stays bounded",balance_samples.all(func(x):return x.cue.length()<.17))
	check("Q after probing resolves one real directional cut",contacts.any(func(c):return c.event.success and not String(c.plan.get("cut_style","")).is_empty()))
	check("no duplicate ordinary contact after combination",unique_contacts())
	check("probe combination has no height explosion",rows.all(func(x):return float(x.ball[1])<.35))
	await reset_case("release_cancel_reverse","B",Vector2(0,.28),true)
	set_keys([KEY_W]);key(KEY_SHIFT,true);await ticks(1);key(KEY_SHIFT,false);await ticks(120)
	key(KEY_SHIFT,true);await ticks(1);key(KEY_SHIFT,false);set_keys([KEY_S]);await ticks(36)
	check("release assistance does not keep forward intent on reverse",game.player.move_intent.dot(game.player.body_facing)<.05)
	set_keys([]);await ticks(90)
	check("no input still stops the actor",Vector2(game.player.velocity.x,game.player.velocity.z).length()<.15)
	check("balance settles without perpetual fake motion",game.player.dribble_balance.load.length()<.06)
	FileAccess.open("res://../verification/dribble_rhythm_play.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"rows":rows,"contacts":contacts,"balance":pack(balance_samples),"scope":"Isolated real input/motor/shoe tests; no natural beating-defender or visual acceptance."}))
	game.shutdown_audio();game.queue_free()
	for i in 4:await process_frame
	quit(0 if checks.all(func(c):return c.passed) else 1)
