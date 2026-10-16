class_name ViewportUI
extends Node3D
## A normal Control scene displayed in XR. Rays become viewport mouse input;
## no physics/colliders, so buttons still work while the game is paused.

@onready var _size: Vector2 = ($Screen.mesh as QuadMesh).size
@onready var viewport := $Viewport as SubViewport
@onready var content := $Viewport/Panel as Control

var _pointers: Array[UIPointer] = []
var _active: UIPointer
var _inside := false
var _last := Vector2.ZERO


func _ready() -> void:
	add_to_group(&"viewport_ui")
	visibility_changed.connect(_on_visibility_changed)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = viewport.get_texture()
	$Screen.material_override = material
	for controller: XRController3D in get_parent().find_children("*", "XRController3D", true, false):
		var pointer := UIPointer.new()
		pointer.name = "%s%sPointer" % [controller.name, name]
		pointer.controller = controller
		get_parent().add_child(pointer)
		_pointers.append(pointer)


func _exit_tree() -> void:
	for pointer in _pointers:
		if is_instance_valid(pointer):
			pointer.queue_free()


func _process(_delta: float) -> void:
	var hits: Dictionary[UIPointer, Vector2] = {}
	var click: UIPointer = null
	for pointer in _pointers:
		var pressed := pointer.sample(visible)
		if not pointer.visible:
			continue
		var inverse := global_transform.affine_inverse()
		var origin := inverse * pointer.global_position
		var direction := inverse.basis * -pointer.global_basis.z
		var distance := -origin.z / direction.z if origin.z > 0.0 and direction.z < -0.0001 else INF
		var hit := origin + direction * distance if distance < UIPointer.LENGTH else Vector3.INF
		var on_panel := absf(hit.x) <= _size.x * 0.5 and absf(hit.y) <= _size.y * 0.5
		pointer.draw_ray(distance if on_panel else UIPointer.LENGTH, on_panel)
		if on_panel:
			hits[pointer] = Vector2(hit.x / _size.x + 0.5, 0.5 - hit.y / _size.y) * Vector2(viewport.size)
			if pressed and click == null:
				click = pointer
	if click:
		_active = click
	elif not hits.has(_active):
		_active = hits.keys().back() if not hits.is_empty() else null
	if _active == null:
		if _inside:
			viewport.notify_mouse_exited()
			_inside = false
		return
	if not _inside:
		viewport.notify_mouse_entered()
		_inside = true
	var point: Vector2 = hits[_active]
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	motion.relative = point - _last
	viewport.push_input(motion, true)
	_last = point
	if click:
		# A trigger edge is one complete UI click. Buttons don't repeat or drag.
		for down in [true, false]:
			var event := InputEventMouseButton.new()
			event.position = point
			event.global_position = point
			event.button_index = MOUSE_BUTTON_LEFT
			event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
			event.pressed = down
			viewport.push_input(event, true)
		_active.controller.get_node(^"Hand").pulse()


func place() -> void:
	var camera := get_parent().get_node(^"Camera") as Node3D
	var forward := -camera.global_basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	global_position = camera.global_position + forward * 0.95 + Vector3.DOWN * 0.17
	look_at(global_position + (global_position - camera.global_position).normalized())


## Observing and aiming at controls uses their actual laid-out rectangles.
func buttons() -> Array[Node]:
	return content.find_children("*", "Button", true, false).filter(
		func(button: Button) -> bool: return button.is_visible_in_tree() and not button.disabled)


func button_position(button: Button) -> Vector3:
	var point := button.get_global_rect().get_center() / Vector2(viewport.size)
	return global_transform * Vector3((point.x - 0.5) * _size.x, (0.5 - point.y) * _size.y, 0.001)


func _on_visibility_changed() -> void:
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if visible else SubViewport.UPDATE_DISABLED
	if not visible:
		for pointer in _pointers:
			pointer.sample(false)
		if _inside:
			viewport.notify_mouse_exited()
			_inside = false
