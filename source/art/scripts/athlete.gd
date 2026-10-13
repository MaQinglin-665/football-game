extends Node3D
# Reuses the project's original skeleton and clips without changing a single bone/rest/socket.
const Original=preload("res://art/assets/footballer.glb")
const OldBody=preload("res://art/scripts/baseline_body.gd")
var skeleton:Skeleton3D
var player:AnimationPlayer
var old_meshes:Array[MeshInstance3D]=[]
var skin:Skin
var team:Color
var jersey:int
var surfaces:Dictionary={}
var visual:Node3D

func collect(n:Node)->void:
 if n is Skeleton3D:skeleton=n
 if n is AnimationPlayer:player=n
 if n is MeshInstance3D:old_meshes.append(n)
 for ch in n.get_children():collect(ch)

func build(c:Color,num:int,before:bool)->void:
 team=c;jersey=num;visual=Original.instantiate();add_child(visual);collect(visual)
 skin=Skin.new()
 for i in skeleton.get_bone_count():skin.add_bind(i,skeleton.get_bone_global_rest(i).affine_inverse())
 if before:
  OldBody.build(skeleton)
  for m in old_meshes:
   if OldBody.meshes.has(str(m.name)):m.mesh=OldBody.meshes[str(m.name)];m.skin=OldBody.binding
   for s in m.mesh.get_surface_count():
    var mat=ShaderMaterial.new();mat.shader=load("res://art/assets/kit.gdshader");mat.set_shader_parameter("team",Color("628fb1") if num==7 else Color("c26961"));mat.set_shader_parameter("authored_rest",not str(m.name).begins_with("Boot"))
    var part=0
    if str(m.name).begins_with("RobotArm"):part=1
    elif str(m.name).begins_with("RobotLeg"):part=2
    elif str(m.name)=="Head":part=3
    elif str(m.name).begins_with("Boot"):part={"BootUpper":4,"BootSole":5,"BootStuds":6,"BootLaces":7,"BootAccent":8}.get(m.mesh.surface_get_material(s).resource_name,4)
    mat.set_shader_parameter("part",part);mat.set_shader_parameter("jersey_digits",load("res://art/assets/jersey_digits.png"));mat.set_shader_parameter("jersey_number",num);m.set_surface_override_material(s,mat)
 else:
  for m in old_meshes:
   if not str(m.name).begins_with("Boot"):m.visible=false
   else:
    for s in m.mesh.get_surface_count():
     var source=m.mesh.surface_get_material(s)
     var mat=StandardMaterial3D.new();mat.albedo_color=Color("14202e");mat.roughness=.39
     if "Sole" in source.resource_name:mat.albedo_color=Color("dcdcd1");mat.roughness=.69
     if "Stud" in source.resource_name:mat.albedo_color=Color("263442");mat.roughness=.5
     if "Laces" in source.resource_name:mat.albedo_color=Color("f1eee1");mat.roughness=.88
     if "Accent" in source.resource_name:mat.albedo_color=Color("c4f358");mat.roughness=.42
     m.set_surface_override_material(s,mat)
  make_body()
 for clip in ["Idle","Run"]:player.get_animation(clip).loop_mode=Animation.LOOP_LINEAR
 player.play("Idle")

func material(key:String)->Material:
 var m=ShaderMaterial.new();m.shader=load("res://art/scripts/fabric.gdshader")
 m.set_shader_parameter("fabric",load("res://art/assets/cotton_jersey_normal.png"));m.set_shader_parameter("digits",load("res://art/assets/jersey_digits.png"));m.set_shader_parameter("number",float(jersey))
 var c=team;var kind=0
 if key=="skin":c=Color("ac7658") if team.b>team.r else Color("d49c79");kind=1
 if key=="shorts":c=Color("15243d") if team.b>team.r else Color("f0eee5");kind=2
 if key=="trim":c=Color("efe9d7");kind=2
 if key=="sock":c=Color("ecebdc") if team.b>team.r else Color("d23040");kind=2
 m.set_shader_parameter("color",c);m.set_shader_parameter("kind",kind);return m

