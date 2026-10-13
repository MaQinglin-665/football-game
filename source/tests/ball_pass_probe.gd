extends SceneTree
const Ball = preload("res://addons/football_physics/football_ball.gd")
const Profile = preload("res://addons/football_physics/physics_profile.gd")
var label := "before"
func _initialize()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="):label=arg.trim_prefix("--label=")
	call_deferred("run")
func run()->void:
	var floor_body:=StaticBody3D.new()
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(600,.2,600);shape.shape=box;floor_body.add_child(shape);floor_body.position.y=-.1;root.add_child(floor_body)
	var ball:=Ball.new();ball.profile=Profile.playable();ball.auto_step=false;root.add_child(ball)
	await physics_frame;await physics_frame
	var results:Array=[]
	for spec in [{"name":"short","power":.0,"angle":0.0},{"name":"medium","power":.35,"angle":0.0},{"name":"long_ground","power":1.0,"angle":0.0},{"name":"loft_half","power":.5,"angle":34.0},{"name":"loft_full","power":1.0,"angle":34.0},{"name":"loft_team","power":1.0,"angle":34.0,"speed":26.0},{"name":"low_roll","speed":.3},{"name":"sliding","speed":8.0}]:
		ball.position=Vector3(0,.111,0);ball.velocity=Vector3.ZERO;ball.spin_rads=Vector3.ZERO
		if spec.has("angle"):ball.kick(Vector3.FORWARD,spec.power,spec.angle,Vector3.ZERO,"pass",spec.get("speed",-1.0))
		else:
			ball.velocity=Vector3.FORWARD*float(spec.speed)
			if spec.name=="low_roll":ball.spin_rads=Vector3.UP.cross(ball.velocity)/ball.radius
		var row:Dictionary={"name":spec.name,"launch_speed":ball.velocity.length(),"samples":[],"arrival":{},"peak":0.0,"landing_time":-1.0,"landing_distance":-1.0,"ground_hops":0,"max_ground_height":0.0,"max_speed_gain":0.0}
		var raised:bool=false;var previous_speed:float=ball.velocity.length();var previous_vy:float=ball.velocity.y
		for i in 1800:
			ball.step_physics(1.0/120)
			var time:float=float(i+1)/120;var distance:float=-ball.position.z
			row.peak=maxf(row.peak,ball.position.y)
			row.max_speed_gain=maxf(row.max_speed_gain,ball.velocity.length()-previous_speed)
			if ball.position.y>.3:raised=true
			if raised and row.landing_time<0 and previous_vy<0 and ball.velocity.y>=0:
				row.landing_time=time;row.landing_distance=distance
			if not spec.has("angle") or spec.get("angle",0)==0:
				row.max_ground_height=maxf(row.max_ground_height,ball.position.y)
				if previous_vy<=0 and ball.velocity.y>.1:row.ground_hops+=1
			for marker in [5,10,20,35]:
				if distance>=marker and not row.arrival.has(str(marker)):row.arrival[str(marker)]={"time":time,"speed":ball.velocity.length()}
			if i%30==0:row.samples.append({"t":time,"position":ball.position,"speed":ball.velocity.length(),"spin":ball.spin_rads,"slip":(ball.velocity+ball.spin_rads.cross(Vector3.DOWN*ball.radius)).length()})
			previous_speed=ball.velocity.length();previous_vy=ball.velocity.y
			if time>.1 and ball.velocity.length()<.001:
				row.stop_time=time;break
		row.end_distance=-ball.position.z;row.end_speed=ball.velocity.length();results.append(row)
	var path:=ProjectSettings.globalize_path("res://../verification/ball_"+label+".json")
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(results,"  "));print(path)
	ball.queue_free();floor_body.queue_free();await process_frame;quit()
