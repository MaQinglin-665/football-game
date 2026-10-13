extends RefCounted
static func make()->ArrayMesh:
 # Curved concave seat bucket and back with real shell thickness, rolled leading lip.
 var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
 var profile=[[-.27,.88],[-.265,.92],[-.235,.94],[-.207,.93],[-.18,.85],[-.158,.66],[-.125,.50],[-.08,.455],[.02,.445],[.17,.46],[.225,.475],[.25,.462],[.254,.43],[.21,.421],[.08,.412],[-.09,.42],[-.16,.454],[-.197,.62],[-.22,.82],[-.27,.88]]
 for j in profile.size()-1:
  for i in 12:
   var quad:Array=[]
   for idx in [[i,j],[i+1,j],[i+1,j+1],[i,j+1]]:
    var u=float(idx[0])/12.;var r=profile[idx[1]];var x=(u-.5)*.44;var curve=pow(absf(x)/.22,3.)*.032
    quad.append(Vector3(x,r[1]+curve,r[0]+curve*.5))
   var norm=(quad[1]-quad[0]).cross(quad[2]-quad[0]).normalized()
   for k in [0,2,1,0,3,2]:st.set_normal(norm);st.set_uv(Vector2(quad[k].x,quad[k].y));st.add_vertex(Vector3(quad[k].x,quad[k].y-.15,-quad[k].z))
 # Endcaps on each shell side.
 for sx in [-.22,.22]:
  for j in range(1,profile.size()-2):
   for k in [0,j,j+1]:st.set_normal(Vector3(signf(sx),0,0));st.set_uv(Vector2.ZERO);st.add_vertex(Vector3(sx,profile[k][1]+.032-.15,-profile[k][0]-.016))
 st.index();st.generate_normals();return st.commit()

