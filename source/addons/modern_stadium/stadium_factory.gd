extends RefCounted
## Original procedural geometry. Geometry only; no ball, teams or match rules.
const Batch = preload("res://addons/modern_stadium/geometry_batch.gd")
const API = preload("res://addons/modern_stadium/layout_api.gd")
const SLOT_NAMES = ["Turf","LinesWhite","GoalFrame","GoalNet","SeatNavy","SeatBlue","Concrete","Metal","Roof","Board","Flag","Glass","Light","Crowd"]
var d: Resource
var root: Node3D
var materials: Dictionary = {}
var seat_total: int = 0
var crowd_total: int = 0
var batch_count: int = 0
var build_started: int = 0

static func build(config: Resource = null) -> Node3D:
	var factory = new()
	factory.d = config if config else load("res://addons/modern_stadium/presets/full_105x68.tres")
	return factory._build()

static func build_training(config: Resource) -> Node3D:
	var factory = new()
	factory.d = config
	return factory._build(true)

func _build(training_only := false) -> Node3D:
	build_started = Time.get_ticks_msec()
	var errors: PackedStringArray = d.validation_errors()
	if not errors.is_empty():
		push_error("Stadium config: " + "; ".join(errors))
		return null
	root = API.new()
	root.name = "ModernStadium"
	root.dimensions = d
	for slot in SLOT_NAMES:
		materials[slot] = load("res://addons/modern_stadium/materials/%s.tres" % slot)
	materials["Turf"] = materials["Turf"].duplicate()
	materials["Turf"].set_shader_parameter("stripe_width",d.pitch_length/14.0)
	for name in ["Pitch","Markings","Goals","Flags","TechnicalAreas","Bowl","Roof","Perimeter","Anchors"]:
		_group(root,name)
	_pitch()
	_markings()
	_goals()
	_flags()
	if not training_only:
		_technical()
		_bowl()
		_roof()
	_perimeter()
	_anchors()
	root.build_details = {"seat_instances":seat_total,"crowd_instances":crowd_total,"geometry_batches":batch_count,"build_ms":Time.get_ticks_msec()-build_started,"quality":d.quality_label,"generator_version":"1.2-stand-patch","seat_nodes":d.tier_rows.size()*d.sector_count,"no_dynamic_crowd":true}
	return root

func _group(parent: Node, name: String) -> Node3D:
	var n = Node3D.new()
	n.name = name
	parent.add_child(n)
	return n

func _mesh(parent: Node, name: String, batch: RefCounted, slot: String, shadow := true) -> MeshInstance3D:
	var node = MeshInstance3D.new()
	node.name = name
	node.mesh = batch.mesh(materials[slot])
	node.set_meta("material_slot",slot)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	batch_count += 1
	return node

func _solid_box(parent: Node, name: String, size: Vector3, center: Vector3, enabled := true) -> StaticBody3D:
	var body = StaticBody3D.new()
	body.name = name
	body.position = center
	body.collision_layer = 1 if enabled else 0
	body.collision_mask = 0
	var collision = CollisionShape3D.new()
	collision.name = "Shape"
	var shape = BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	return body

func _pitch() -> void:
	var hw: float = d.pitch_width*0.5
	var hl: float = d.pitch_length*0.5
	var turf = Batch.new()
	turf.top_rect(-hw-d.runoff,hw+d.runoff,-hl-d.runoff,hl+d.runoff,0.0)
	_mesh(root.get_node("Pitch"),"TurfSurface",turf,"Turf",false)
	var apron = Batch.new()
	var sx: float = hw+78.0
	var sz: float = hl+80.0
	apron.top_rect(-sx,sx,-sz,sz,-0.014)
	_mesh(root.get_node("Pitch"),"ServiceApron",apron,"Concrete",false)
	_solid_box(root.get_node("Pitch"),"Ground",Vector3(sx*2,.50,sz*2),Vector3(0,-.25,0))

