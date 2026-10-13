extends Node3D
## Passive geometry interface. No _process, ball, team, restart or scoring logic.
@export var dimensions: Resource
@export var build_details: Dictionary = {}
@export var seat_lod_meshes: Array[Mesh] = []
@export var seat_lod_near_distance: float = 70.0
@export var seat_lod_mid_distance: float = 90.0
@export var detail_hysteresis: float = 6.0
@export var net_lod_distance: float = 32.0
var _detail_batches: Array = []
var _net_pairs: Array = []
var _far_proxies: Dictionary = {}
var _seats_enabled: bool = true
var _crowd_enabled: bool = true

func get_layout() -> Dictionary:
	return dimensions.layout() if dimensions else {}

func replace_material(slot: String, replacement: Material) -> int:
	var changed := 0
	for node in find_children("*", "GeometryInstance3D", true, false):
		if str(node.get_meta("material_slot", "")) == slot:
			node.material_override = replacement
			changed += 1
	return changed

func set_crowd_visible(enabled: bool) -> void:
	_crowd_enabled=enabled
	for node in find_children("Crowd_*", "MultiMeshInstance3D", true, false):
		node.visible = enabled

func set_seat_detail_enabled(enabled: bool) -> void:
	_seats_enabled=enabled
	for node in find_children("Seats_*", "MultiMeshInstance3D", true, false):
		node.visible = enabled
	for node in find_children("FarSeats_*","MeshInstance3D",true,false):
		# Re-enabling waits for the next distance update to avoid overlapping levels.
		node.visible=false

func set_perimeter_collision_enabled(enabled: bool) -> void:
	for node in get_node("Perimeter").find_children("*", "StaticBody3D", true, false):
		node.collision_layer = 1 if enabled else 0

func update_detail_for_camera(camera_world_position: Vector3, seats_distance := 215.0, crowd_distance := 170.0) -> void:
	## Optional: call from host at ~4 Hz; root has no autonomous processing.
	if _detail_batches.is_empty():
		_detail_batches=find_children("*","MultiMeshInstance3D",true,false)
		for node in _detail_batches:
			if str(node.name).begins_with("Seats_"):
				var proxy=node.get_parent().get_node_or_null("Far"+str(node.name))
				if proxy: _far_proxies[node.get_instance_id()]=proxy
	for batch in _detail_batches:
		var crowd: bool = str(batch.name).begins_with("Crowd_")
		var limit: float = maxf(0.0,crowd_distance if crowd else seats_distance)
		var bounds: AABB = batch.multimesh.custom_aabb
		var local_camera: Vector3 = batch.to_local(camera_world_position)
		var closest: Vector3 = local_camera.clamp(bounds.position,bounds.end)
		var distance: float = (batch.to_global(closest)-camera_world_position).length()
		var was_visible: bool = bool(batch.get_meta("range_visible",true))
		# A small caller range must still restore detail when the camera enters it.
		# Zero/negative ranges explicitly hide detail instead of growing by the margin.
		var range_margin: float = minf(maxf(0.0,detail_hysteresis),limit*0.25)
		var in_range: bool = limit>0.0 and distance<=limit+(range_margin if was_visible else -range_margin)
		batch.set_meta("range_visible",in_range)
		batch.visible=in_range and (_crowd_enabled if crowd else _seats_enabled)
		if crowd or seat_lod_meshes.size()!=3: continue
		var current: int = int(batch.get_meta("lod_level",0))
		var desired: int = current
		if current==0:
			if distance>seat_lod_mid_distance+detail_hysteresis: desired=2
			elif distance>seat_lod_near_distance+detail_hysteresis: desired=1
		elif current==1:
			if distance<seat_lod_near_distance-detail_hysteresis: desired=0
			elif distance>seat_lod_mid_distance+detail_hysteresis: desired=2
		else:
			if distance<seat_lod_near_distance-detail_hysteresis: desired=0
			elif distance<seat_lod_mid_distance-detail_hysteresis: desired=1
		if desired!=current:
			batch.multimesh.mesh=seat_lod_meshes[desired]
			batch.set_meta("lod_level",desired)
		var proxy=_far_proxies.get(batch.get_instance_id())
		if proxy:
			var represented: bool = in_range and _seats_enabled
			proxy.visible=represented and desired==2
			batch.visible=represented and desired!=2
	if _net_pairs.is_empty():
		for name in ["North","South"]:
			var goal = get_node("Goals/"+name)
			if goal.has_node("NetCoarse"): _net_pairs.append([goal.get_node("Net"),goal.get_node("NetCoarse")])
	for pair in _net_pairs:
		var bounds: AABB = pair[0].mesh.get_aabb()
		var p: Vector3 = pair[0].to_local(camera_world_position)
		var distance: float = pair[0].to_global(p.clamp(bounds.position,bounds.end)).distance_to(camera_world_position)
		var coarse: bool = bool(pair[0].get_meta("coarse_active",false))
		coarse=distance>net_lod_distance+(detail_hysteresis if not coarse else -detail_hysteresis)
		pair[0].set_meta("coarse_active",coarse)
		pair[0].visible=not coarse
		pair[1].visible=coarse

func get_detail_stats() -> Dictionary:
	var counts: Array[int] = [0,0,0]
	var visible_seats: int = 0
	var hidden_seats: int = 0
	var net_coarse: int = 0
	var proxy_batches: int = 0
	var represented_seats: int = 0
	for batch in find_children("Seats_*","MultiMeshInstance3D",true,false):
		var proxy=batch.get_parent().get_node_or_null("Far"+str(batch.name))
		var represented: bool = batch.visible or (proxy!=null and proxy.visible)
		if represented:
			counts[int(batch.get_meta("lod_level",0))]+=1
			represented_seats+=batch.multimesh.instance_count
		if proxy!=null and proxy.visible: proxy_batches+=1
		if batch.visible:
			visible_seats+=batch.multimesh.instance_count
		else: hidden_seats+=batch.multimesh.instance_count
	for node in find_children("NetCoarse","MeshInstance3D",true,false):
		if node.visible: net_coarse+=1
	return {"seat_near_batches":counts[0],"seat_mid_batches":counts[1],"seat_far_batches":counts[2],"visible_seat_instances":visible_seats,"hidden_seat_instances":hidden_seats,"coarse_nets":net_coarse,"far_proxy_batches":proxy_batches,"represented_seat_instances":represented_seats,"seat_detail_enabled":_seats_enabled,"crowd_enabled":_crowd_enabled}
