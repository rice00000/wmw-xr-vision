class_name Contrast
extends Node
## Sets how far its parent's colour stands out from the surface behind it, as
## [b]Weber contrast[/b]: c = (L_background - L_target) / L_background, with the
## target the darker of the two. c = 1 is as dark as the object can go, c = 0 is
## the background's own luminance (invisible). Child of the Node3D it grades.
##
## The Vision module's contrast is a whole-scene Environment grade, which is a
## spirit ability: it dims the subtitles and the guide's cues along with
## everything else, and it cannot say what contrast a child actually failed at.
## Difficulty needs this instead — one object, one number, written into the round's
## log line next to the result.
##
## Emission is switched off while graded: a glowing object is visible whatever its
## albedo says, which would make the number meaningless.

const LUMA := Vector3(0.2126, 0.7152, 0.0722) # Rec. 709 luminance weights

## Linear luminance of what the object sits on. It has to match the actual
## surface, so keep it in step with the floor or table material.
@export var background_luminance := 0.34
## Grade on entering the tree, for objects placed outside a task.
@export var apply_on_ready := false
@export_range(0.0, 1.0) var contrast := 0.8

var _meshes: Array[MeshInstance3D] = []
var _originals: Array[Material] = []
var _graded: Array[StandardMaterial3D] = []


func _ready() -> void:
	var target := get_parent() as Node3D
	if target == null:
		push_warning("[Contrast] Parent is not a Node3D.")
		return
	_meshes.assign(target.find_children("*", "MeshInstance3D", true, false))
	if target is MeshInstance3D:
		_meshes.append(target)
	if apply_on_ready:
		apply(contrast)


## Grades the object to [param weber] contrast against [member background_luminance].
func apply(weber: float) -> void:
	contrast = clampf(weber, 0.0, 1.0)
	var target_luminance := background_luminance * (1.0 - contrast)
	for i in _meshes.size():
		var material := _material_for(i)
		if material == null:
			continue
		material.albedo_color = _at_luminance(material.albedo_color, target_luminance)
		material.emission_enabled = false


## Linear luminance the object should sit at for the contrast last applied.
func intended_luminance() -> float:
	return background_luminance * (1.0 - contrast)


## Linear luminance the object's albedo actually came out at. Reads the material
## back, so it checks the grading rather than restating the intent.
func applied_luminance() -> float:
	if _graded.is_empty() or _graded[0] == null:
		return NAN
	var linear := _graded[0].albedo_color.srgb_to_linear()
	return Vector3(linear.r, linear.g, linear.b).dot(LUMA)


## Puts the object's authored materials back.
func reset() -> void:
	for i in _meshes.size():
		if i < _originals.size():
			_meshes[i].set_surface_override_material(0, _originals[i])
	_graded.clear()
	_originals.clear()


## Own copy of surface 0's material, so grading never leaks into the shared
## resource other objects use.
func _material_for(index: int) -> StandardMaterial3D:
	while _graded.size() <= index:
		_graded.append(null)
		_originals.append(null)
	if _graded[index]:
		return _graded[index]
	var mesh := _meshes[index]
	var source := mesh.get_surface_override_material(0)
	if source == null and mesh.mesh and mesh.mesh.get_surface_count() > 0:
		source = mesh.mesh.surface_get_material(0)
	var copy := source.duplicate() as StandardMaterial3D if source is StandardMaterial3D else StandardMaterial3D.new()
	_originals[index] = mesh.get_surface_override_material(0)
	_graded[index] = copy
	mesh.set_surface_override_material(0, copy)
	return copy


## Same hue, scaled to [param luminance] (linear), back in sRGB.
func _at_luminance(color: Color, luminance: float) -> Color:
	var linear := color.srgb_to_linear()
	var current := Vector3(linear.r, linear.g, linear.b).dot(LUMA)
	if current <= 0.0001:
		linear = Color(luminance, luminance, luminance)
	else:
		var scale := luminance / current
		linear = Color(linear.r * scale, linear.g * scale, linear.b * scale)
	return Color(minf(linear.r, 1.0), minf(linear.g, 1.0), minf(linear.b, 1.0), color.a).linear_to_srgb()