func _markings() -> void:
	var hw: float = d.pitch_width*0.5
	var hl: float = d.pitch_length*0.5
	var w: float = d.line_width
	var y: float = 0.004
	var b = Batch.new()
	# Paint belongs to the pitch: boundary OUTSIDE edges are exactly +/- hw, hl.
	for sx in [-1.0,1.0]:
		var xc: float = sx*(hw-w*.5)
		b.top_rect(xc-w*.5,xc+w*.5,-hl,hl,y)
	for sz in [-1.0,1.0]:
		var zc: float = sz*(hl-w*.5)
		b.top_rect(-hw+w,hw-w,zc-w*.5,zc+w*.5,y)
	b.top_rect(-hw+w,hw-w,-w*.5,w*.5,y)
	b.ring(0,0,d.circle_radius,w,y,0,TAU,192)
	b.disk(0,0,.11,y+.0002)
	for side in [-1.0,1.0]:
		for depth in [d.goal_area_depth,d.penalty_area_depth]:
			var halfbox: float = d.goal_width*.5+depth
			var near_z: float = side*(hl-depth+w*.5)
			b.top_rect(-halfbox,halfbox,near_z-w*.5,near_z+w*.5,y)
			for sx in [-1.0,1.0]:
				var xc: float = sx*(halfbox-w*.5)
				var lo: float = minf(side*(hl-w),side*(hl-depth+w))
				var hi: float = maxf(side*(hl-w),side*(hl-depth+w))
				b.top_rect(xc-w*.5,xc+w*.5,lo,hi,y)
		var pz: float = side*(hl-d.penalty_distance)
		b.disk(0,pz,.11,y+.0002)
		var outside: float = d.penalty_area_depth-d.penalty_distance
		var alpha: float = acos(outside/d.circle_radius)
		var angle: float = -PI*.5 if side>0 else PI*.5
		b.ring(0,pz,d.circle_radius,w,y,angle-alpha,angle+alpha,96)
		for sx in [-1.0,1.0]:
			var start: float = 0.0
			if sx>0 and side<0: start=PI*.5
			elif sx>0 and side>0: start=PI
			elif sx<0 and side>0: start=PI*1.5
			b.ring(sx*hw,side*hl,d.corner_radius,w,y,start,start+PI*.5,40)
	_mesh(root.get_node("Markings"),"RegulationPaint",b,"LinesWhite",false)

func _goals() -> void:
	var hl: float = d.pitch_length*.5
	var r: float = d.line_width*.5
	var post_x: float = (d.goal_width+d.line_width)*.5
	var top: float = d.goal_height+r
	for side in [-1.0,1.0]:
		var parent = _group(root.get_node("Goals"),"North" if side<0 else "South")
		var z: float = side*(hl-r)
		parent.set_meta("opening_width",d.goal_width)
		parent.set_meta("opening_height",d.goal_height)
		parent.set_meta("goal_line_outer_z",side*hl)
		var b = Batch.new()
		for sx in [-1.0,1.0]:
			var a = Vector3(sx*post_x,0,z)
			b.smooth_rod(a,Vector3(a.x,top,a.z),r,16)
			var body = StaticBody3D.new()
			body.name = "LeftPostBody" if sx<0 else "RightPostBody"
			body.position = Vector3(a.x,top*.5,z)
			body.collision_layer = 1
			body.collision_mask = 0
			var collision = CollisionShape3D.new()
			collision.name = "Shape"
			var shape = CylinderShape3D.new()
			shape.radius = r
			shape.height = top
			collision.shape = shape
			body.add_child(collision)
			parent.add_child(body)
		b.smooth_rod(Vector3(-post_x,top,z),Vector3(post_x,top,z),r,16)
		var body = StaticBody3D.new()
		body.name = "CrossbarBody"
		body.position = Vector3(0,top,z)
		body.rotation.z = PI*.5
		body.collision_layer = 1
		body.collision_mask = 0
		var collision = CollisionShape3D.new()
		collision.name = "Shape"
		var shape = CylinderShape3D.new()
		shape.radius = r
		shape.height = post_x*2
		collision.shape = shape
		body.add_child(collision)
		parent.add_child(body)
		_mesh(parent,"Frame",b,"GoalFrame")
		# Rounded near ropes share curved panel intersection points. Visual only.
		var back: float = side*(hl+d.goal_depth)
		var nx: float = d.goal_width*.5
		_mesh(parent,"Net",_net_geometry(side,z,back,.16,.0035,6),"GoalNet",false)
		var coarse = _mesh(parent,"NetCoarse",_net_geometry(side,z,back,.48,.006,4),"GoalNet",false)
		coarse.visible=false
		var supports = Batch.new()
		for sx in [-1.0,1.0]:
			supports.rod(Vector3(sx*(nx+.18),0,back),Vector3(sx*(nx+.18),2.72,back),.035,8)
			supports.rod(Vector3(sx*post_x,top,z),Vector3(sx*(nx+.18),2.65,back),.015,6)
			supports.box(Vector3(.24,.035,.24),Vector3(sx*post_x,.0175,z))
		_mesh(parent,"NetSupports",supports,"Metal")

