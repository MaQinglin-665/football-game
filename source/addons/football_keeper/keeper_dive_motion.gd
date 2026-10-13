extends RefCounted
## Two GK only. World still owns every translation/collision, never position writes.
const Body := preload("res://addons/football_keeper/keeper_dive_body.gd")
const LowState := preload("res://addons/football_interaction/low_body_state.gd")
const CROUCH := .10
const FLIGHT := .30
const LAND := .16
const GETUP := .55
const SIDE_SPEED := 2.2
const LIFT_SPEED := .85
var actor: Node3D
var host: Node
var body = Body.new()
var phase := "IDLE"
var age := 0.0
var total_age := 0.0
var cooldown := 0.0
var side := 1.0
var push_speed := SIDE_SPEED
var forward_speed := 0.0
var lift_speed := LIFT_SPEED
var flight_seconds := FLIGHT
var next_offer_frame := -1
var facing_basis := Basis.IDENTITY
var ground_y := 0.0
var action_id := ""
var valid := false
var central_block:=false
var block_drop:=.65
var sequence := 0
var stand_check_frame := -1
var stand_check_result := false

func bind(keeper: Node3D, authority: Node) -> bool:
	actor = keeper
	host = authority
	valid = body.bind(actor.avatar,self)
	if valid:
		# Ordinary AI creates this component lazily after a physical trip.
		# A keeper's own dive also needs it before the first low-body action.
		if not is_instance_valid(actor.down_state):
			var low = LowState.new()
			low.setup(host.game,actor)
			actor.down_state = low
			actor.add_child(low)
		actor.avatar.keeper_dive = self
	return valid

func active() -> bool:
	return phase!="IDLE"

func owns_low_state() -> bool:
	return active() and is_instance_valid(actor.down_state) and actor.down_state.state=="SLIDE" and actor.down_state.action_id==action_id

func weight() -> float:
	if central_block:
		return smoothstep(0.0,CROUCH,age) if phase=="CROUCH" else 1.0-smoothstep(0.0,GETUP,age) if phase=="GETUP" else 1.0 if active() else 0.0
	match phase:
		"CROUCH": return .08*smoothstep(0.0,CROUCH,age)
		"FLIGHT": return lerpf(.08,1.0,smoothstep(0.0,.28,age))
		"LAND": return 1.0
		"GETUP": return 1.0-smoothstep(0.0,GETUP,age)
	return 0.0

func crouch_weight() -> float:
	return sin(PI*clampf(age/CROUCH,0.0,1.0)) if phase=="CROUCH" else .30*(1.0-weight()) if active() else 0.0

