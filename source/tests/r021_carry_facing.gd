extends "res://tests/r019_edge_control.gd"
func ticks(n:int)->void:
	var aligned:bool=true
	for i in n:
		await super.ticks(1)
		aligned=aligned and absf(angle_difference(game.player.hip_yaw,game.player.rotation.y))<.01 and game.player.body_facing.dot(Vector3(-sin(game.player.rotation.y),0,-cos(game.player.rotation.y)))>.999
	check("carry body yaw follows view throughout",aligned)
