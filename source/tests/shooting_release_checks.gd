extends "res://tests/shooting_chain_qa.gd"

func _initialize() -> void:
	AudioServer.set_bus_mute(0,true) # Only this validation process.
	super._initialize()
