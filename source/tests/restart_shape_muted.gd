extends "res://tests/restart_shapes.gd"

func _initialize() -> void:
	AudioServer.set_bus_mute(0,true)
	super._initialize()
