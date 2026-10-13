extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	var game:Node=load("res://scenes/match.tscn").instantiate();game.test_mode=true;root.add_child(game)
	game.settings_menu.values.lighting=1;game.settings_menu.apply_values(false)
	for i in 15:await process_frame
	print("NORMAL_GAME_QUIT_REQUESTED")
	game.quit_game()