func emit(key:String,p:Vector3,n:Vector3,uv:Vector2,b1:String,b2:String,w:float)->void:
 if not surfaces.has(key):
  var s=SurfaceTool.new();s.begin(Mesh.PRIMITIVE_TRIANGLES);s.set_material(material(key));surfaces[key]=s
 var st:SurfaceTool=surfaces[key]
 st.set_normal(n);st.set_uv(uv);st.set_uv2(Vector2(p.x,p.z));st.set_color(Color(p.y*.5,0,0,1))
 st.set_bones(PackedInt32Array([skeleton.find_bone(b1),skeleton.find_bone(b2),0,0]));st.set_weights(PackedFloat32Array([1-w,w,0,0]));st.add_vertex(p)

# Profile rings provide anatomical shoulder/chest/pelvis/knee/calf silhouette.
# Each entry: y, x centre, z centre, halfwidth, halfdepth, lower-bone weight.
func loft(key:String,rings:Array,b1:String,b2:String,fold:float=0.,segments:int=40)->void:
 var ascending=true
 for j in rings.size()-1:
  if rings[j+1][0]<=rings[j][0]:ascending=false
 if ascending:
  var smooth:Array=[]
  for j in rings.size()-1:
   var a=rings[maxi(0,j-1)];var b=rings[j];var c=rings[j+1];var d=rings[mini(j+2,rings.size()-1)]
   for k in 3:
    var t=k/3.;var r:Array=[]
    for h in 6:
     var v=.5*((2.*b[h])+(-a[h]+c[h])*t+(2.*a[h]-5.*b[h]+4.*c[h]-d[h])*t*t+(-a[h]+3.*b[h]-3.*c[h]+d[h])*t*t*t)
     if h==3 or h==4:v=maxf(v,.001)
     if h==5:v=clampf(v,0.,1.)
     r.append(v)
    smooth.append(r)
  smooth.append(rings[-1]);rings=smooth
 var rows:Array=[]
 for j in rings.size():
  var r=rings[j];var prev=rings[maxi(j-1,0)];var next=rings[mini(j+1,rings.size()-1)]
  var row:Array=[]
  for i in segments+1:
   var a=TAU*i/segments;var f=fold*(sin(a*7.+r[0]*7.+sin(a*3.)*.7)*.65+sin(a*11.-r[0]*11.)*.35)*(1.+.9*exp(-pow((r[0]-1.09)/.09,2.)))
   var p=Vector3(r[1]+cos(a)*(r[3]+f),r[0],r[2]+sin(a)*(r[4]+f))
   var slope=((next[3]-prev[3])*cos(a)*cos(a)+(next[4]-prev[4])*sin(a)*sin(a))/maxf(absf(next[0]-prev[0]),.002)
   var n=Vector3(cos(a),-slope,sin(a)).normalized()
   row.append([p,n,Vector2(float(i)/segments,r[0]*2.),r[5]])
  rows.append(row)
 # Surface normals include elliptical radii, limb offsets and real cloth folds.
 for j in rows.size():
  for i in segments+1:
   var left=(i+segments-1)%segments;var right=(i+1)%segments
   var around:Vector3=rows[j][right][0]-rows[j][left][0]
   var along:Vector3=rows[mini(j+1,rows.size()-1)][i][0]-rows[maxi(j-1,0)][i][0]
   var normal=along.cross(around).normalized()
   if normal.length_squared()>.5:rows[j][i][1]=normal
 for j in rows.size()-1:
  for i in segments:
   for v in [rows[j][i],rows[j][i+1],rows[j+1][i],rows[j][i+1],rows[j+1][i+1],rows[j+1][i]]:emit(key,v[0],v[1],v[2],b1,b2,v[3])

func continuous_jersey()->void:
 var data=JSON.parse_string(FileAccess.get_file_as_string("res://art/assets/jersey_shell.json"))
 for face in data.faces:
  for i in face:
   var a=data.vertices[i];var v=Vector3(a[0],a[1],a[2]);var b=data.normals[i];var n=Vector3(b[0],b[1],b[2])
   var b1="hips";var b2="chest";var w=smoothstep(1.06,1.39,v.y)
   if absf(v.x)>.16 and v.y>1.18:
    b1="chest";b2="upper_arm."+("L" if v.x<0 else "R");w=smoothstep(.17,.255,absf(v.x))
   emit("jersey",v,n,Vector2(atan2(v.z,v.x)/TAU+.5,v.y*2.),b1,b2,w)