func offer() -> Dictionary:
	if not valid or not actor.active or active() or cooldown>0.0 or not host.legal_hand_contact(actor,host.game.ball.global_position):return {}
	if actor.down_state.blocked() or not actor.foot.idle() or actor.foot.has_buffer() or host.game.ball.carrier!=null or host.game.ball.held:return {}
	var frame:int=Engine.get_physics_frames()
	if frame<next_offer_frame:return {}
	next_offer_frame=frame+3 # Only two keepers; no per-substep global search.
	var ball:Node3D=host.game.ball
	var basis:Basis=actor.avatar.visual.global_basis.orthonormalized()
	var p:Vector3=basis.inverse()*(ball.global_position-actor.global_position)
	var v:Vector3=basis.inverse()*ball.velocity
	if v.z<1.5:return {}
	var crossing:float=(-.48-p.z)/v.z
	if crossing<.18 or crossing>.72:return {}
	var floor_y:float=actor.origin_ground_y if actor.origin_ground_supported else actor.global_position.y-.002
	for shift in [0.0,-.025,.025]:
		var time:float=crossing+shift
		if time<.16:continue
		var target:Vector3=ball.global_position+ball.velocity*time
		var grounded:bool=ball.global_position.y<=ball.radius+.025 and ball.velocity.y<=.2
		if grounded:
			var horizontal:Vector3=Vector3(ball.velocity.x,0,ball.velocity.z)
			target=ball.global_position+horizontal.normalized()*maxf(0,horizontal.length()*time-.5*host.game.physics_profile.roll_deceleration_mps2*time*time)
			target.y=ball.radius+.014
		else:target.y-=float(host.game.physics_profile.gravity_mps2)*.5*time*time
		if target.y<ball.radius+.008 or target.y>2.25:continue
		var local:Vector3=basis.inverse()*(target-actor.global_position)
		if absf(local.x)<.28 or absf(local.x)>2.25 or local.z>-.12 or local.z<-1.0:continue
		var mode:String="catch" if (ball.velocity-actor.velocity).length()<6.0 else "parry"
		if body.standing_can_reach(target,basis,mode,ball.radius):continue
		var selected_side:float=signf(local.x)
		var tau:float=time-CROUCH
		var push:float=clampf((absf(local.x)-.45)/maxf(.08,tau)+.30*tau,.8,4.2)
		var lift:float=clampf((target.y-.55+.5*actor.profile.gravity_mps2*tau*tau)/maxf(.08,tau),LIFT_SPEED,4.2)
		var predicted:Vector3=actor.global_position+basis.x*selected_side*maxf(0,push*tau-.30*tau*tau)
		# A low lateral save needs a small real forward dive to reach the hand plane.
		# Keep the prediction and the World-owned motor impulse consistent.
		var forward_push:float=.65 if grounded else 0.0
		predicted-=basis.z*forward_push*tau
		predicted.y=maxf(floor_y+.002,actor.global_position.y+lift*tau-.5*actor.profile.gravity_mps2*tau*tau)
		var weight_at:float=lerpf(.08,1.0,smoothstep(0.0,.28,tau))
		if not host._own_area(actor,predicted) or not host._own_area(actor,target,ball.radius):continue
		var count:int=body.predicted_hand_count(target,predicted,basis,selected_side,weight_at,mode,ball.radius,floor_y)
		if count==0:continue
		if mode=="catch" and count<2:
			mode="parry"
			if not body.can_reach(target,predicted,basis,selected_side,weight_at,mode,ball.radius,floor_y):continue
		return {"dive":true,"target_world":target,"hand_mode":mode,"side":selected_side,"basis":basis,"ground_y":floor_y,"predicted_contact_seconds":time,"predicted_origin":predicted,"push_speed":push,"forward_speed":forward_push,"lift_speed":lift,"flight_seconds":clampf(tau+.06,FLIGHT,.66),"contact_seconds":time+.04}
	return {}

func start(offer_data: Dictionary) -> void:
	central_block=bool(offer_data.get("central_block",false))
	block_drop=float(offer_data.get("block_drop",.65))
	sequence += 1
	action_id = "gk-dive:%d:%d" % [actor.get_instance_id(),sequence]
	side = float(offer_data.side)
	push_speed = float(offer_data.get("push_speed",SIDE_SPEED))
	forward_speed = float(offer_data.get("forward_speed",0.0))
	lift_speed = float(offer_data.get("lift_speed",LIFT_SPEED))
	flight_seconds = float(offer_data.get("flight_seconds",FLIGHT))
	facing_basis = offer_data.basis
	ground_y = float(offer_data.ground_y)
	phase = "CROUCH"
	age = 0.0
	total_age = 0.0
	actor.foot.cancel()
	actor.pending_kick.clear()
	actor.set_move_intent(Vector3.ZERO)
	actor.down_state.set_slide(weight(),facing_basis.x*side,action_id)
	host._emit("GK_DIVE_BEGIN",actor,{"side":side,"target":offer_data.target_world,"predicted_origin":offer_data.predicted_origin,"predicted_contact_seconds":offer_data.predicted_contact_seconds})

