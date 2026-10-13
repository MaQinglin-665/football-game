extends SceneTree
class FakeGame extends Node:
	enum Phase {PLAY, PAUSED, MENU, FINISHED}
	var phase=Phase.PLAY
	var ai_enabled=true
class Probe extends "res://scripts/integration_tactics.gd":
	var seen:Dictionary={}
	func _build_snapshot()->Dictionary:
		var actors:Array[Dictionary]=[]
		return {"actors":actors,"snapshot":{"fresh":true}}
	func _run_director(_actors:Array[Dictionary],snapshot:Dictionary,_delta:float)->void:seen=snapshot
var failed:=0
func check(label:String,ok:bool)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failed+=1
func _initialize()->void:
	var script=preload("res://scripts/tactics/receive_plan.gd")
	var original:Dictionary={"ball_point":Vector3(1,.11,1),"body_point":Vector3(1,0,.62),"face_direction":Vector3.FORWARD,"reachable":true,"horizon":.5}
	for mode in ["bounce","delayed","height","expired"]:
		var plan=script.new();plan.active={};plan.clock=2.0;plan._apply_lock(original)
		var changed:Dictionary=original.duplicate()
		if mode=="bounce":changed.await_settle=true
		if mode=="delayed":changed.horizon=1.8
		if mode=="height":changed.ball_point.y=1.0
		if mode=="expired":plan.clock=3.0
		plan._apply_lock(changed)
		check(mode+" releases stale reception lock",not plan.active.get("intercept_locked",false))
	var timing:=FirstTouchTiming.new();timing.observe(Vector3.FORWARD,0.)
	for i in [1,2,3]:timing.observe(Vector3.FORWARD.rotated(Vector3.UP,deg_to_rad(i*10.)),i*.1)
	check("gradual direction change restarts onset after total 25 degrees",timing.grade(.40).grade=="ON_TIME")
	var bridge:=Probe.new();var game:=FakeGame.new();bridge.game=game
	bridge._staged_snapshot={"actors":[],"snapshot":{"fresh":false}}
	bridge._refresh_now_impl(.2)
	check("explicit event refresh uses fresh snapshot",bridge.seen.get("fresh",false))
	bridge._staged_snapshot={"old":true};game.phase=game.Phase.PAUSED
	bridge._physics_process(.01)
	check("pause discards pending snapshot",bridge._staged_snapshot.is_empty())
	bridge.free();game.free()
	quit(1 if failed else 0)
