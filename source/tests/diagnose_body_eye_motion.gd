extends SceneTree
var game: Node
var rows: Array[Dictionary] = []
var held: Array[int] = []
func _initialize() -> void: run.call_deferred()
func key(code: int, pressed: bool) -> void:
	var event:=InputEventKey.new();event.physical_keycode=code;event.keycode=code;event.pressed=pressed
	Input.parse_input_event(event);Input.flush_buffered_events()
func inputs(keys: Array) -> void:
	for code in held:
		if not keys.has(code): key(code,false)
	for code in keys:
		if not held.has(code): key(code,true)
	held.assign(keys)
func skin_mesh(node: MeshInstance3D, sk: Skeleton3D) -> Array:
	var transforms: Array=[]
	for bind in node.skin.get_bind_count():
		var name:=String(node.skin.get_bind_name(bind))
		var bone_id:=sk.find_bone(name) if name!="" else node.skin.get_bind_bone(bind)
		transforms.append(sk.global_transform*sk.get_bone_global_pose(bone_id)*node.skin.get_bind_pose(bind))
	var a: Array=node.mesh.surface_get_arrays(0)
	var points:=PackedVector3Array();var normals:=PackedVector3Array()
	for v in a[Mesh.ARRAY_VERTEX].size():
		var p:=Vector3.ZERO;var n:=Vector3.ZERO
		for slot in 4:
			var k: int=v*4+slot;var w: float=a[Mesh.ARRAY_WEIGHTS][k]
			if w<=0:continue
			var tr: Transform3D=transforms[a[Mesh.ARRAY_BONES][k]]
			p+=(tr*(a[Mesh.ARRAY_VERTEX][v] as Vector3))*w
			n+=(tr.basis*(a[Mesh.ARRAY_NORMAL][v] as Vector3))*w
		points.append(p);normals.append(n.normalized())
	return [points,normals,a[Mesh.ARRAY_INDEX]]
func body_hit(geometry: Array, origin: Vector3, target: Vector3) -> bool:
	var p: PackedVector3Array=geometry[0];var n: PackedVector3Array=geometry[1];var indices: PackedInt32Array=geometry[2]
	var ray:=target-origin
	for t in range(0,indices.size(),3):
		var a:=indices[t];var b:=indices[t+1];var c:=indices[t+2]
		if (n[a]+n[b]+n[c]).dot(origin-(p[a]+p[b]+p[c])/3.0)<=0:continue
		var hit: Variant=Geometry3D.ray_intersects_triangle(origin,ray.normalized(),p[a],p[b],p[c])
		if hit!=null:
			var distance:=origin.distance_to(hit as Vector3)
			if distance>=.05 and distance<ray.length()-.11:return true
	return false
func probe(tag: String) -> void:
	var player=game.player
	var sk: Skeleton3D=player.avatar.skeleton
	var body: MeshInstance3D
	for node in player.avatar.mesh_nodes:
		if String(node.name)=="BodyCore":body=node
	var head_id:=sk.find_bone("head")
	assert(head_id>=0)
	var head_world: Vector3=(sk.global_transform*sk.get_bone_global_pose(head_id)).origin
	var geometry:=skin_mesh(body,sk)
	var candidates: Array=[]
	var cb: Basis=player.camera.global_basis
	for mode in ["fixed_height_front011","head_front011","head_front020","head_front028","head_height_front011"]:
		var eye: Vector3=player.global_position+Vector3.UP*1.60+player.avatar.visual.global_basis*Vector3(0,0,-.11)
		if mode.begins_with("head_"):
			eye=head_world+player.avatar.visual.global_basis*Vector3(0,0,-(.20 if mode=="head_front020" else .28 if mode=="head_front028" else .11))
			if mode=="head_height_front011":eye.y=player.global_position.y+1.60
		var local: Vector3=cb.inverse()*(game.ball.global_position-eye)
		var in_view:=local.z<0 and absf(local.y)<=-local.z*tan(deg_to_rad(48)) and absf(local.x)<=-local.z*tan(deg_to_rad(48))*1280.0/720.0
		candidates.append({"mode":mode,"eye":eye,"blocked":body_hit(geometry,eye,game.ball.global_position),"in_view":in_view,"ball_view_relative":local})
	rows.append({"stage":tag,"frame":Engine.get_physics_frames(),"head_relative":player.to_local(head_world),"ball_relative":player.to_local(game.ball.global_position),"speed":Vector2(player.velocity.x,player.velocity.z).length(),"owned":game.ball.carrier==player,"candidates":candidates})
func run() -> void:
	game=load("res://scenes/match.tscn").instantiate();game.test_mode=true;root.add_child(game)
	game.ai_enabled=false;game.services.rules.state=game.Rules.State.LIVE;game.services.rules.restart.clear();game.set_phase(game.Phase.PLAY)
	game.services.configuration.half_seconds=600
	game.input_bridge.focused=true;game.sync_input_context()
	game.player.position=Vector3(0,.002,8);game.player.velocity=Vector3.ZERO;game.player.reset_view(0)
	game.ball.clear_control();game.ball.set_held(false);game.ball.position=Vector3(0,.113,7.42);game.ball.previous_position=game.ball.position;game.ball.velocity=Vector3.ZERO;game.ball.spin_rads=Vector3.ZERO;game.ball.pickup_block=0;game.ball.touch_timer=0;game.ball.control_mode="LOOSE"
	for i in game.agents.size():
		var agent=game.agents[i];agent.position=Vector3(-28 if i%2 else 28,.002,-43+4.2*i);agent.velocity=Vector3.ZERO;agent.target=agent.position;agent.refresh_pose(0);agent.pose_updates_enabled=false
	key(KEY_SPACE,true);await physics_frame;key(KEY_SPACE,false)
	for i in 45:await physics_frame
	game.player.head.rotation.x=deg_to_rad(-60.0);game.player.head.rot.x=deg_to_rad(-60.0)
	probe("idle")
	for part in [{"tag":"noShift","keys":[KEY_W],"ticks":144},{"tag":"Shift","keys":[KEY_W,KEY_SHIFT],"ticks":144},{"tag":"Shift_cut","keys":[KEY_W,KEY_D,KEY_SHIFT],"ticks":120},{"tag":"stop","keys":[],"ticks":84}]:
		inputs(part.keys)
		for i in part.ticks:
			await physics_frame
			if i%12==11:probe(part.tag)
	inputs([])
	var bones: Array=[]
	for id in game.player.avatar.skeleton.get_bone_count():bones.append(game.player.avatar.skeleton.get_bone_name(id))
	var report:={"rows":rows,"bones":bones,"GPU_used":false,"scope":"Actual current match same RECEIVE then realW/Shift/cut, no further ball/root fixture. Fixed-fps120 CPU geometric head/BodyCore ray diagnostics only. Camera candidates are computed only; no production view or physics writes after down-look."}
	FileAccess.open(ProjectSettings.globalize_path("res://../verification/MOTION_EYE_GEOMETRY_DIAGNOSTIC.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	game.shutdown_audio();game.free();print("MOTION_EYE_DIAGNOSTIC_DONE rows=",rows.size());quit(0)