func advance_motor(dt: float) -> bool:
	cooldown = maxf(0.0,cooldown-dt)
	if not active(): return false
	if not owns_low_state() or not actor.active or not actor.visible or not host._live():
		cancel("external_down_or_rule")
		return false
	age += dt
	total_age += dt
	if central_block:
		if phase=="CROUCH" and age>=CROUCH:phase="BLOCK";age-=CROUCH
		elif phase=="BLOCK" and age>=flight_seconds:phase="GETUP";age=0.0
		elif phase=="GETUP" and age>=GETUP:cancel("central_recovered");return false
		var horizontal:=Vector3(actor.velocity.x,0,actor.velocity.z).move_toward(Vector3.ZERO,18.0*dt)
		actor.velocity.x=horizontal.x;actor.velocity.z=horizontal.z
		actor.velocity.y-=actor.profile.gravity_mps2*dt
		actor.down_state.set_slide(weight(),-facing_basis.z,action_id);body.sync_volume()
		return true
	if phase=="CROUCH" and age>=CROUCH:
		phase = "FLIGHT"
		age -= CROUCH
		var before: Vector3 = actor.velocity
		var desired: Vector3 = facing_basis.x*side*push_speed-facing_basis.z*forward_speed
		actor.receive_body_impulse_ns((desired-Vector3(before.x,0,before.z))*actor.physics_mass_kg())
		actor.velocity.y = maxf(actor.velocity.y,lift_speed)
		host._emit("GK_DIVE_PUSH",actor,{"velocity":actor.velocity})
	elif phase=="FLIGHT" and age>=flight_seconds and actor.global_position.y<=ground_y+.08:
		phase = "LAND"
		age = 0.0
		host._emit("GK_DIVE_LAND",actor,{"velocity":actor.velocity})
	elif phase=="LAND" and age>=LAND:
		if not _can_stand():
			actor.down_state.enter_recovery(action_id+":blocked",facing_basis.x*side,.05)
			cancel("handoff_blocked_getup")
			return false
		phase = "GETUP"
		age = 0.0
	elif phase=="GETUP":
		if not _can_stand():
			actor.down_state.enter_recovery(action_id+":getup-blocked",facing_basis.x*side,.05)
			cancel("handoff_blocked_getup")
			return false
		if age>=GETUP:
			cancel("recovered")
			return false
	var flat := Vector3(actor.velocity.x,0,actor.velocity.z)
	flat = flat.move_toward(Vector3.ZERO,(.60 if phase=="FLIGHT" else 7.0 if phase=="CROUCH" else 6.0)*dt)
	actor.velocity.x = flat.x
	actor.velocity.z = flat.z
	actor.velocity.y -= actor.profile.gravity_mps2*dt
	actor.down_state.set_slide(weight(),facing_basis.x*side,action_id)
	body.sync_volume()
	return true

func _can_stand() -> bool:
	var frame := Engine.get_physics_frames()
	if frame!=stand_check_frame:
		stand_check_frame = frame
		stand_check_result = actor.down_state.can_stand()
	return stand_check_result

func cancel(reason: String) -> void:
	if not active(): return
	var owned := owns_low_state()
	phase = "IDLE"
	age = 0.0
	cooldown = 1.20
	if owned:
		actor.down_state.state = "IDLE"
		actor.down_state.weight = 0.0
		actor.down_state.apply_volume()
	body.restore()
	actor.avatar.invalidate_pose_snapshot()
	host._emit("GK_DIVE_END",actor,{"reason":reason,"elapsed":total_age,"low_state":actor.down_state.state})

