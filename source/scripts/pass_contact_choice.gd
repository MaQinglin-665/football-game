extends RefCounted
## Read-only selection. One choice per gesture; the ordinary dribble is untouched.
static func choose(actor:Node3D, ball:Node3D, intent:Dictionary)->Dictionary:
	if actor.has_method("ensure_contact_pose_current"):actor.ensure_contact_pose_current()
	var forward:Vector3=-actor.avatar.visual.global_basis.z.normalized()
	var right:=Vector3(-forward.z,0,forward.x)
	var aim:Vector3=intent.get("direction",forward);aim.y=0;aim=aim.normalized()
	var offset:Vector3=ball.position-actor.position
	var lateral:float=offset.dot(right);var depth:float=offset.dot(forward)
	var high:bool=String(intent.get("action",""))=="pass_high" or float(intent.get("elevation_deg",0))>10
	var heel:bool=aim.dot(forward)<-.55
	# A planned long outlet must turn for a full strike, not silently become
	# a short heel pass whose force contradicts the team's arrival estimate.
	if heel and not actor.is_human and float(intent.get("power",0))>.16:return {}
	if heel and (high or depth<-.42 or depth>.32 or absf(lateral)>.48 or offset.length()>.62 or (ball.velocity-actor.velocity).length()>5.5):return {}
	if not heel and (depth<-.25 or offset.length()>1.06):return {}
	var best:Dictionary={};var best_cost:float=INF
	for side:int in [-1,1]:
		if absf(lateral)>.12 and lateral*side<0:continue # Do not cross through the standing leg.
		var surface:String="HEEL" if heel else "INSTEP" if high or float(intent.get("power",0))>.60 else "OUTSIDE" if aim.dot(right)*side>.38 else "INSIDE"
		var contact:Dictionary=actor.avatar.get_foot_contact(side,surface)
		if not contact.has("point"):continue
		var target:Vector3=ball.position-aim*ball.radius
		var cost:float=(contact.point as Vector3).distance_to(target)
		var support:Dictionary=actor.avatar.get_foot_contact(-side,"SOLE")
		cost+=clampf(absf((support.point as Vector3).y-actor.position.y)-.035,0,.15)
		if cost<best_cost:
			best_cost=cost
			best={"side":side,"surface":surface,"foot_direction":forward if heel else aim,"heel":heel,"loft":high,"power":minf(float(intent.get("power",0)),.16) if heel else float(intent.get("power",0))}
	return best

static func still_legal(actor:Node3D,ball:Node3D,choice:Dictionary)->bool:
	var offset:Vector3=ball.position-actor.position
	var forward:Vector3=-actor.avatar.visual.global_basis.z.normalized();var right:=Vector3(-forward.z,0,forward.x)
	if offset.dot(right)*int(choice.side)<-.12:return false
	if choice.surface=="HEEL":return offset.length()<=.65 and offset.dot(forward)>=-.44 and offset.dot(forward)<=.34 and (ball.velocity-actor.velocity).length()<=6
	return offset.length()<1.06 and offset.dot(forward)>-.26
