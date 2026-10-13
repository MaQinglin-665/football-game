extends RefCounted
# Original clothed seated bodies. Feet are on the terrace, hips on a 0.445m seat.
# UV.x stores material part; UV.y stores body height. All variants face local -Z.
var st:SurfaceTool
var segments:int
var standing:bool=false
var distant:bool=false
func vertex(p:Vector3,n:Vector3,part:float)->void:
 if standing and (part==0. or part==1. or part==3. or part==4.):p.y+=.38
 st.set_normal(n);st.set_uv(Vector2(part,p.y));st.add_vertex(p)
func quad(p:Array,n:Array,part:float)->void:
 for i in [0,1,2,0,2,3]:vertex(p[i],n[i],part)
func ellipsoid(at:Vector3,r:Vector3,part:float,segs:int,rows:int)->void:
 for j in rows:
  for i in segs:
   var p:Array=[];var n:Array=[]
   for v in [Vector2(j,i),Vector2(j+1,i),Vector2(j+1,i+1),Vector2(j,i+1)]:
    var theta:float=PI*v.x/rows;var phi:float=TAU*v.y/segs
    var unit=Vector3(sin(theta)*cos(phi),cos(theta),sin(theta)*sin(phi))
    p.append(at+unit*r);n.append((unit/r).normalized())
   quad(p,n,part)
func limb(a:Vector3,b:Vector3,ra:float,rb:float,part:float)->void:
 var axis:Vector3=(b-a).normalized();var side:Vector3=axis.cross(Vector3.FORWARD).normalized()
 if side.length()<.5:side=axis.cross(Vector3.RIGHT).normalized()
 var up:Vector3=axis.cross(side).normalized()
 for i in segments:
  var u:Vector3=side*cos(TAU*i/segments)+up*sin(TAU*i/segments)
  var v:Vector3=side*cos(TAU*(i+1)/segments)+up*sin(TAU*(i+1)/segments)
  var nu:Vector3=(u+axis*(ra-rb)/a.distance_to(b)).normalized()
  var nv:Vector3=(v+axis*(ra-rb)/a.distance_to(b)).normalized()
  quad([a+u*ra,b+u*rb,b+v*rb,a+v*ra],[nu,nu,nv,nv],part)
func torso(lean:float,width:float)->void:
 # Hem, waist, ribs, chest, sloping shoulder and neckline, not a single oval.
 var rings:Array=[Vector4(.43,.157,.112,-.006),Vector4(.49,.166,.117,-.007),Vector4(.64,.145,.105,lean*.35),Vector4(.82,.182,.119,lean*.75),Vector4(.94,.207,.106,lean),Vector4(1.015,.115,.078,lean),Vector4(1.033,.059,.053,lean)]
 if distant:rings=[rings[0],rings[2],rings[4],rings[6]]
 for j in rings.size()-1:
  for i in segments:
   var ps:Array=[];var ns:Array=[]
   for pair in [[j,i],[j+1,i],[j+1,i+1],[j,i+1]]:
    var ring:Vector4=rings[pair[0]];var a:float=TAU*pair[1]/segments
    # Low amplitude folds change the silhouette; no noisy fabric normal map.
    var fold:float=1.+.018*cos(3.*a+float(j)*.7)
    ps.append(Vector3(sin(a)*ring.y*width*fold,ring.x,cos(a)*ring.z*fold+ring.w))
    var slope:float=(rings[mini(pair[0]+1,rings.size()-1)].y-rings[maxi(pair[0]-1,0)].y)/.22
    ns.append(Vector3(sin(a)/width,-slope,cos(a)).normalized())
   # Rings run clockwise when viewed from above.
   quad(ps,ns,0.)
func make(variant:int,detail:bool,far_detail:bool=false)->ArrayMesh:
 distant=far_detail
 standing=variant==7
 st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
 segments=4 if distant else 12 if detail else 6
 var lean:float=[-.04,.015,-.07,.035,-.025,.01,-.055,.025][variant%8]
 var width:float=[1.,.90,1.02,.95,.92,1.01,.96,.91][variant%8]
 torso(lean,width)
 if detail:ellipsoid(Vector3(0,.779 if standing else .399,.015),Vector3(.157*width,.10,.134),2.,segments,4)
 limb(Vector3(0,1.015,lean),Vector3(0,1.08,lean),.047,.044,1.)
 # Separate collar sits around the neck, with an open skin centre.
 if not distant:limb(Vector3(0,1.023,lean),Vector3(0,1.047,lean),.060,.054,4.)
 var head:Vector3=Vector3(.008*sin(variant*1.7),1.172,lean-.01)
 ellipsoid(head,Vector3(.080,.115,.083),1.,segments,3 if distant else 6 if detail else 4)
 ellipsoid(head+Vector3(0,.055,.013),Vector3(.081,.069,.079),3.,segments,2 if distant else 4)
 if detail and variant%3==1:
  ellipsoid(head+Vector3(0,-.018,.065),Vector3(.087,.096,.043),3.,segments,4)
 if detail:
  for sx in [-1.,1.]:ellipsoid(head+Vector3(sx*.079,-.005,0),Vector3(.014,.024,.018),1.,6,4)
 for sx in [-1.,1.]:
  var shoulder:Vector3=Vector3(sx*.185*width,.941,lean)
  var elbow:Vector3=Vector3(sx*.205*width,.717,lean-.025)
  var hand:Vector3=Vector3(sx*.128,.485,-.19)
  match variant%8:
   1:hand=Vector3(sx*.10,.51,-.24);elbow.z=-.09
   2:hand=Vector3(sx*.145,.48,-.31);elbow=Vector3(sx*.20,.69,-.13)
   3:hand=Vector3(sx*.18,.46,-.10)
   4:
    if sx>0:hand=Vector3(.055,.93,-.15);elbow=Vector3(.19,.76,-.13)
   5:hand=Vector3(sx*.045,.65,-.24);elbow=Vector3(sx*.21,.72,-.07)
   6:hand=Vector3(sx*.15,.52,-.28);elbow.z=-.12
   7:
    if sx<0:hand=Vector3(-.20,.57,-.26)
  var sleeve_end:Vector3=shoulder.lerp(elbow,.60 if variant%3==0 else .94)
  limb(shoulder,sleeve_end,.069,.053,0.)
  if detail:ellipsoid(shoulder,Vector3(.072,.070,.073),0.,segments,4)
  limb(sleeve_end,elbow,.049,.043,1. if variant%3==0 else 0.)
  limb(elbow,hand,.041,.028,1. if variant%3==0 else 0.)
  if detail:ellipsoid(hand,Vector3(.033,.039,.051),1.,segments,4)
  var hip:Vector3=Vector3(sx*.090,.401,.005)
  var knee:Vector3=Vector3(sx*(.111+.012*(variant%3)),.36,-.33)
  var ankle:Vector3=Vector3(knee.x,.0,-.30+.022*(variant%3))
  if standing:
   hip=Vector3(sx*.09,.78,.005);knee=Vector3(sx*.11,.38,-.025);ankle=Vector3(sx*.12,0.,-.015)
  limb(hip,knee,.086,.061,2.)
  if detail:ellipsoid(knee,Vector3(.062,.058,.062),2.,segments,4)
  limb(knee,ankle-Vector3.UP*.052,.057,.033,2.)
  ellipsoid(ankle+Vector3(0,-.085,-.045),Vector3(.049,.047,.112),5.,segments,4 if detail else 2)
  if detail:ellipsoid(ankle+Vector3(0,-.112,-.045),Vector3(.051,.019,.113),6.,segments,4)
 st.index();return st.commit()