func _flags() -> void:
	var hw: float = d.pitch_width*.5
	var hl: float = d.pitch_length*.5
	var poles = Batch.new()
	var fabric = Batch.new()
	for sx in [-1.0,1.0]:
		for sz in [-1.0,1.0]:
			var at = Vector3(sx*hw,0,sz*hl)
			poles.rod(at,at+Vector3(0,d.flag_height,0),.016,8)
			# Blunt cap and original yellow fabric, no emblems.
			poles.box(Vector3(.038,.025,.038),at+Vector3(0,d.flag_height,0))
			var a = at+Vector3(0,d.flag_height-.04,0)
			var c = at+Vector3(sx*.45,d.flag_height-.34,sz*.035)
			fabric.quad(a,a+Vector3(sx*.45,-.045,sz*.035),c,at+Vector3(0,d.flag_height-.30,0))
	_mesh(root.get_node("Flags"),"Poles",poles,"GoalFrame",false)
	_mesh(root.get_node("Flags"),"Flags",fabric,"Flag",false)

func _technical() -> void:
	var hw: float = d.pitch_width*.5
	var concrete = Batch.new()
	var metal = Batch.new()
	var glass = Batch.new()
	var seats = Batch.new()
	var paint = Batch.new()
	for sz in [-1.0,1.0]:
		var center: float = sz*12.0
		var x: float = hw+6.0
		concrete.box(Vector3(2.8,.14,10),Vector3(x,.07,center))
		metal.box(Vector3(.075,2.4,10),Vector3(x+1.35,1.27,center))
		metal.box(Vector3(2.8,.09,10),Vector3(x,2.47,center))
		glass.box(Vector3(.045,1.7,10),Vector3(x+1.25,1.5,center))
		for end in [-1.0,1.0]:
			glass.box(Vector3(2.6,2.2,.06),Vector3(x,1.24,center+end*5))
			metal.box(Vector3(.06,2.4,.06),Vector3(x-1.35,1.27,center+end*5))
		for i in range(18):
			var at = Vector3(x+.15,.64,center-4.5+i*.53)
			_bench_chair(seats,metal,at)
		# Technical area reaches exactly 1 m from touchline; 1 m beyond bench ends.
		var front: float = hw+1.0
		var rear: float = x+1.55
		for zz in [center-6,center+6]:
			for xx in range(ceili((rear-front)/.65)):
				var a: float = front+xx*.65
				paint.top_rect(a,minf(a+.36,rear),zz-.05,zz+.05,.004)
		for xx in [front,rear]:
			for k in range(19):
				var a: float = center-6+k*.65
				paint.top_rect(xx-.05,xx+.05,a,minf(a+.36,center+6),.004)
	_mesh(root.get_node("TechnicalAreas"),"BenchPlatforms",concrete,"Concrete")
	_mesh(root.get_node("TechnicalAreas"),"BenchFrames",metal,"Metal")
	_mesh(root.get_node("TechnicalAreas"),"OpaqueTintedCanopies",glass,"Glass")
	_mesh(root.get_node("TechnicalAreas"),"SubstituteSeats",seats,"SeatBlue")
	_mesh(root.get_node("TechnicalAreas"),"TechnicalPaint",paint,"LinesWhite",false)

func _outline(rx: float, rz: float, angle: float, y: float) -> Vector3:
	# Rounded rectangle (superellipse exponent 4), original closed bowl geometry.
	var c: float = cos(angle)
	var s: float = sin(angle)
	return Vector3(rx*signf(c)*sqrt(absf(c)),y,rz*signf(s)*sqrt(absf(s)))

func _seat_mesh() -> ArrayMesh:
	var b = Batch.new()
	b.box(Vector3(.44,.09,.42),Vector3(0,.12,0))
	b.box(Vector3(.44,.40,.07),Vector3(0,.35,.18),Basis(Vector3.RIGHT,-.10))
	return b.mesh()

