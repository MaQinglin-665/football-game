extends SceneTree
const OldHost:=preload("res://tests/baseline_host.gd")
const NewHost:=preload("res://scripts/integration_character_pose.gd")

func _initialize()->void:run.call_deferred()

func find_body(avatar)->MeshInstance3D:
	for node in avatar.mesh_nodes:
		if String(node.name)=="BodyCore":return node
	return null

func visibility(avatar)->Dictionary:
	var out:={"body":false,"head":false,"arms":0,"body_triangles":0,"body_surfaces":0,"color":"","opaque":false,"cull_back":false}
	for node in avatar.mesh_nodes:
		if String(node.name)=="Head":out.head=node.visible
		if String(node.name).begins_with("RobotArm") and node.visible:out.arms+=1
		if String(node.name)!="BodyCore":continue
		out.body=node.visible;out.body_surfaces=node.mesh.get_surface_count()
		for s in node.mesh.get_surface_count():out.body_triangles+=int(node.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX].size()/3)
		var mat:StandardMaterial3D=node.get_active_material(0)
		out.color=mat.albedo_color.to_html();out.opaque=mat.transparency==BaseMaterial3D.TRANSPARENCY_DISABLED and mat.albedo_color.a==1
		out.cull_back=mat.cull_mode==BaseMaterial3D.CULL_BACK
	return out

func skin_mesh(node:MeshInstance3D,sk:Skeleton3D)->Array:
	var transforms:Array=[]
	for bind in node.skin.get_bind_count():
		var name:=String(node.skin.get_bind_name(bind))
		var bone_id:=sk.find_bone(name) if name!="" else node.skin.get_bind_bone(bind)
		transforms.append(sk.global_transform*sk.get_bone_global_pose(bone_id)*node.skin.get_bind_pose(bind))
	var a:Array=node.mesh.surface_get_arrays(0)
	var points:=PackedVector3Array();var normals:=PackedVector3Array()
	for v in a[Mesh.ARRAY_VERTEX].size():
		var p:=Vector3.ZERO;var n:=Vector3.ZERO
		for slot in 4:
			var k:int=v*4+slot;var w:float=a[Mesh.ARRAY_WEIGHTS][k]
			if w<=0:continue
			var tr:Transform3D=transforms[a[Mesh.ARRAY_BONES][k]]
			p+=(tr*(a[Mesh.ARRAY_VERTEX][v] as Vector3))*w
			n+=(tr.basis*(a[Mesh.ARRAY_NORMAL][v] as Vector3))*w
		points.append(p);normals.append(n.normalized())
	return [points,normals,a[Mesh.ARRAY_INDEX]]

func body_hit(geometry:Array,origin:Vector3,direction:Vector3,max_distance:float=INF)->float:
	var best:=INF;var p:PackedVector3Array=geometry[0];var n:PackedVector3Array=geometry[1];var indices:PackedInt32Array=geometry[2]
	for t in range(0,indices.size(),3):
		var a:=indices[t];var b:=indices[t+1];var c:=indices[t+2]
		# Cull inner/back faces using the imported outward vertex normals.
		if (n[a]+n[b]+n[c]).dot(origin-(p[a]+p[b]+p[c])/3.0)<=0:continue
		var hit:Variant=Geometry3D.ray_intersects_triangle(origin,direction,p[a],p[b],p[c])
		if hit==null:continue
		var distance:=origin.distance_to(hit as Vector3)
		if distance>=.05 and distance<max_distance:best=minf(best,distance)
	return best

func camera_probe(avatar)->Array:
	var geometry:=skin_mesh(find_body(avatar),avatar.skeleton);var rows:=[]
	for origin_kind in ["released_rotating_rear_offset","proposed_fixed_front_eye"]:
		for pitch in [-75.0,-60.0,-42.0,-39.0,0.0,45.0,75.0]:
			var cb:=Basis.from_euler(Vector3(deg_to_rad(pitch),0,0))
			var eye:=Vector3(0,1.60,0)+(cb*Vector3(0,0,.16) if origin_kind=="released_rotating_rear_offset" else Vector3(0,0,-.11))
			var forward_hit:=body_hit(geometry,eye,-cb.z)
			var balls:=[]
			for z in [-.04,-.28,-.40,-.65]:
				var ball:=Vector3(0,.11,z);var ray:Vector3=ball-eye
				var local:Vector3=cb.inverse()*ray
				var visible_angle:bool=local.z<0 and absf(local.y)<=-local.z*tan(deg_to_rad(48.0))
				var hit:=body_hit(geometry,eye,ray.normalized(),ray.length()-.11)
				balls.append({"ball_z":z,"in_vertical_fov":visible_angle,"blocked_by_body":hit<INF,"body_hit_m":hit if hit<INF else -1.0})
			rows.append({"origin":origin_kind,"pitch_deg":pitch,"camera_world":[eye.x,eye.y,eye.z],"center_ray_body_hit_m":forward_hit if forward_hit<INF else -1.0,"balls":balls})
	return rows

