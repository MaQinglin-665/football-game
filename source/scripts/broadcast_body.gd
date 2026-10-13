extends RefCounted
# Original smooth visual mesh. Reuses the unchanged skeleton, animation and collision rig.
static var meshes:Dictionary={}
static var binding:Skin
static func apply(avatar,first_person:bool)->void:
 if first_person:return # Preserve authored first-person visibility and boot sockets.
 var sk:Skeleton3D=avatar.skeleton
 if meshes.is_empty():build(sk)
 for node in avatar.mesh_nodes:
  var key:String=String(node.name)
  if meshes.has(key):node.mesh=meshes[key];node.skin=binding
 avatar.set_color_preset(avatar._preset)
static func build(sk:Skeleton3D)->void:
 binding=Skin.new()
 for i in sk.get_bone_count():binding.add_bind(i,sk.get_bone_global_rest(i).affine_inverse())
 meshes["BodyCore"]=torso(sk)
 meshes["Head"]=head(sk)
 for suffix in ["L","R"]:
  meshes["RobotArm_"+suffix]=limb(sk,suffix,true)
  meshes["RobotLeg_"+suffix]=limb(sk,suffix,false)
static func start(name:String)->SurfaceTool:
 var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
 var mat:=StandardMaterial3D.new();mat.resource_name="Broadcast"+name;st.set_material(mat);return st
static func vertex(st:SurfaceTool,p:Vector3,n:Vector3,bones:PackedInt32Array,weights:PackedFloat32Array)->void:
 st.set_normal(n);st.set_uv(Vector2(p.x*3,p.y*3));st.set_uv2(Vector2(p.x,p.z));st.set_color(Color(p.y*.5,0,0,1))
 st.set_bones(bones);st.set_weights(weights);st.add_vertex(p)
static func stitch(st:SurfaceTool,rows:Array)->void:
 for j in range(rows.size()-1):
  for i in range(rows[j].size()):
   var k:int=(i+1)%rows[j].size()
   for cell in [rows[j][i],rows[j+1][i],rows[j][k],rows[j][k],rows[j+1][i],rows[j+1][k]]:
    vertex(st,cell.p,cell.n,cell.b,cell.w)
static func torso(sk:Skeleton3D)->ArrayMesh:
 var st:=start("Kit");var rows:Array=[]
 var hips:int=sk.find_bone("hips");var chest:int=sk.find_bone("chest")
 for spec in [[.985,.162,.094],[1.03,.176,.106],[1.12,.158,.101],[1.21,.171,.111],[1.32,.197,.117],[1.41,.221,.106],[1.46,.202,.092],[1.49,.143,.075],[1.52,.054,.053],[1.545,.048,.048]]:
  var row:Array=[];var y:float=spec[0];var w:float=smoothstep(1.07,1.40,y)
  for i in 24:
   var a:float=TAU*i/24.0;var fold:float=sin(a*6+y*23)*.0025*(1.0-smoothstep(1.10,1.49,y))
   var v:=Vector3(cos(a)*(float(spec[1])+fold),y,sin(a)*(float(spec[2])+fold))
   row.append({"p":v,"n":Vector3(cos(a),.06,sin(a)).normalized(),"b":PackedInt32Array([hips,chest,0,0]),"w":PackedFloat32Array([1-w,w,0,0])})
  rows.append(row)
 rows.reverse() # Godot front faces are clockwise; expose the outward torso surface.
 stitch(st,rows);return st.commit()
static func head(sk:Skeleton3D)->ArrayMesh:
 var st:=start("Skin");var rows:Array=[];var bone:int=sk.find_bone("head")
 for j in range(17):
  var a:float=PI*(1.0-j/16.0);var row:Array=[]
  for i in 24:
   var t:float=TAU*i/24.0;var n:=Vector3(sin(a)*cos(t),cos(a),sin(a)*sin(t))
   row.append({"p":Vector3(n.x*.096,1.654+n.y*.139,n.z*.092-.006),"n":n,"b":PackedInt32Array([bone,0,0,0]),"w":PackedFloat32Array([1,0,0,0])})
  rows.append(row)
 rows.reverse()
 stitch(st,rows);return st.commit()
static func limb(sk:Skeleton3D,suffix:String,arm:bool)->ArrayMesh:
 var upper:int=sk.find_bone(("upper_arm." if arm else "thigh.")+suffix)
 var lower:int=sk.find_bone(("forearm." if arm else "shin.")+suffix)
 var end:int=sk.find_bone(("hand." if arm else "foot.")+suffix)
 var a:Vector3=sk.get_bone_global_rest(upper).origin;var b:Vector3=sk.get_bone_global_rest(lower).origin;var c:Vector3=sk.get_bone_global_rest(end).origin
 var st:=start("Limb");var rows:Array=[]
 for j in range(17):
  var t:float=j/16.0;var axis:Vector3=(b-a).normalized() if t<.5 else (c-b).normalized()
  var center:Vector3=a.lerp(b,t*2) if t<.5 else b.lerp(c,(t-.5)*2)
  if j==0:center-=axis*(.065 if arm else .12)
  if j==16:center+=axis*(.13 if arm else .025)
  var radius:float=lerpf(.061,.039,smoothstep(0,.50,t)) if arm else lerpf(.088,.055,smoothstep(0,.5,t))
  if t>.5:radius=lerpf(.046,.027,smoothstep(.60,1,t)) if arm else lerpf(.064,.041,smoothstep(.65,1,t))
  if arm and j==15:center+=axis*.075;radius=.035
  if j==16:radius=.001
  var x:Vector3=axis.cross(Vector3.FORWARD).normalized();var z:Vector3=x.cross(axis).normalized()
  var weight:float=smoothstep(.36,.64,t);var row:Array=[]
  for i in 16:
   var angle:float=TAU*i/16.0;var n:Vector3=x*cos(angle)+z*sin(angle)
   row.append({"p":center+n*radius,"n":n,"b":PackedInt32Array([upper,lower,0,0]),"w":PackedFloat32Array([1-weight,weight,0,0])})
  rows.append(row)
 var cap:Array=[];var center:=Vector3.ZERO
 for cell in rows[0]:center+=cell.p
 center/=rows[0].size()
 for cell in rows[0]:
  var tip:Dictionary=cell.duplicate();tip.p=center;tip.n=(a-b).normalized();cap.append(tip)
 rows.push_front(cap)
 rows.reverse()
 stitch(st,rows);return st.commit()

