extends SceneTree
const Shape := preload("res://scripts/tactics/restart_shape.gd")
var game: Node
var checks: Array[Dictionary] = []
var output := ""

func _initialize() -> void:
	output = ProjectSettings.globalize_path("res://../verification/01_restart_shapes.json")
	call_deferred("run")

func check(label: String, ok: bool, details: Variant = null) -> void:
	checks.append({"check":label,"passed":ok,"details":details})
	print("PASS " if ok else "FAIL ",label," ",details if details!=null else "")

func xyz(v: Vector3) -> Array:
	return [v.x,v.y,v.z]

func run() -> void:
	game = load("res://scenes/match.tscn").instantiate()
	root.add_child(game)
	for i in 5: await process_frame
	game.hud.menu.get_node("StartMatch").pressed.emit()
	for i in 720: await physics_frame
	check("22 actors, one goalkeeper per team, fixed human #10",game.players.size()==22 and game.players.filter(func(p):return p.is_goalkeeper).size()==2 and game.player.jersey==10 and game.player.team==0)
	check("actual kickoff READY is legal",game.services.rules.state==game.Rules.State.RESTART_READY and game.services.rules.restart_violations().is_empty(),game.services.rules.restart_violations())
	check("dead-ball player input/view and World remain enabled",game.player.input_enabled and game.player.head.enabled and game.physics_world.auto_step)
	var actors := []
	var within_shape := true
	var resting := true
	for actor in game.players:
		var goal := Shape.kickoff_target(actor.role,actor.lane,game.attack_direction(actor.team),game.field_half_width,game.field_half_length)
		actors.append({"id":game.players.find(actor),"name":String(actor.name),"team":actor.team,"role":actor.role,"human":actor.is_human,"jersey":actor.jersey,"position":xyz(actor.position),"velocity":xyz(actor.velocity),"formation_goal":xyz(goal),"motor_target":xyz(actor.target) if not actor.is_human else null})
		if not actor.is_human and game.flat_distance(actor.position,goal)>1.2: within_shape = false
		if not actor.is_human and Vector2(actor.velocity.x,actor.velocity.z).length()>.25: resting = false
	check("actual 21 AI walk to separated role staging targets",within_shape,actors)
	check("arrived AI settle instead of clearance-overshoot pacing",resting)
	var both_halves_ok := true
	var min_spacing := INF
	var static_shapes := []
	for half in [1,2]:
		for team in [0,1]:
			var points := []
			var width_min := INF
			var width_max := -INF
			var attack := (-1.0 if team==0 else 1.0)*(1.0 if half==1 else -1.0)
			for row in game.roster_configuration:
				if row.team!=team: continue
				var target := Shape.kickoff_target(row.role,row.lane,attack,game.field_half_width,game.field_half_length)
				points.append(target)
				both_halves_ok = both_halves_ok and target.z*attack<=-.35 and target.length()>=11.5-.01
				width_min = minf(width_min,target.x)
				width_max = maxf(width_max,target.x)
				static_shapes.append({"half":half,"team":team,"id":row.id,"role":row.role,"position":xyz(target)})
			for a in range(points.size()):
				for b in range(a+1,points.size()): min_spacing = minf(min_spacing,points[a].distance_to(points[b]))
			both_halves_ok = both_halves_ok and width_max-width_min>45.0
	check("both halves and teams retain width, own half and centre-circle clearance",both_halves_ok)
	check("formation destinations never share a body queue",min_spacing>5.0,{"minimum_metres":min_spacing})
	var passed := checks.filter(func(c):return c.passed).size()
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failed":checks.size()-passed,"checks":checks,"actors":actors,"static_shapes":static_shapes,"headless":true,"actual_actor_positions":true,"native_screenshot":false,"human_transform_modified":false,"scope":"Actual default kickoff motor/collision staging; pure mirrored shape checks. Menu callback exercised, native GPU/input not evaluated."},"\t"))
	game.pause_match()
	game.shutdown_audio()
	game.queue_free()
	for i in 4: await process_frame
	quit(0 if passed==checks.size() else 1)
