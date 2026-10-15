class_name Highlight
extends Node
## Makes [b]one[/b] object stand out: an outline, a brief flash, a lift, a bob.
## Child of the Node3D it emphasises.
##
## The Vision module outlines every node in the "vision_target" group in a single
## colour at once — that is a spirit ability the child turns on. This is the
## per-object counterpart task feedback needs: green on the right pick, red on
## the wrong one, an outline or a wobble on just the target when a hint is due.
##
## It remembers any material_overlay that was already there (Vision's, say) and
## puts it back on [method clear].

const SHADER := preload("res://shared/outline.gdshader")

@export var width := 0.016

var _target: Node3D
var _meshes: Array[MeshInstance3D] = []
var _previous: Array[Material] = []
var _material: ShaderMaterial
var _outlined := false
var _bob: Tween
var _move: Tween
var _rest := Vector3.ZERO
var _lifted := false


func _ready() -> void:
	_target = get_parent() as Node3D
	if _target == null:
		push_warning("[Highlight] Parent is not a Node3D.")
		return
	_meshes.assign(_target.find_children("*", "MeshInstance3D", true, false))
	if _target is MeshInstance3D:
		_meshes.append(_target)


## Outline the object until [method clear].
func outline(color: Color) -> void:
	if _meshes.is_empty() or not _renderable():
		return
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		_material.set_shader_parameter(&"width", width)
	_material.set_shader_parameter(&"color", color)
	if _outlined:
		return
	_outlined = true
	_previous.clear()
	for mesh in _meshes:
		_previous.append(mesh.material_overlay)
		mesh.material_overlay = _material


func clear() -> void:
	if not _outlined or _previous.is_empty():
		return
	_outlined = false
	for i in _meshes.size():
		_meshes[i].material_overlay = _previous[i] if i < _previous.size() else null
	_previous.clear()


## Outline for [param seconds], then go back to how it was.
func flash(color: Color, seconds := 0.9) -> void:
	outline(color)
	if not is_inside_tree():
		return
	await get_tree().create_timer(seconds).timeout
	clear()


## Raise the object clear of the clutter so its edges can be seen whole.
func lift(height := 0.25, seconds := 0.35) -> void:
	if _target == null or _lifted:
		return
	_lifted = true
	_rest = _target.position
	_hold_still()
	_move = _target.create_tween()
	_move.set_trans(Tween.TRANS_CUBIC)
	_move.tween_property(_target, ^"position:y", _rest.y + height, seconds)


## Small continuous movement. Motion made newly sighted people better at telling
## objects apart (design doc ref [2]), so this is the middle rung of help, not a
## difficulty setting.
func wobble(amplitude := 0.035, seconds := 0.6) -> void:
	if _target == null or _bob != null:
		return
	_rest = _target.position
	_hold_still()
	_bob = _target.create_tween().set_loops()
	_bob.set_trans(Tween.TRANS_SINE)
	_bob.tween_property(_target, ^"position:y", _rest.y + amplitude, seconds * 0.5)
	_bob.tween_property(_target, ^"position:y", _rest.y, seconds * 0.5)


## Stop moving and go back where it started.
func settle() -> void:
	if _bob:
		_bob.kill()
		_bob = null
	if _move:
		_move.kill()
		_move = null
	if _target and (_lifted or _rest != Vector3.ZERO):
		_target.position = _rest
	_lifted = false


## The dummy renderer in --headless has no material to hang a shader on, so
## outlining is skipped there. Everything else about a round behaves the same,
## which keeps the smoke test's output free of errors it cannot act on.
func _renderable() -> bool:
	return DisplayServer.get_name() != "headless"


## Frozen bodies can be tweened; live ones would fight the solver.
func _hold_still() -> void:
	if _target is RigidBody3D:
		var body := _target as RigidBody3D
		body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		body.freeze = true
