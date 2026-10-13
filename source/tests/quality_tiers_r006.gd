extends SceneTree
# R006: three quality tiers in UI and code; one AA method per tier; SSIL only on high.
var failed:=0
func check(label:String,ok:bool,info:Variant="")->void:
	if not ok:failed+=1
	print("PASS " if ok else "FAIL ",label," ",info)
func _initialize()->void:call_deferred("run")
func run()->void:
	var game:Node=load("res://scenes/match.tscn").instantiate();game.test_mode=true;root.add_child(game);current_scene=game
	for i in 8:await process_frame
	var menu:Node=game.settings_menu
	check("quality menu has 3 tiers",menu.widgets.quality.item_count==3,menu.widgets.quality.item_count)
	check("RenderQuality has 3 levels",preload("res://scripts/render_quality.gd").LEVELS.size()==3)
	var vp:Viewport=game.get_window()
	var fwd:=RenderingServer.get_current_rendering_method()=="forward_plus"
	var expect:=[[Viewport.MSAA_DISABLED,false,true],[Viewport.MSAA_2X,false,false],[Viewport.MSAA_DISABLED,true,false]]
	for q in 3:
		menu.values.quality=q;menu.values.aa=1;menu.values.effects=2;menu.values.upscale=0
		menu.apply_values(false)
		for i in 3:await process_frame
		var got:=[vp.msaa_3d,vp.use_taa,vp.screen_space_aa==Viewport.SCREEN_SPACE_AA_FXAA]
		var want:Array=expect[q].duplicate();want[1]=want[1] and fwd
		check("tier %d single AA"%q,got==want,{"got":got,"want":want})
		var methods:=int(vp.msaa_3d!=Viewport.MSAA_DISABLED)+int(vp.use_taa)+int(got[2])
		check("tier %d at most one AA method"%q,methods<=1,methods)
		var env:Environment=game.get_node("MatchEnvironment").environment
		check("tier %d SSIL only on high"%q,not env.ssil_enabled or q==2,env.ssil_enabled)
	menu.values.quality=2;menu.values.aa=0;menu.apply_values(false)
	check("aa off disables all",vp.msaa_3d==Viewport.MSAA_DISABLED and not vp.use_taa and vp.screen_space_aa==Viewport.SCREEN_SPACE_AA_DISABLED)
	menu.values.quality=2;menu.cycle_quality()
	check("F2 cycle wraps 2->0",int(menu.values.quality)==0)
	print("RESULT ","PASS" if failed==0 else "FAIL %d"%failed)
	quit(1 if failed else 0)
