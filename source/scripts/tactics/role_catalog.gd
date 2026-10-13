class_name FootballTacticalRoles
extends RefCounted
## Role coordinates use a team's local frame: +x right, +y toward the other goal.
## Fractions in regions scale with pitch size; they describe responsibilities,
## not fixed destinations. The director shifts each anchor with play.

const GOALKEEPER := "goalkeeper"
const CENTER_BACK := "center_back"
const FULL_BACK := "full_back"
const MIDFIELDER := "midfielder"
const ATTACKING_MIDFIELDER := "attacking_midfielder"
const LEFT_MIDFIELDER := "left_midfielder"
const RIGHT_MIDFIELDER := "right_midfielder"
const WINGER := "winger"
const STRIKER := "striker"

static func definitions() -> Dictionary:
	return {
		GOALKEEPER: {"label":"门将", "attack":Vector2(0,-0.90), "defend":Vector2(0,-0.94), "region":Rect2(-0.28,-0.97,0.56,0.30), "width":0.0, "cover":true},
		CENTER_BACK: {"label":"中后卫", "attack":Vector2(0,-0.35), "defend":Vector2(0,-0.68), "region":Rect2(-0.55,-0.86,1.10,1.05), "width":0.0, "cover":true},
		FULL_BACK: {"label":"边后卫", "attack":Vector2(0.60,-0.10), "defend":Vector2(0.50,-0.58), "region":Rect2(-0.88,-0.85,1.76,1.38), "width":0.58, "cover":true},
		MIDFIELDER: {"label":"中场", "attack":Vector2(0,0.05), "defend":Vector2(0,-0.35), "region":Rect2(-0.62,-0.72,1.24,1.42), "width":0.0, "cover":false},
		ATTACKING_MIDFIELDER: {"label":"中前卫", "attack":Vector2(0,0.28), "defend":Vector2(0,-0.22), "region":Rect2(-0.64,-0.64,1.28,1.45), "width":0.0, "cover":false},
		LEFT_MIDFIELDER: {"label":"左中场", "attack":Vector2(-0.58,0.15), "defend":Vector2(-0.43,-0.32), "region":Rect2(-0.90,-0.74,0.98,1.48), "width":0.58, "cover":false},
		RIGHT_MIDFIELDER: {"label":"右中场", "attack":Vector2(0.58,0.15), "defend":Vector2(0.43,-0.32), "region":Rect2(-0.08,-0.74,0.98,1.48), "width":0.58, "cover":false},
		WINGER: {"label":"边锋", "attack":Vector2(0.70,0.38), "defend":Vector2(0.47,-0.24), "region":Rect2(-0.92,-0.76,1.84,1.67), "width":0.70, "cover":false},
		STRIKER: {"label":"前锋", "attack":Vector2(0,0.62), "defend":Vector2(0,-0.05), "region":Rect2(-0.68,-0.49,1.36,1.40), "width":0.0, "cover":false}
	}

static func profile(role: String) -> Dictionary:
	var all := definitions()
	return all.get(role,all[MIDFIELDER]).duplicate(true)

static func default_five(team: int, ids: Array, human_id := -1) -> Array[Dictionary]:
	assert(ids.size()==5,"Five-a-side includes exactly one keeper and four outfield players")
	# Legacy order: fixed player/AI #9, #7, #4, #11, #6. Preserve old numeric
	# roles (kickoff/duel code depends on them); tactical roles live separately.
	var roles := [ATTACKING_MIDFIELDER,WINGER,CENTER_BACK,WINGER,GOALKEEPER]
	var lanes := [0.0,-1.0,0.0,1.0,0.0]
	var roster: Array[Dictionary] = []
	for i in range(ids.size()):
		roster.append({"id":int(ids[i]),"team":team,"role":roles[i],"is_goalkeeper":roles[i]==GOALKEEPER,"lane":lanes[i],"human":int(ids[i])==human_id})
	return roster

static func default_eleven(team: int, ids: Array, human_id := -1) -> Array[Dictionary]:
	assert(ids.size()==11,"4-3-3 requires one keeper and ten outfield players")
	# ids order: GK, LB, LCB, RCB, RB, holding CM, left CM, attacking CM,
	# LW, CF, RW. #10 remains an attacking central midfielder under human input.
	var roles := [GOALKEEPER,FULL_BACK,CENTER_BACK,CENTER_BACK,FULL_BACK,MIDFIELDER,MIDFIELDER,MIDFIELDER,WINGER,STRIKER,WINGER]
	var lanes := [0.0,-1.0,-0.65,0.65,1.0,0.0,-0.65,0.55,-1.0,0.0,1.0]
	var slots := ["GK","LB","LCB","RCB","RB","DM","LCM","RCM","LW","CF","RW"]
	var duties := ["keeper","balance","cover","cover","balance","hold","support","support","width","finish","width"]
	var roster: Array[Dictionary] = []
	for i in range(ids.size()):
		roster.append({"id":int(ids[i]),"team":team,"role":roles[i],"is_goalkeeper":roles[i]==GOALKEEPER,"lane":lanes[i],"duty":duties[i],"slot":slots[i],"human":int(ids[i])==human_id})
	return roster
