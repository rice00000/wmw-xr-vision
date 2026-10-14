class_name Hand
extends Area3D
## A hand. Grabs Grabbable bodies and touches anything that has a touch(hand) method.
##
## Driven by its parent XRController3D, or by DesktopControls when there's no headset.
## Interaction is duck-typed: objects don't need to know about hands, they just
## implement touch() (see Touchable) or extend Grabbable.

@export var grab_action := &"grip_click"
@export var throw_strength := 1.2

## The body currently held, or null.
var held: Grabbable

var _controller: XRController3D
var _offset := Transform3D.IDENTITY
var _velocity := Vector3.ZERO
var _last_position := Vector3.ZERO


func _ready() -> void:
	add_to_group(&"hand")
	area_entered.connect(_on_area_entered)
	_controller = get_parent() as XRController3D
	if _controller:
		_controller.button_pressed.connect(_on_button_pressed)
		_controller.button_released.connect(_on_button_released)


func grab() -> void:
	if held:
		return
	var body := _nearest_grabbable()
	if body == null or not body.grab(self):
		return
	held = body
	_offset = global_transform.affine_inverse() * body.global_transform
	_last_position = body.global_position
	_velocity = Vector3.ZERO
	pulse()


func release() -> void:
	if held and is_instance_valid(held):
		held.release(self, _velocity * throw_strength)
	held = null


## Short controller vibration. Does nothing on desktop.
func pulse(strength := 0.5, duration := 0.08) -> void:
	if _controller:
		_controller.trigger_haptic_pulse(&"haptic", 0.0, strength, duration, 0.0)


func _physics_process(delta: float) -> void:
	if held == null:
		return
	if not is_instance_valid(held):
		held = null
		return
	held.global_transform = global_transform * _offset
	_velocity = _velocity.lerp((held.global_position - _last_position) / delta, 0.4)
	_last_position = held.global_position


func _on_area_entered(area: Area3D) -> void:
	if area.has_method(&"touch") and area.touch(self):
		pulse(0.3)


func _on_button_pressed(action: String) -> void:
	if action == grab_action:
		grab()


func _on_button_released(action: String) -> void:
	if action == grab_action:
		release()


func _nearest_grabbable() -> Grabbable:
	var best: Grabbable = null
	var best_distance := INF
	for body in get_overlapping_bodies():
		if body is Grabbable and body.holder == null:
			var distance := global_position.distance_squared_to(body.global_position)
			if distance < best_distance:
				best = body
				best_distance = distance
	return best
