extends "res://tests/shift_release_checks.gd"

func _initialize() -> void:
	AudioServer.set_bus_mute(0,true)
	super._initialize()
