extends RefCounted
# Game presets, not a claim of official competition dimensions. Counts include GK.
const Roles=preload("res://scripts/tactics/role_catalog.gd")
static func spec(count:int)->Dictionary:
	if count==5:
		return {"formation":"1–2–1", "jerseys":[1,4,8,10,9], "human":3,
		"slots":["GK","CB","LCM","RCM","CF"],
		"roles":[Roles.GOALKEEPER,Roles.CENTER_BACK,Roles.MIDFIELDER,Roles.MIDFIELDER,Roles.STRIKER],
		"lanes":[0.0,0.0,-.65,.65,0.0], "duties":["keeper","cover","support","support","finish"],
		"homes":[Vector2(0,16.5),Vector2(0,11),Vector2(-5,6),Vector2(5,6),Vector2(0,2)]}
	if count==6:
		return {"formation":"2–2–1", "jerseys":[1,4,5,8,10,9], "human":4,
		"slots":["GK","LCB","RCB","LCM","RCM","CF"],
		"roles":[Roles.GOALKEEPER,Roles.CENTER_BACK,Roles.CENTER_BACK,Roles.MIDFIELDER,Roles.MIDFIELDER,Roles.STRIKER],
		"lanes":[0.0,-.65,.65,-.7,.7,0.0], "duties":["keeper","cover","cover","support","support","finish"],
		"homes":[Vector2(0,23),Vector2(-6,17),Vector2(6,17),Vector2(-9,8),Vector2(9,8),Vector2(0,2)]}
	assert(count==9)
	return {"formation":"3–3–2", "jerseys":[1,3,4,2,8,14,10,9,11], "human":6,
		"slots":["GK","LB","CB","RB","LCM","DM","RCM","LF","RF"],
		"roles":[Roles.GOALKEEPER,Roles.FULL_BACK,Roles.CENTER_BACK,Roles.FULL_BACK,Roles.MIDFIELDER,Roles.MIDFIELDER,Roles.MIDFIELDER,Roles.STRIKER,Roles.STRIKER],
		"lanes":[0.0,-1.0,0.0,1.0,-.7,0.0,.7,-.55,.55], "duties":["keeper","balance","cover","balance","support","hold","support","finish","finish"],
		"homes":[Vector2(0,35),Vector2(-17,26),Vector2(0,29),Vector2(17,26),Vector2(-13,13),Vector2(0,18),Vector2(13,13),Vector2(-7,3),Vector2(7,3)]}
static func dimensions(count:int)->Resource:
	if count==5:return preload("res://config/training_3v3.tres").dimensions()
	var d=preload("res://addons/modern_stadium/stadium_dimensions.gd").new()
	d.regulation_markings=false
	d.pitch_length=50.0 if count==6 else 75.0
	d.pitch_width=34.0 if count==6 else 50.0
	d.goal_width=5.0 if count==6 else 6.0
	d.goal_height=2.0 if count==6 else 2.2
	d.goal_area_depth=3.0 if count==6 else 4.0
	d.penalty_area_depth=9.0 if count==6 else 12.0
	d.penalty_distance=6.0 if count==6 else 9.0
	d.circle_radius=5.0 if count==6 else 7.5
	d.quality_label="small_sided_%d"%count
	return d
static func roster(count:int,team:int,ids:Array,human_id:int=-1)->Array[Dictionary]:
	assert(ids.size()==count)
	var s=spec(count)
	var result:Array[Dictionary]=[]
	for i in count:
		result.append({"id":int(ids[i]),"team":team,"role":s.roles[i],"is_goalkeeper":i==0,"lane":s.lanes[i],"duty":s.duties[i],"slot":s.slots[i],"human":int(ids[i])==human_id})
	return result