func _crowd_mesh() -> ArrayMesh:
	var b = Batch.new()
	# Static seated silhouettes: 24 triangles, no animation, scripts or physics.
	b.box(Vector3(.32,.38,.20),Vector3(0,.40,.04))
	b.box(Vector3(.17,.20,.17),Vector3(0,.69,.04))
	return b.mesh()

func _instances(parent: Node, name: String, source: ArrayMesh, transforms: Array, tints: Array, slot: String, far_distance: float) -> void:
	if transforms.is_empty(): return
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = source
	mm.instance_count = transforms.size()
	var minimum = Vector3(INF,INF,INF)
	var maximum = Vector3(-INF,-INF,-INF)
	for i in range(transforms.size()):
		mm.set_instance_transform(i,transforms[i])
		mm.set_instance_color(i,tints[i])
		minimum = minimum.min(transforms[i].origin-Vector3(.55,.1,.55))
		maximum = maximum.max(transforms[i].origin+Vector3(.55,1.0,.55))
	mm.custom_aabb = AABB(minimum,maximum-minimum)
	var node = MultiMeshInstance3D.new()
	node.name = name
	node.multimesh = mm
	node.material_override = materials[slot]
	node.set_meta("material_slot",slot)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Keep spatial batch culling. Optional coarse distance detail is controlled by
	# API.update_detail_for_camera(), allowing host quality presets without fades.
	node.set_meta("detail_distance",far_distance)
	parent.add_child(node)
	batch_count += 1

