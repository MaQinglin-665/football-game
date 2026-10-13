extends "res://addons/football_physics/football_ball.gd"
var held := false
var visual: MeshInstance3D
var marker: MeshInstance3D
class MockMatch:
	enum Phase { MENU, COUNTDOWN, PLAY, RESTART, GOAL, PAUSED, FINISHED }
	var phase := Phase.PLAY
var match_controller := MockMatch.new()
func _ready() -> void:
	super._ready()
	auto_step = false
	set_physics_process(false)
	set_process(false)
	visual = MeshInstance3D.new()
	add_child(visual)
	marker = MeshInstance3D.new()
	add_child(marker)

func _process(_delta: float) -> void:
	if is_instance_valid(marker):
		marker.global_position = Vector3(position.x,.045,position.z)
		marker.visible = position.y<1 and match_controller.phase!=match_controller.Phase.MENU

func _substep(delta: float) -> void:
	if not held:
		var before_spin := spin_rads
		super._substep(delta)
		_advance_visual_spin((before_spin + spin_rads) * 0.5, delta)

func _advance_visual_spin(spin_world: Vector3, delta: float) -> void:
	# Visual only: integrate at the same substeps as the existing ball motion.
	# Modulo a full turn preserves orientation; it never caps elapsed rotation.
	if not is_instance_valid(visual) or not spin_world.is_finite() \
			or not is_finite(delta) or delta <= 0.0:
		return
	var speed := spin_world.length()
	var angle := speed * delta
	if speed <= 0.00000001 or not is_finite(speed) or not is_finite(angle):
		return
	var axis := (global_basis.orthonormalized().inverse() * (spin_world / speed)).normalized()
	var turn := Quaternion(axis, fposmod(angle, TAU))
	visual.quaternion = (turn * visual.quaternion).normalized()

