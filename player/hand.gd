class_name Hand
extends Area3D
## A hand. Grabs Grabbable bodies and touches anything that has a touch(hand) method.
##
## Driven by its parent XRController3D.
## Interaction is duck-typed: objects don't need to know about hands, they just
## implement touch() (see Touchable) or extend Grabbable.
##
## Whatever this hand could use right now lights up through [Hover]: the
## grabbable that [method grab] would pick, and the nearest touchable within
## [member reach]. Nothing else, so the light never says more than "near you".
## While the tree is paused (wrist menu open) the hand still tracks, but grabs,
## touches and hover stop; the menu does its own, poking with [method poke_point].
## A held object waits where it was and is let go of (gently) only once the
## world runs again, so nothing is thrown by a menu.

## Haptic patterns for Events.feedback kinds: [delay s, strength 0-1, duration s].
const PATTERNS := {
	&"good": [[0.0, 0.5, 0.05], [0.12, 0.5, 0.05]], # short double tick
	&"bad": [[0.0, 0.3, 0.35]], # one longer, soft buzz
	&"reward": [[0.0, 0.35, 0.07], [0.15, 0.6, 0.07], [0.3, 0.9, 0.09]], # rising triple
}

@export var grab_action := &"grip_click"
@export var throw_strength := 1.2
## How close (m) a touchable has to be to light up as "about to be touched".
@export var reach := 0.16
## How far in front of the hand centre (along the controller's -Z) the fingertip is.
@export var poke_reach := 0.06

## The body currently held, or null.
var held: Grabbable
## Strength of the last vibration actually sent, after Settings.haptics; a test seam.
var last_pulse := 0.0

@onready var _controller := get_parent() as XRController3D

var _offset := Transform3D.IDENTITY
var _velocity := Vector3.ZERO
var _last_position := Vector3.ZERO
var _reach: Area3D
var _hovered: Array[Node3D] = []
var _was_paused := false
var _release_pending := false # grip let go while paused


func _ready() -> void:
	add_to_group(&"hand")
	area_entered.connect(_on_area_entered)
	_controller.button_pressed.connect(_on_button_pressed)
	_controller.button_released.connect(_on_button_released)
	_reach = Area3D.new()
	_reach.name = "Reach"
	_reach.monitorable = false
	_reach.collision_layer = 0
	_reach.collision_mask = collision_mask
	var shape := CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	(shape.shape as SphereShape3D).radius = reach
	_reach.add_child(shape)
	add_child(_reach)


func _exit_tree() -> void:
	_set_hover([])


func grab() -> void:
	if held or get_tree().paused:
		return
	if hold(_nearest_grabbable()):
		pulse()


## Takes [param body] into this hand where it is, as if it had just been grabbed.
## Used by grab() and by things that hand the child an object (placement).
func hold(body: Grabbable) -> bool:
	if held or body == null or not body.grab(self):
		return false
	held = body
	_offset = global_transform.affine_inverse() * body.global_transform
	_last_position = body.global_position
	_velocity = Vector3.ZERO
	_set_hover([])
	return true


func release() -> void:
	_release_pending = false
	if held and is_instance_valid(held):
		held.release(self, _velocity * throw_strength)
	held = null


## The fingertip: where menus and buttons should test for a poke.
func poke_point() -> Vector3:
	return global_position - global_basis.z * poke_reach


## Short controller vibration, scaled by the haptics setting.
func pulse(strength := 0.5, duration := 0.08) -> void:
	var scaled := strength * float(Settings.value(&"haptics"))
	if scaled <= 0.0:
		return
	last_pulse = scaled
	if XRServer.primary_interface: # no controller to shake headless
		_controller.trigger_haptic_pulse(&"haptic", 0.0, scaled, duration, 0.0)


## Plays the haptic pattern for a feedback kind (good / bad / reward).
func play(kind: StringName) -> void:
	for beat: Array in PATTERNS.get(kind, []):
		if beat[0] <= 0.0:
			pulse(beat[1], beat[2])
		else:
			get_tree().create_timer(beat[0]).timeout.connect(pulse.bind(beat[1], beat[2]))


## True when this hand is lighting [param node] up.
func is_hovering(node: Node3D) -> bool:
	return _hovered.has(node)


func _physics_process(delta: float) -> void:
	if get_tree().paused:
		_set_hover([])
		_velocity = Vector3.ZERO
		_was_paused = true
		return
	if held and (not is_instance_valid(held) or not held.is_inside_tree()):
		held = null # freed or taken out of the world (put away, a reload)
	if held == null:
		_release_pending = false
		_was_paused = false
		_update_hover()
		return
	held.global_transform = global_transform * _offset
	if _was_paused: # the hand moved while the world stood still: that is not a throw
		_was_paused = false
		_velocity = Vector3.ZERO
	else:
		_velocity = _velocity.lerp((held.global_position - _last_position) / delta, 0.4)
	_last_position = held.global_position
	if _release_pending:
		release()
	_update_hover()


func _update_hover() -> void:
	var wanted: Array[Node3D] = []
	var body := _nearest_grabbable() if held == null else null
	if body:
		wanted.append(body)
	var touchable := _nearest_touchable()
	if touchable:
		wanted.append(touchable)
	_set_hover(wanted)


func _set_hover(wanted: Array[Node3D]) -> void:
	for i in range(_hovered.size() - 1, -1, -1):
		if not is_instance_valid(_hovered[i]):
			_hovered.remove_at(i) # freed while lit (put away, caught)
	for node in _hovered:
		if not wanted.has(node) and not _other_hand_hovers(node):
			Hover.set_hovered(node, false)
	for node in wanted:
		if not _hovered.has(node):
			Hover.set_hovered(node, true)
	_hovered = wanted


func _other_hand_hovers(node: Node3D) -> bool:
	for hand in get_tree().get_nodes_in_group(&"hand"):
		if hand != self and hand.has_method(&"is_hovering") and hand.is_hovering(node):
			return true
	return false


func _on_area_entered(area: Area3D) -> void:
	if get_tree().paused:
		return
	if area.has_method(&"touch") and area.touch(self):
		pulse(0.3)


func _on_button_pressed(action: String) -> void:
	if action == grab_action:
		if get_tree().paused:
			_release_pending = false # gripped again before the menu closed
		else:
			grab()


func _on_button_released(action: String) -> void:
	if action == grab_action:
		if get_tree().paused:
			_release_pending = held != null
		else:
			release()


func _nearest_grabbable() -> Grabbable:
	var best: Grabbable = null
	var best_distance := INF
	for body in get_overlapping_bodies():
		if body is Grabbable and body.holder == null and body.is_inside_tree():
			var distance := global_position.distance_squared_to(body.global_position)
			if distance < best_distance:
				best = body
				best_distance = distance
	return best


func _nearest_touchable() -> Area3D:
	var best: Area3D = null
	var best_distance := INF
	for area in _reach.get_overlapping_areas():
		if area.has_method(&"touch") and area.is_visible_in_tree() \
				and not (area.has_method(&"can_touch") and not area.can_touch(self)):
			var distance := global_position.distance_squared_to(area.global_position)
			if distance < best_distance:
				best = area
				best_distance = distance
	return best
