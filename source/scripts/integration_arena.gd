class_name FootballArenaIntegration
extends RefCounted
const FullStadium := preload("res://addons/modern_stadium/scenes/modern_stadium_105x68.tscn")

static func attach(game: Node3D) -> Node3D:
	var stadium: Node3D
	if game.training_configuration != null:
		stadium = preload("res://addons/modern_stadium/stadium_factory.gd").build_training(game.training_configuration.dimensions())
	elif game.team_size==5 or game.small_training_pitch:
		stadium=preload("res://addons/modern_stadium/stadium_factory.gd").build_training(game.SmallSides.dimensions(5))
	elif game.team_size in [6,9]:
		stadium=preload("res://addons/modern_stadium/stadium_factory.gd").build(game.SmallSides.dimensions(game.team_size))
	else:
		stadium = FullStadium.instantiate()
	game.add_child(stadium)
	var layout: Dictionary = stadium.get_layout()
	game.field_half_width = float(layout.field_half_width)
	game.field_half_length = float(layout.field_half_length)
	game.goal_width = float(layout.goal_width_clear)
	game.goal_height = float(layout.goal_height_clear)
	game.field_layout = layout.duplicate(true)
	# Only environment lighting is retained from the existing project. Old
	# pitch/goal geometry is never built alongside the delivered large stadium.
	var world := WorldEnvironment.new()
	world.name = "MatchEnvironment"
	var environment := Environment.new()
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("5d91aa")
	sky_material.sky_horizon_color = Color("d6d7bb")
	sky_material.ground_horizon_color = Color("d6d7bb")
	sky_material.ground_bottom_color = Color("a1a791")
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d7e7e7")
	environment.ambient_light_energy = 0.28
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	world.environment = environment
	game.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.name = "MatchSun"
	sun.rotation_degrees = Vector3(-48,-32,0)
	sun.light_color = Color("fff0cc")
	sun.light_energy = 0.62
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 100
	game.add_child(sun)
	return stadium
