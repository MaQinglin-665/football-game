extends RefCounted
## Apply after the host's general material mapping. Touches two seating slots only.
static func apply(stadium: Node, navy: Material = null, blue: Material = null) -> Dictionary:
	if navy==null: navy=load("res://addons/modern_stadium/materials/SeatNavy.tres").duplicate()
	if blue==null: blue=load("res://addons/modern_stadium/materials/SeatBlue.tres").duplicate()
	return {"SeatNavy":stadium.replace_material("SeatNavy",navy),"SeatBlue":stadium.replace_material("SeatBlue",blue)}