func _bowl() -> void:
	var hw: float = d.pitch_width*.5
	var hl: float = d.pitch_length*.5
	var offset: float = 0.0
	var base_y: float = 1.20
	var segments: int = 192
	var seat = _seat_mesh()
	root.seat_lod_meshes.assign([seat,_seat_mid_mesh(),_seat_far_mesh()])
	var crowd = _crowd_mesh()
	var rng = RandomNumberGenerator.new()
	rng.seed = 20261002
	var rail = Batch.new()
	var trim = Batch.new()
	var stairs = Batch.new()
	for tier in range(d.tier_rows.size()):
		var group = _group(root.get_node("Bowl"),"Tier%d" % (tier+1))
		var rows: int = d.tier_rows[tier]
		var concrete = Batch.new()
		var transforms: Array = []
		var tints: Array = []
		var far_rows: Array = []
		var crowd_transforms: Array = []
		var crowd_colors: Array = []
		for sec in range(d.sector_count):
			transforms.append([])
			tints.append([])
			far_rows.append(Batch.new())
			crowd_transforms.append([])
			crowd_colors.append([])
		for row in range(rows):
			var rx: float = hw+15.0+offset+row*d.row_depth
			var rz: float = hl+16.0+offset+row*d.row_depth
			var y: float = base_y+row*d.row_rise
			for s in range(segments):
				var a: float = TAU*s/segments
				var b: float = TAU*(s+1)/segments
				var p = _outline(rx,rz,a,y)
				var q = _outline(rx,rz,b,y)
				var po = _outline(rx+d.row_depth,rz+d.row_depth,a,y)
				var qo = _outline(rx+d.row_depth,rz+d.row_depth,b,y)
				concrete.quad(p,q,qo,po)
				concrete.quad(p-Vector3(0,d.row_rise,0),q-Vector3(0,d.row_rise,0),q,p)
			for sec in range(d.sector_count):
				_append_far_seat_row(far_rows[sec],rx,rz,y,sec)
			# Equal-distance sampling prevents tiny seats crowding curved ends.
			var points: Array[Vector3] = []
			var lengths: Array[float] = [0.0]
			var circumference: float = 0.0
			for s in range(768+1):
				var p = _outline(rx+.42,rz+.42,TAU*s/768.0,y+.15)
				if s>0:
					circumference += p.distance_to(points[-1])
					lengths.append(circumference)
				points.append(p)
			var count: int = floori(circumference/d.seat_spacing)
			var cursor: int = 0
			for i in range(count):
				var distance: float = circumference*(i+.5)/count
				while cursor<767 and lengths[cursor+1]<distance: cursor+=1
				var f: float = (distance-lengths[cursor])/(lengths[cursor+1]-lengths[cursor])
				var at: Vector3 = points[cursor].lerp(points[cursor+1],f)
				var angle: float = TAU*(cursor+f)/768.0
				var sector: int = mini(d.sector_count-1,floori(angle/TAU*d.sector_count))
				var fraction: float = fposmod(angle/TAU*d.sector_count,1.0)
				if fraction < .033 or fraction > .967: continue # continuous radial aisles
				# Two real player tunnels below the middle of the side stands.
				if tier==0 and row<6 and absf(at.z)<3.8: continue
				var outward = Vector3(at.x/(rx*rx),0,at.z/(rz*rz)).normalized()
				var basis = Basis(Vector3.UP,atan2(outward.x,outward.z))
				transforms[sector].append(Transform3D(basis,at))
				var value: float = rng.randf_range(.78,1.08)
				# Controlled navy seating, subtle alternating blocks; no noisy rainbow.
				var tint = Color(value,value,value,1)
				tints[sector].append(tint)
				seat_total += 1
				if rng.randf() < d.crowd_density:
					crowd_transforms[sector].append(Transform3D(basis,at+Vector3(0,.03,-.05)))
					crowd_colors[sector].append([Color("8897ac"),Color("34435c"),Color("c1b7a3"),Color("587aaa")][rng.randi_range(0,3)])
					crowd_total += 1
		_mesh(group,"Terraces",concrete,"Concrete")
		for sec in range(d.sector_count):
			_instances(group,"Seats_%02d" % sec,seat,transforms[sec],tints[sec],"SeatBlue" if sec%6==0 else "SeatNavy",215.0)
			_instances(group,"Crowd_%02d" % sec,crowd,crowd_transforms[sec],crowd_colors[sec],"Crowd",170.0)
			var proxy = _mesh(group,"FarSeats_%02d" % sec,far_rows[sec],"SeatBlue" if sec%6==0 else "SeatNavy",false)
			proxy.visible=false
			proxy.set_meta("seat_proxy",true)
		var front_rx: float = hw+15+offset
		var front_rz: float = hl+16+offset
		# Balcony fascias and two-tier hospitality strips give a large enclosed arena.
		for s in range(segments):
			var a: float = TAU*s/segments
			var b: float = TAU*(s+1)/segments
			var p = _outline(front_rx,front_rz,a,base_y)
			var q = _outline(front_rx,front_rz,b,base_y)
			trim.quad(p-Vector3(0,.9,0),q-Vector3(0,.9,0),q,p)
			if tier>0:
				rail.rod(p+Vector3(0,.80,0),q+Vector3(0,.80,0),.025,4)
				if s%4==0: rail.rod(p,p+Vector3(0,.8,0),.025,4)
		# Half-height contrasting aisle steps, batched into one mesh.
		for sec in range(d.sector_count):
			var angle: float = TAU*sec/d.sector_count
			for r in range(rows*2):
				var at = _outline(front_rx+r*d.row_depth*.5,front_rz+r*d.row_depth*.5,angle,base_y+r*d.row_rise*.5-.025)
				var outward = Vector3(at.x/(front_rx*front_rx),0,at.z/(front_rz*front_rz)).normalized()
				stairs.box(Vector3(.82,.05,d.row_depth*.48),at,Basis(Vector3.UP,atan2(outward.x,outward.z)))
		offset += rows*d.row_depth+3.0
		base_y += rows*d.row_rise+2.25
	_mesh(root.get_node("Bowl"),"AisleSteps",stairs,"LinesWhite",false)
	_mesh(root.get_node("Bowl"),"BalconyRails",rail,"Metal",false)
	_mesh(root.get_node("Bowl"),"BalconyFascias",trim,"Board")
	# Outer shell, three concourse bands and structural columns all merged.
	var shell = Batch.new()
	var metal = Batch.new()
	var windows = Batch.new()
	var rx: float = hw+15+offset
	var rz: float = hl+16+offset
	for s in range(192):
		var a: float = TAU*s/192
		var b: float = TAU*(s+1)/192
		var p = _outline(rx,rz,a,0)
		var q = _outline(rx,rz,b,0)
		shell.quad(q,p,p+Vector3(0,base_y+2,0),q+Vector3(0,base_y+2,0))
		for y in [8.4,17.8,27.2]:
			var po = _outline(rx+.12,rz+.12,a,y)
			var qo = _outline(rx+.12,rz+.12,b,y)
			windows.quad(qo,po,po+Vector3(0,1.1,0),qo+Vector3(0,1.1,0))
		if s%4==0:
			metal.rod(p,p+Vector3(0,base_y+2,0),.23,6)
	_mesh(root.get_node("Bowl"),"OuterShell",shell,"Roof")
	_mesh(root.get_node("Bowl"),"ConcourseWindows",windows,"Glass")
	_mesh(root.get_node("Bowl"),"ExteriorColumns",metal,"Metal")
	var tunnels = Batch.new()
	for sx in [-1.0,1.0]:
		tunnels.box(Vector3(2.0,3.2,7.6),Vector3(sx*(hw+15.2),1.6,0))
	_mesh(root.get_node("Bowl"),"PlayerTunnelPortals",tunnels,"Board",false)

