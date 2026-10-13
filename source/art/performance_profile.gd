extends RefCounted
static func apply_stadium(environment:Environment,viewport:Viewport,settings:Dictionary,forward:bool)->void:
 # Keep a full-size atlas for long-range stadium shadows; respect the effects menu.
 environment.ssao_enabled=forward and int(settings.effects)>0
 environment.ssil_enabled=forward and int(settings.effects)==2
 environment.glow_enabled=forward and int(settings.effects)>0
 viewport.positional_shadow_atlas_size=4096
 RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH if int(settings.quality)>=2 else RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
# Presentation settings only. Keep the full-stadium profile separate from the small pitch.
static func apply_small(environment:Environment,viewport:Viewport,settings:Dictionary,forward:bool)->void:
 var effects:int=int(settings.effects)
 var quality:int=int(settings.quality)
 environment.ssao_enabled=forward and effects>0
 environment.ssil_enabled=forward and effects==2
 environment.glow_enabled=forward and effects>0
 viewport.positional_shadow_atlas_size=4096 if int(settings.shadows)==2 else 2048
 RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH if quality>=2 else RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
