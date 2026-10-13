extends "res://tests/three_turn043_contact_completion.gd"
func start()->void:
	game=load("res://scenes/training_3v3.tscn").instantiate();game.test_mode=true;root.add_child(game)
	for i in 4:await process_frame
	for label in ["single_on","single_off","rapid_pair"]:
		await reset_case(label,"B",Vector2(0,.28),true)
		set_keys([KEY_W]);await ticks(120)
		key(KEY_SHIFT,true);await ticks(1);key(KEY_SHIFT,false)
		if label=="single_off":
			await ticks(120);key(KEY_SHIFT,true);await ticks(1);key(KEY_SHIFT,false)
		elif label=="rapid_pair":
			await ticks(10);key(KEY_SHIFT,true);await ticks(1);key(KEY_SHIFT,false)
		await ticks(180)
	set_keys([])
	var report:String="res://../verification/shift_carry_before.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):report=arg.trim_prefix("--output=")
	FileAccess.open(report,FileAccess.WRITE).store_string(JSON.stringify({"cases":cases,"rows":rows,"contacts":contacts,"scope":"Declared isolated starts; actual input, motor, feet and ball. No natural-match or visual acceptance."}))
	game.shutdown_audio();game.queue_free()
	for i in 4:await process_frame
	quit()
