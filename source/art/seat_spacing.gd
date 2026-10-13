extends RefCounted
# The original superellipse used angular aisle widths; near the axes this left
# gaps several metres wider than the stairs. Fill those gaps, keeping a 1.3m aisle.
static func repair(stadium:Node3D)->int:
 var rows:Dictionary={};var sources:Array=[];var contents:Array=[];var extras:Array=[]
 for node in stadium.find_children("Seats_*","MultiMeshInstance3D",true,false):
  var index:int=sources.size();sources.append(node);contents.append([]);extras.append([])
  for i in node.multimesh.instance_count:
   var t:Transform3D=node.multimesh.get_instance_transform(i)
   var c:Color=node.multimesh.get_instance_color(i)
   contents[index].append([t,c])
   var key:int=roundi(t.origin.y*1000)
   if not rows.has(key):rows[key]=[]
   rows[key].append([t,index])
 var added:int=0
 for row in rows.values():
  row.sort_custom(func(a,b):return atan2(a[0].origin.z,a[0].origin.x)<atan2(b[0].origin.z,b[0].origin.x))
  for i in row.size():
   var a:Transform3D=row[i][0];var b:Transform3D=row[(i+1)%row.size()][0]
   var length:float=a.origin.distance_to(b.origin)
   if length<2.3 or length>24.:continue
   var middle:Vector3=(a.origin+b.origin)*.5
   if middle.y<4.4 and absf(middle.z)<4.5:continue
   var steps:int=floori(length/.54)
   for j in range(1,steps):
    var distance:float=length*j/steps
    if absf(distance-length*.5)<.65:continue
    var t:Transform3D=a;t.origin=a.origin.lerp(b.origin,float(j)/steps)
    var source_index:int=row[i][1] if j<steps/2 else row[(i+1)%row.size()][1]
    extras[source_index].append([t,Color(.88,.88,.88,1)]);added+=1
 for index in sources.size():
  if extras[index].is_empty():continue
  contents[index].append_array(extras[index])
  var previous:MultiMesh=sources[index].multimesh
  var mm=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.use_colors=true;mm.mesh=previous.mesh;mm.instance_count=contents[index].size()
  var transforms:Array=[]
  for i in contents[index].size():
   mm.set_instance_transform(i,contents[index][i][0]);mm.set_instance_color(i,contents[index][i][1]);transforms.append(contents[index][i][0])
  sources[index].multimesh=mm;sources[index].set_meta("crowd_seat_transforms",transforms)
 print("AISLE_SPACING_REPAIR added_seats=",added)
 return added
