extends RefCounted
const Host := preload("res://addons/football_keeper/keeper_host.gd")

static func attach(game: Node) -> Node:
	if game.training_configuration != null: return null
	if game.has_node("KeeperActions04"): return game.get_node("KeeperActions04")
	var host := Host.new()
	host.name = "KeeperActions04"
	host.game = game
	game.add_child(host)
	host.bind_match()
	return host
