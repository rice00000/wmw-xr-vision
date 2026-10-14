extends MeshInstance3D
## Fades the view to black while levels change (VR comfort). Delete it for hard cuts.

var _material := StandardMaterial3D.new()


func _ready() -> void:
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.no_depth_test = true
	_material.render_priority = Material.RENDER_PRIORITY_MAX
	_material.albedo_color = Color.BLACK # start black, fade in when the first level is ready
	material_override = _material
	Events.level_changing.connect(func(_path: String) -> void: _fade_to(1.0))
	Events.level_changed.connect(func(_level: Node) -> void: _fade_to(0.0))


func _fade_to(alpha: float) -> void:
	visible = true
	var tween := create_tween()
	tween.tween_property(_material, ^"albedo_color:a", alpha, Game.FADE_TIME)
	tween.tween_callback(func() -> void: visible = alpha > 0.0) # don't pay for overdraw when clear