func _roof() -> void:
	var hw: float = d.pitch_width*.5
	var hl: float = d.pitch_length*.5
	var offset: float = 0.0
	var height: float = 1.2
	for rows in d.tier_rows:
		offset += rows*d.row_depth+3.0
		height += rows*d.row_rise+2.25
	height += 2.4
	var inner_x: float = hw+8.0
	var inner_z: float = hl+10.0
	var outer_x: float = hw+15.0+offset+1.8
	var outer_z: float = hl+16.0+offset+1.8
	var roof = Batch.new()
	var ribs = Batch.new()
	var lights = Batch.new()
	var edge = Batch.new()
	for s in range(192):
		var a: float = TAU*s/192
		var b: float = TAU*(s+1)/192
		var p = _outline(inner_x,inner_z,a,height)
		var q = _outline(inner_x,inner_z,b,height)
		var po = _outline(outer_x,outer_z,a,height+2.3)
		var qo = _outline(outer_x,outer_z,b,height+2.3)
		roof.quad(p,po,qo,q)
		edge.quad(p-Vector3(0,.8,0),q-Vector3(0,.8,0),q,p)
		if s%4==0:
			ribs.rod(p-Vector3(0,.45,0),po-Vector3(0,.45,0),.18,6)
			ribs.rod(p-Vector3(0,.9,0),po-Vector3(0,.10,0),.09,6)
			lights.rod(p-Vector3(0,.95,0),_outline(inner_x,inner_z,b+TAU/192,height-.95),.075,4)
		# Eight horizontal metal facade bands imply an airy modern silver shell.
		for band in range(8):
			var ba = _outline(outer_x-.8,outer_z-.8,a,height-1.0-band*1.05)
			var bb = _outline(outer_x-.8,outer_z-.8,b,height-1.0-band*1.05)
			ribs.quad(ba,bb,bb+Vector3(0,.22,0),ba+Vector3(0,.22,0))
	_mesh(root.get_node("Roof"),"Canopy",roof,"Roof")
	_mesh(root.get_node("Roof"),"RibsAndFacadeLouvers",ribs,"Metal")
	_mesh(root.get_node("Roof"),"InnerRingFascia",edge,"Board")
	_mesh(root.get_node("Roof"),"FloodlightStrips",lights,"Light",false)
	# Unlit screen geometry and neutral lettering, no real-world marks.
	var screens = Batch.new()
	for sz in [-1.0,1.0]:
		var z: float = sz*(hl+24.0)
		screens.box(Vector3(12,4,.28),Vector3(0,height-8,z))
		var label = Label3D.new()
		label.name = "NorthDisplay" if sz<0 else "SouthDisplay"
		label.text = "NORTH ARENA\n105 × 68   /   FOOTBALL"
		label.position = Vector3(0,height-8,z-sz*.16)
		label.rotation.y = 0 if sz<0 else PI
		label.font_size = 64
		label.pixel_size = .010
		label.outline_size = 0
		label.modulate = Color("c5dbe8")
		label.no_depth_test = false
		root.get_node("Roof").add_child(label)
	_mesh(root.get_node("Roof"),"DisplayHousings",screens,"Board")

