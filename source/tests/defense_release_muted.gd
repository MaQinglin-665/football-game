extends "res://tests/defense_physical.gd"

func _initialize() -> void:
	AudioServer.set_bus_mute(0,true)
	super._initialize()