func anatomical_limbs()->void:
 var data=JSON.parse_string(FileAccess.get_file_as_string("res://art/assets/anatomy.json"))
 for face in data.faces:
  for i in face:
   var a=data.vertices[i];var v=Vector3(a[0],a[1],a[2]);var b=data.normals[i];var n=Vector3(b[0],b[1],b[2]);var side="L" if v.x<0 else "R"
   var b1="thigh."+side;var b2="shin."+side;var w=1.-smoothstep(.46,.60,v.y)
   if data.parts[i]=="arm":
    if v.y<.96:b1="forearm."+side;b2="hand."+side;w=1.-smoothstep(.85,.95,v.y)
    else:b1="upper_arm."+side;b2="forearm."+side;w=1.-smoothstep(1.08,1.17,v.y)
   emit("skin",v,n,Vector2(v.x*3.,v.y*3.),b1,b2,w)

func make_body()->void:
 continuous_jersey()
 anatomical_limbs()
 # Independent jersey hem, shaped chest and open neckline. No giant capsule torso.
 var torso:Array=[]
 for r in [[1.02,.176,.115],[1.028,.181,.118],[1.045,.179,.117],[1.08,.171,.112],[1.13,.165,.109],[1.19,.169,.115],[1.25,.182,.122],[1.33,.206,.126],[1.40,.228,.111],[1.43,.233,.102],[1.46,.205,.091],[1.49,.141,.069],[1.512,.071,.057],[1.519,.064,.053]]:
  torso.append([r[0],0.,0.,r[1],r[2],smoothstep(1.06,1.39,r[0])])
 loft("trim",[[1.505,0.,0.,.072,.059,1.],[1.522,0.,0.,.071,.058,1.],[1.523,0.,0.,.061,.049,1.],[1.505,0.,0.,.060,.048,1.]],"hips","chest")
 loft("skin",[[1.48,0.,0.,.048,.044,0.],[1.55,0.,0.,.044,.044,.7],[1.59,0.,-.008,.045,.046,1.]],"neck","head")
 # Featureless but shaped jaw, cranium and chin. Deliberately no eyes/nose/mouth.
 var head:Array=[]
 for r in [[1.54,.031,.035,-.010],[1.56,.051,.050,-.012],[1.59,.072,.069,-.008],[1.63,.087,.086,0.],[1.69,.094,.091,.003],[1.74,.081,.080,.002],[1.78,.051,.054,.001],[1.795,.002,.002,0.]]:head.append([r[0],0.,r[3],r[1],r[2],0.])
 loft("skin",head,"head","head")
 loft("shorts",[[.89,0.,.007,.181,.105,0.],[.98,0.,0.,.181,.112,0.],[1.038,0.,0.,.175,.110,0.]],"hips","hips",.002)
 for side in ["L","R"]:
  var signx=-1. if side=="L" else 1.
  var upper="upper_arm."+side;var lower="forearm."+side;var hand="hand."+side;var thigh="thigh."+side;var shin="shin."+side
  var x=.145*signx
  loft("shorts",[[.725,x,0.,.095,.102,1.],[.733,x,0.,.099,.106,1.],[.75,x,0.,.100,.107,1.],[.80,x,0.,.102,.11,.95],[.89,x*.85,.003,.106,.114,.65],[1.018,x*.65,0.,.093,.112,.12]],"hips",thigh,.005)
  loft("trim",[[.731,x,0.,.101,.108,1.],[.744,x,0.,.101,.108,1.]],"hips",thigh)
  loft("sock",[[.10,x,0.,.036,.040,1.],[.18,x,-.005,.041,.045,1.],[.28,x,-.012,.056,.066,1.],[.39,x,-.025,.062,.068,1.],[.438,x,-.030,.055,.061,1.],[.447,x,-.031,.058,.063,1.],[.458,x,-.031,.056,.061,1.],[.459,x,-.031,.050,.055,1.]],thigh,shin)
  loft("jersey",[[.420,x,-.028,.059,.065,1.],[.432,x,-.030,.058,.064,1.]],thigh,shin)
  # Blended shoulder yoke bridges the animated upper arm to chest, beneath the sleeve rim.
  loft("trim",[[1.256,.310*signx,0.,.080,.075,0.],[1.271,.310*signx,0.,.080,.075,0.],[1.273,.310*signx,0.,.070,.065,0.]],upper,upper)
 for key in surfaces:
  var st:SurfaceTool=surfaces[key];st.generate_tangents();var m=MeshInstance3D.new();m.name="Authored_"+key;m.mesh=st.commit();m.skin=skin;skeleton.add_child(m);m.skeleton=NodePath("..");m.extra_cull_margin=1.