func _perimeter() -> void:
	var hw: float = d.pitch_width*.5
	var hl: float = d.pitch_length*.5
	var boards = Batch.new()
	var panels = Batch.new()
	# Visual boards 6 m outside touchlines, 6.5 m behind goals; technical gaps.
	for sx in [-1.0,1.0]:
		for interval in [[-hl-5,-19.0],[19.0,hl+5]] if sx>0 else [[-hl-5,hl+5]]:
			boards.box(Vector3(.20,.85,interval[1]-interval[0]),Vector3(sx*(hw+6),.425,(interval[0]+interval[1])*.5))
			for z in range(ceili(interval[0]/8.0),floori(interval[1]/8.0)):
				panels.box(Vector3(.025,.48,6.2),Vector3(sx*(hw+5.88),.49,z*8.0+4))
	for sz in [-1.0,1.0]:
		boards.box(Vector3(d.pitch_width+12,.85,.2),Vector3(0,.425,sz*(hl+6.5)))
		for i in range(9):
			panels.box(Vector3(6.2,.48,.025),Vector3((i-4)*8.0,.49,sz*(hl+6.38)))
	_mesh(root.get_node("Perimeter"),"PitchsideBoards",boards,"Board")
	_mesh(root.get_node("Perimeter"),"NeutralBoardPanels",panels,"SeatBlue",false)
	var distance: float = d.perimeter_clearance
	for sx in [-1.0,1.0]:
		_solid_box(root.get_node("Perimeter"),"WestOuterStop" if sx<0 else "EastOuterStop",Vector3(.25,2.4,d.pitch_length+distance*2),Vector3(sx*(hw+distance),1.2,0),d.perimeter_collision)
	for sz in [-1.0,1.0]:
		_solid_box(root.get_node("Perimeter"),"NorthOuterStop" if sz<0 else "SouthOuterStop",Vector3(d.pitch_width+distance*2,2.4,.25),Vector3(0,1.2,sz*(hl+distance)),d.perimeter_collision)

func _anchors() -> void:
	var hw: float = d.pitch_width*.5
	var hl: float = d.pitch_length*.5
	var anchors = {"Center":Vector3.ZERO,"NorthGoalLine":Vector3(0,0,-hl),"SouthGoalLine":Vector3(0,0,hl),"NorthPenaltySpot":Vector3(0,0,-hl+d.penalty_distance),"SouthPenaltySpot":Vector3(0,0,hl-d.penalty_distance),"CornerNW":Vector3(-hw,0,-hl),"CornerNE":Vector3(hw,0,-hl),"CornerSW":Vector3(-hw,0,hl),"CornerSE":Vector3(hw,0,hl),"NorthGoalMouth":Vector3(0,d.goal_height*.5,-hl+d.line_width*.5),"SouthGoalMouth":Vector3(0,d.goal_height*.5,hl-d.line_width*.5),"WestTunnel":Vector3(-hw-15,0,0),"EastTunnel":Vector3(hw+15,0,0)}
	for name in anchors:
		var marker = Marker3D.new()
		marker.name = name
		marker.position = anchors[name]
		root.get_node("Anchors").add_child(marker)

func _net_point(panel: int, u: float, v: float, side: float, front: float, back: float) -> Vector3:
	var half: float = d.goal_width*.5
	var height: float = d.goal_height
	if panel==0:
		var x: float = lerpf(-half,half,u)
		var y: float = lerpf(.03,height,v)
		return Vector3(x,y,back-side*.075*sin(PI*u)*sin(PI*v))
	if panel==1:
		return Vector3(lerpf(-half,half,u),height-.045*sin(PI*u)*sin(PI*v),lerpf(front,back,v))
	var xsign: float = -1.0 if panel==2 else 1.0
	return Vector3(xsign*(half-.035*sin(PI*u)*sin(PI*v)),lerpf(.03,height,v),lerpf(front,back,u))

func _net_geometry(side: float, front: float, back: float, spacing: float, radius: float, sides: int) -> RefCounted:
	var net = Batch.new()
	for panel in range(4):
		var width: float = d.goal_width if panel<2 else absf(back-front)
		var height: float = absf(back-front) if panel==1 else d.goal_height-.03
		var columns: int = ceili(width/spacing)
		var rows: int = ceili(height/spacing)
		for x in range(columns+1):
			var u: float = float(x)/columns
			for y in range(rows):
				var a: Vector3 = _net_point(panel,u,float(y)/rows,side,front,back)
				var b: Vector3 = _net_point(panel,u,float(y+1)/rows,side,front,back)
				net.smooth_rod(a,b,radius,sides)
		for y in range(rows+1):
			var v: float = float(y)/rows
			for x in range(columns):
				var a: Vector3 = _net_point(panel,float(x)/columns,v,side,front,back)
				var b: Vector3 = _net_point(panel,float(x+1)/columns,v,side,front,back)
				net.smooth_rod(a,b,radius,sides)
	return net

