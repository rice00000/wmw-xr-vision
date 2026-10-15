extends Node
## Vision module (autoload "Vision"): applies a VisionProfile on top of each level's
## look (contrast, colour, fog) and outlines nodes in the "vision_target" group.
## Levels keep their own Environment; this works on a copy, so nothing leaks between levels.

const TARGET_GROUP := &"vision_target"

## Active profile. Null = the level's normal look.
var profile: VisionProfile

var _base: Environment # the level's own environment, never modified
var _env: Environment # working copy on screen
var _outline := ShaderMaterial.new()


func _ready() -> void:
	_outline.shader = preload("res://shared/outline.gdshader")
	Events.level_changed.connect(_on_level_changed)
	get_tree().node_added.connect(_on_node_added)


func apply(new_profile: VisionProfile) -> void:
	profile = new_profile
	_refresh()


## Turn [param p] on, or back off when it's already active.
func toggle(p: VisionProfile) -> void:
	apply(null if profile == p else p)


func _on_level_changed(_level: Node) -> void:
	var world := get_viewport().find_world_3d()
	_base = world.environment
	_env = _base.duplicate() if _base else null
	world.environment = _env
	_refresh()


func _refresh() -> void:
	var p := profile if profile else VisionProfile.new()
	if _env:
		_env.adjustment_enabled = _base.adjustment_enabled or p.changes_colors()
		_env.adjustment_brightness = _base.adjustment_brightness * p.brightness
		_env.adjustment_contrast = _base.adjustment_contrast * p.contrast
		_env.adjustment_saturation = _base.adjustment_saturation * p.saturation
		_env.adjustment_color_correction = p.color_correction if p.color_correction else _base.adjustment_color_correction
		_env.fog_density = _base.fog_density * p.fog
	_outline.set_shader_parameter(&"color", p.highlight_color)
	for node in get_tree().get_nodes_in_group(TARGET_GROUP):
		_set_outline(node, p.highlight_targets)


func _on_node_added(node: Node) -> void:
	if profile and profile.highlight_targets and node.is_in_group(TARGET_GROUP):
		_set_outline.call_deferred(node, true) # children aren't in yet


func _set_outline(node: Node, on: bool) -> void:
	var meshes := node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		meshes.append(node)
	for mesh: MeshInstance3D in meshes:
		mesh.material_overlay = _outline if on else null