func run()->void:
	var old=OldHost.new();var new=NewHost.new();root.add_child(old);root.add_child(new)
	var checks:=[];var passed:=true
	for team in 3:
		new.setup(team,1,true);var fp:=visibility(new)
		var color:String=["1d5fffff","ffdd00ff","ef2532ff"][team]
		var fp_ok:bool=fp.body and not fp.head and fp.arms==2 and fp.body_triangles==672 and fp.body_surfaces==1 and fp.color==color and fp.opaque and fp.cull_back
		checks.append({"case":"FP_team_"+str(team),"passed":fp_ok,"details":fp});passed=passed and fp_ok
		new.setup(team,1,false);var tp:=visibility(new)
		var tp_ok:bool=tp.body and tp.head and tp.arms==2 and tp.body_triangles==768 and tp.body_surfaces==3 and tp.color==color
		checks.append({"case":"TP_restore_team_"+str(team),"passed":tp_ok,"details":tp});passed=passed and tp_ok
	old.setup(0,1,true);new.setup(0,1,true)
	var position_error:=0.0;var basis_error:=0.0;var contact_error:=0.0;var valid_equal:=true
	var body_mesh_id:int=find_body(new).mesh.get_instance_id()
	for tick in 360:
		var mode:="idle" if tick<60 else "walk" if tick<150 else "run"
		var yaw:=deg_to_rad(60.0*sin(tick/45.0)) if tick>=240 else 0.0
		var forward:=Vector3(-sin(yaw),0,-cos(yaw));var velocity:=forward*(0.0 if mode=="idle" else 1.4 if mode=="walk" else 4.4)
		var state:={"velocity":velocity,"accel":Vector3.ZERO,"forward":forward,"grounded":true,"ground_y":0.0,"locomotion":mode,"pose_tick":tick}
		for a in [old,new]:a.position+=velocity/120.0;a.update_pose(1.0/120,state)
		for i in 32:
			var a:Transform3D=old.skeleton.get_bone_global_pose(i);var b:Transform3D=new.skeleton.get_bone_global_pose(i)
			position_error=maxf(position_error,a.origin.distance_to(b.origin))
			for axis in 3:basis_error=maxf(basis_error,a.basis[axis].distance_to(b.basis[axis]))
		for side in [-1,1]:
			for surface in ["INSIDE","OUTSIDE","INSTEP","SOLE","TOE"]:
				var a:Dictionary=old.get_foot_contact(side,surface);var b:Dictionary=new.get_foot_contact(side,surface)
				contact_error=maxf(contact_error,(a.point as Vector3).distance_to(b.point));valid_equal=valid_equal and a.valid==b.valid
		assert(find_body(new).mesh.get_instance_id()==body_mesh_id)
	var pose_ok:bool=position_error==0 and basis_error==0 and contact_error==0 and valid_equal
	checks.append({"case":"360_idle_walk_run_turn_ticks","passed":pose_ok,"all_bones":32,"socket_checks":3600,"position_error_m":position_error,"basis_error":basis_error,"socket_error_m":contact_error,"valid_equal":valid_equal,"no_runtime_mesh_rebuild":true})
	passed=passed and pose_ok
	new.position=Vector3.ZERO;new.visual.rotation=Vector3.ZERO;new.skeleton.reset_bone_poses();new.skeleton.force_update_all_bone_transforms()
	var probes:=camera_probe(new)
	var report:={"passed":passed,"GPU_used":false,"checks":checks,"camera_geometry_probe":probes,"native_render_pending":true,
		"scope":"Exact applied visibility patch; existing geometry and rig unchanged. Ray tests are geometric diagnostics, not native framebuffer/performance acceptance."}
	var f:=FileAccess.open(ProjectSettings.globalize_path("res://").path_join("../verification/check_body_01.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify(report,"\t"));f.close();old.free();new.free();print("FP_BODY_01_HEADLESS_COMPLETE passed="+str(passed));quit(0 if passed else 1)
