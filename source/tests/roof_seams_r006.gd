extends SceneTree
# R006: the closed glass panels must stay inside the sloped ring's opening, so the two
# transparent layers never overlap (overlap = darker/lighter corner triangles).
var failed:=0
func check(label:String,ok:bool,info:Variant="")->void:
	if not ok:failed+=1
	print("PASS " if ok else "FAIL ",label," ",info)
class StadiumMock extends Node3D:
	var dimensions:Resource
	var seat_lod_meshes:Array=[]
	func replace_material(_a,_b)->void:pass
func _initialize()->void:
	var holder:=StadiumMock.new();holder.dimensions=preload("res://addons/modern_stadium/stadium_dimensions.gd").new()
	var r2:=Node3D.new();r2.name="Roof";holder.add_child(r2);root.add_child(holder)
	var art:Node3D=preload("res://art/bernabeu.gd").new();root.add_child(art)
	art.build(holder)
	var d=holder.dimensions
	var x:float=d.pitch_width*.5+8.;var z:float=d.pitch_length*.5+10.
	var v:PackedVector3Array=art.get_node("ArtGlassRoof").mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var flat:=v.size() # Central glazing is separated from the opaque outer canopy in R008.
	var worst:=0.0
	for i in flat:
		worst=maxf(worst,pow(absf(v[i].x)/x,4.0)+pow(absf(v[i].z)/z,4.0))
	check("panel vertices inside ring opening",worst<=1.0+1e-4,snappedf(worst,.0001))
	check("outer canopy has independent opaque surface",art.has_node("OuterOpaqueCanopy") and art.get_node("OuterOpaqueCanopy").mesh.surface_get_material(0) is StandardMaterial3D)
	print("RESULT ","PASS" if failed==0 else "FAIL %d"%failed)
	quit(1 if failed else 0)
