extends "res://art/scripts/athlete.gd"
func material(key:String)->Material:
 var m=super.material(key)
 if key=="jersey":m.set_shader_parameter("color",Color("e5ce39"));m.set_shader_parameter("kind",4)
 elif key in ["sock","shorts","trim"]:m.set_shader_parameter("color",Color("18232b"))
 return m
func animate_official(speed:float,gesture:String,age:float,clock:float)->void:
 var clip="Run" if speed>.35 else "Idle"
 if player.current_animation!=clip:player.play(clip,.18)
 elif not player.is_playing():player.play()
 player.speed_scale=clampf(speed/4.,.65,1.5) if speed>.35 else 1.
 var pace=clampf(speed/5.,0.,1.)
 for side in ["L","R"]:
  var sign_side=-1. if side=="L" else 1.
  var arm=skeleton.find_bone("upper_arm."+side)
  var forearm=skeleton.find_bone("forearm."+side)
  var swing=sin(clock*8.)*sign_side*.45*pace
  var target=Quaternion(Vector3.RIGHT,swing)*Quaternion(Vector3.FORWARD,sign_side*.10)
  if age>0. and side=="R":target=Quaternion(Vector3.RIGHT,-2.8 if gesture in ["offside","indirect_free_kick"] else -1.35)
  skeleton.set_bone_pose_rotation(arm,skeleton.get_bone_pose_rotation(arm).slerp(target,.3))
  skeleton.set_bone_pose_rotation(forearm,Quaternion(Vector3.RIGHT,-.30-.6*pace))
 visual.rotation.x=-.06*pace