func _seat_mid_mesh() -> ArrayMesh:
	var b = Batch.new()
	b.top_rect(-.22,.22,-.21,.21,.165)
	b.quad(Vector3(-.22,.15,.15),Vector3(-.22,.55,.20),Vector3(.22,.55,.20),Vector3(.22,.15,.15))
	b.quad(Vector3(-.22,.15,.22),Vector3(.22,.15,.22),Vector3(.22,.55,.27),Vector3(-.22,.55,.27))
	return b.mesh()

func _seat_far_mesh() -> ArrayMesh:
	var b = Batch.new()
	b.top_rect(-.22,.22,-.21,.21,.165)
	b.quad(Vector3(-.22,.15,.15),Vector3(-.22,.55,.20),Vector3(.22,.55,.20),Vector3(.22,.15,.15))
	return b.mesh()

func _bench_chair(seats: RefCounted, metal: RefCounted, at: Vector3) -> void:
	# Same footprint/capacity; tapered segmented back and independent armrests.
	seats.box(Vector3(.50,.09,.44),at)
	for i in range(5):
		var y0: float = .06+i*.12
		var y1: float = y0+.12
		var x0: float = .21+sin(float(i)/5.0*PI*.35)*.10
		var x1: float = .21+sin(float(i+1)/5.0*PI*.35)*.10
		var w0: float = .22-i*.007
		var w1: float = .22-(i+1)*.007
		var a = at+Vector3(x0,y0,-w0)
		var b = at+Vector3(x0,y0,w0)
		var c = at+Vector3(x1,y1,w1)
		var e = at+Vector3(x1,y1,-w1)
		seats.quad(b,a,e,c)
		seats.quad(a+Vector3(.05,0,0),b+Vector3(.05,0,0),c+Vector3(.05,0,0),e+Vector3(.05,0,0))
		seats.quad(a,a+Vector3(.05,0,0),e+Vector3(.05,0,0),e)
		seats.quad(b+Vector3(.05,0,0),b,c,c+Vector3(.05,0,0))
	metal.smooth_rod(at-Vector3(0,.48,0),at-Vector3(0,.05,0),.024,6)
	for zsign in [-1.0,1.0]:
		var a = at+Vector3(-.12,.09,zsign*.245)
		var b = at+Vector3(-.12,.30,zsign*.245)
		var c = at+Vector3(.20,.32,zsign*.245)
		metal.smooth_rod(a,b,.016,6)
		metal.smooth_rod(b,c,.016,6)

func _append_far_seat_row(batch: RefCounted, rx: float, rz: float, y: float, sector: int) -> void:
	# Continuous row profiles replace subpixel individual seats only at far detail.
	# Original radial aisle fractions remain clear; no textures or grass changes.
	var start: float = TAU*(sector+.033)/d.sector_count
	var end: float = TAU*(sector+.967)/d.sector_count
	for i in range(8):
		var a: float = lerpf(start,end,float(i)/8.0)
		var b: float = lerpf(start,end,float(i+1)/8.0)
		var p: Vector3 = _outline(rx+.42,rz+.42,a,y+.15)
		var q: Vector3 = _outline(rx+.42,rz+.42,b,y+.15)
		var np: Vector3 = Vector3(p.x/(rx*rx),0,p.z/(rz*rz)).normalized()
		var nq: Vector3 = Vector3(q.x/(rx*rx),0,q.z/(rz*rz)).normalized()
		# The seat pad and inward-facing back preserve tier/row depth cues.
		batch.quad(p-np*.21+Vector3.UP*.165,q-nq*.21+Vector3.UP*.165,q+nq*.21+Vector3.UP*.165,p+np*.21+Vector3.UP*.165)
		batch.quad(p+np*.145+Vector3.UP*.15,q+nq*.145+Vector3.UP*.15,q+nq*.185+Vector3.UP*.55,p+np*.185+Vector3.UP*.55)
