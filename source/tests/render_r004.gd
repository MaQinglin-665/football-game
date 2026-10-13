extends SceneTree
# R004 render smoke: run under a real RenderingDevice (e.g. xvfb + lavapipe) to compile
# Forward+ shaders. Headless (dummy) only checks parsing. Not an FPS measurement.
var failed:=0
func check(label:String,ok:bool,info:Variant="")->void:
	if not ok:failed+=1
	print("PASS " if ok else "FAIL ",label," ",info)
func _initialize()->void:call_deferred("run")
func run()->void:
	var g:Node=load("res://scenes/match.tscn").instantiate();root.add_child(g);current_scene=g
	for i in 30:await process_frame
	g.settings_menu.apply_values(false)
	for i in 60:await process_frame
	var method:=RenderingServer.get_current_rendering_method()
	var fx:Dictionary=g.get_node("MatchEnvironment").get_meta("forward_plus_fx",{})
	print("RENDER ",method," ",RenderingServer.get_video_adapter_name()," FX ",fx)
	var env:Environment=g.get_node("MatchEnvironment").environment
	if method=="forward_plus":
		check("AgX tonemap on Forward+",env.tonemap_mode==Environment.TONE_MAPPER_AGX)
		check("fx report forward_plus",bool(fx.get("forward_plus",false)))
	else:
		check("fallback keeps pre-R004 tonemap (no AgX)",env.tonemap_mode!=Environment.TONE_MAPPER_AGX,method)
	var turf:ShaderMaterial=g.services.materials.slots.pitch_grass
	check("mowing band 5.25m (filtered turf)",is_equal_approx(float(turf.get_shader_parameter("mowing_band_m")),5.25),turf.get_shader_parameter("mowing_band_m"))
	var art:Node=g.find_child("*Integration*",true,false)
	if DisplayServer.get_name()!="headless" and art!=null and art.get("turf")!=null:
		check("art turf stripe 5.25m",is_equal_approx(float(art.turf.get_shader_parameter("stripe_width")),5.25),art.turf.get_shader_parameter("stripe_width"))
	print("RESULT ","PASS" if failed==0 else "FAIL %d"%failed)
	quit(1 if failed else 0)
