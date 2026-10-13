extends SceneTree
const A=preload("res://scripts/player_abilities.gd")
var failures:int=0
var game:Node
func check(label:String,ok:bool)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize()->void:call_deferred("run")
func run()->void:
	game=load("res://scenes/match.tscn").instantiate();game.test_mode=true;root.add_child(game);current_scene=game
	game.physics_world.auto_step=false
	var breaker:Node;var conductor:Node;var sweeper:Node
	for a in game.players:
		if a.team!=1:continue
		match a.get_meta("abilities",{}).get("role",""):
			"breaker":breaker=a
			"conductor":conductor=a
			"sweeper":sweeper=a
	check("three specialized identities exist",breaker!=null and conductor!=null and sweeper!=null)
	check("human uses unchanged profile",game.player.profile==game.physics_profile and game.player.get_meta("abilities",{}).is_empty())
	check("private player profiles never mutate ball profile",breaker.profile!=conductor.profile and game.ball.profile==game.physics_profile and is_equal_approx(game.physics_profile.start_acceleration_mps2,6.8))
	check("ball mass gravity and radius identical",breaker.profile.ball_mass_kg==game.physics_profile.ball_mass_kg and breaker.profile.gravity_mps2==game.physics_profile.gravity_mps2 and breaker.profile.ball_radius_m==game.physics_profile.ball_radius_m)
	var speeds:Array=[]
	for a in [breaker,conductor]:
		a.velocity=Vector3.ZERO;a.move_intent=Vector3.FORWARD;a.sprint_intent=1
		for i in 120:a.advance_motor(1.0/120.0)
		speeds.append(Vector2(a.velocity.x,a.velocity.z).length());a.velocity=Vector3.ZERO
	check("actual motor produces faster initial acceleration for breaker",float(speeds[0])>float(speeds[1])+.1)
	print("MOTOR_SPEED_AFTER_1S ",speeds)
	var v:Vector3=Vector3(0,0,-6)
	var stops:Array=[]
	for a in [breaker,sweeper]:
		var velocity:Vector3=v;var distance:float=0
		for i in 120:
			velocity=preload("res://scripts/movement_inertia.gd").step(velocity,Vector3.ZERO,a.profile,0,1.0/120)
			distance+=velocity.length()/120
		stops.append(distance)
	check("sweeper braking uses the same physical integrator",float(stops[1])<float(stops[0]))
	print("STOP_DISTANCE_FROM_6MPS ",stops)
	var original:Dictionary={"action":"pass_ground","direction":Vector3.FORWARD,"power":.5}
	var error_breaker:float=0;var error_conductor:float=0
	for i in range(1,60):
		error_breaker+=absf(float(A.pass_intent(breaker,original,i,Vector3.ZERO,[]).ability_contact_error_deg))
		error_conductor+=absf(float(A.pass_intent(conductor,original,i,Vector3.ZERO,[]).ability_contact_error_deg))
	check("conductor contact dispersion is lower",error_conductor<error_breaker*.5)
	check("pass intent is not mutated",original.direction==Vector3.FORWARD and not original.has("ability_contact_error_deg"))
	check("human pass intent remains exact",A.pass_intent(game.player,original,1,Vector3.ZERO,[])==original)
	var director=game.tactical_director
	var b:Dictionary=A.observation(breaker);b.merge({"position":Vector3.ZERO,"velocity":Vector3.ZERO,"facing":Vector3.FORWARD})
	var c:Dictionary=A.observation(conductor);c.merge({"position":Vector3.ZERO,"velocity":Vector3.ZERO,"facing":Vector3.FORWARD})
	check("team pass ETA uses actual different capabilities",director.team_attack.eta(b,Vector3(0,0,-12))<director.team_attack.eta(c,Vector3(0,0,-12)))
	var old_profile=breaker.profile
	breaker.role="center_back"
	check("changing formation role preserves player identity",breaker.profile==old_profile and breaker.get_meta("abilities").role=="breaker")
	game.shutdown_audio();quit(1 if failures else 0)
