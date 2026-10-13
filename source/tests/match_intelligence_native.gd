extends "res://tests/ai_match_review.gd"
var picture_at:float=8.0
var picture_busy:bool=false
var picture_count:int=0
func begin()->void:
	super.begin()
	if camera:
		root.mode=Window.MODE_WINDOWED
		root.size=Vector2i(1280,720)
		camera.position=Vector3(0,23,30)
		camera.look_at(Vector3.ZERO)
func observe(dt:float)->void:
	super.observe(dt)
	if finished or not camera:return
	if elapsed>=picture_at and not picture_busy:
		picture_busy=true;picture_at+=8.0
		capture_play()
func capture_play()->void:
	await RenderingServer.frame_post_draw
	picture_count+=1
	root.get_texture().get_image().save_png(output+"_%02d.png" % picture_count)
	picture_busy=false
