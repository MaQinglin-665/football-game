extends RefCounted
## Host calls tick(delta); stadium itself remains passive. Never catches up in a loop.
var stadium: Node3D
var camera: Camera3D
var elapsed: float = 0.0
var interval: float = 0.25

func configure(target: Node3D, view: Camera3D) -> void:
	stadium=target
	camera=view
	elapsed=0.0
	refresh()

func refresh() -> void:
	if is_instance_valid(stadium) and is_instance_valid(camera):
		stadium.update_detail_for_camera(camera.global_position)

func tick(delta: float) -> void:
	elapsed+=maxf(0.0,delta)
	if elapsed>=maxf(0.25,interval):
		elapsed=0.0
		refresh()