func scoop_offer()->Dictionary:
	if not valid or not actor.active or active() or cooldown>0.0 or not host.legal_hand_contact(actor,host.game.ball.global_position):return {}
	var ball:Node3D=host.game.ball
	if actor.down_state.blocked() or not actor.foot.idle() or actor.foot.has_buffer() or ball.carrier!=null or ball.held:return {}
	if ball.velocity.length()>4.0 or ball.position.y>ball.radius+.12:return {}
	var offset:Vector3=ball.global_position-actor.global_position
	if Vector2(offset.x,offset.z).length()>1.35 or actor.velocity.length()>2.0:return {}
	var floor_y:float=actor.origin_ground_y if actor.origin_ground_supported else actor.global_position.y-.002
	var time:float=.40
	var speed:float=Vector2(ball.velocity.x,ball.velocity.z).length()
	var travel:float=maxf(0.0,speed*time-.5*host.game.physics_profile.roll_deceleration_mps2*time*time)
	var target:Vector3=ball.global_position+Vector3(ball.velocity.x,0,ball.velocity.z).normalized()*travel
	target.y=ball.radius+.014
	var base:Basis=actor.avatar.visual.global_basis.orthonormalized()
	for yaw in [0.0,-.60,.60]:
		var basis:Basis=base*Basis(Vector3.UP,yaw)
		for selected_side in [-1.0,1.0]:
			var predicted:Vector3=actor.global_position+basis.x*selected_side*.09
			predicted.y=floor_y+.002
			if not host._own_area(actor,predicted) or not host._own_area(actor,target,ball.radius):continue
			if body.predicted_hand_count(target,predicted,basis,selected_side,1.0,"catch",ball.radius,floor_y)<2:continue
			return {"dive":true,"target_world":target,"hand_mode":"catch","side":selected_side,"basis":basis,"ground_y":floor_y,"predicted_contact_seconds":time,"predicted_origin":predicted,"push_speed":.4}
	return {}

func central_offer()->Dictionary:
	if not valid or not actor.active or active() or cooldown>0.0 or not host.legal_hand_contact(actor,host.game.ball.global_position):return {}
	var ball:Node3D=host.game.ball
	if actor.down_state.blocked() or not actor.foot.idle() or actor.foot.has_buffer() or ball.carrier==actor or ball.held:return {}
	var basis:Basis=actor.avatar.visual.global_basis.orthonormalized()
	var local:Vector3=basis.inverse()*(ball.global_position-actor.global_position)
	var incoming:Vector3=basis.inverse()*(ball.velocity-actor.velocity)
	var seconds:float=(-.42-local.z)/maxf(incoming.z,.01)
	var near_threat:bool=is_instance_valid(ball.carrier) and ball.carrier.team!=actor.team and Vector2(local.x,local.z).length()<1.25
	if incoming.z<1.0 or seconds<.14 or seconds>.60:
		if not near_threat or local.z>-.20:return {}
		seconds=.16
	var target:Vector3=ball.global_position+ball.velocity*seconds
	if ball.global_position.y<=ball.radius+.025 and ball.velocity.y<=.2:
		var flat:=Vector3(ball.velocity.x,0,ball.velocity.z)
		target=ball.global_position+flat.normalized()*maxf(0,flat.length()*seconds-.5*host.game.physics_profile.roll_deceleration_mps2*seconds*seconds)
		target.y=ball.radius+.012
	else:target.y-=.5*host.game.physics_profile.gravity_mps2*seconds*seconds
	var at:Vector3=basis.inverse()*(target-actor.global_position)
	if at.y<ball.radius-.02 or at.y>.80 or absf(at.x)>.62 or at.z>-.12 or at.z<-1.05:return {}
	var floor_y:float=actor.origin_ground_y if actor.origin_ground_supported else actor.global_position.y-.002
	if not host._own_area(actor,target,ball.radius):return {}
	return {"dive":true,"central_block":true,"block_drop":clampf(1.38-at.y-.50,.28,.76),"target_world":target,"hand_mode":"catch" if (ball.velocity-actor.velocity).length()<=6.0 and not near_threat else "parry","side":0.0,"basis":basis,"ground_y":floor_y,"predicted_contact_seconds":seconds,"predicted_origin":actor.global_position,"push_speed":0.0,"lift_speed":0.0,"flight_seconds":seconds+.10,"contact_seconds":seconds+.12}
