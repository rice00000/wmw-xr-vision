extends Node
## Mouse & keyboard fallback when no headset is running (WASD lives in Locomotion).
##
## Mouse looks around. The right hand follows the crosshair, so pointing at
## something "touches" it. Hold left mouse to grab, H asks for help, Esc frees the mouse.
## Removes itself in XR.

@export var mouse_sensitivity := 0.003
@export var eye_height := 1.3 ## a child's eye height, in meters
@export var reach := 2.5

@onready var _origin := get_parent() as XROrigin3D
@onready var _camera := _origin.get_node(^"Camera") as XRCamera3D
@onready var _left := _origin.get_node(^"LeftController") as XRController3D
@onready var _right := _origin.get_node(^"RightController") as XRController3D
@onready var _hand := _right.get_node(^"Hand") as Hand

var _hand_distance := 1.2
var _ignore: Array[RID] = []


func _ready() -> void:
	if Game.is_xr:
		queue_free()
		return
	_camera.position.y = eye_height
	_left.get_node(^"Hand").visible = false # only its wrist readout is useful on a flat screen
	for area: Area3D in [_hand, _left.get_node(^"Hand"), _camera.get_node(^"HeadSensor")]:
		_ignore.append(area.get_rid())
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and captured:
		_origin.rotate_y(-event.relative.x * mouse_sensitivity)
		_camera.rotation.x = clampf(_camera.rotation.x - event.relative.y * mouse_sensitivity, -1.4, 1.4)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not captured:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.pressed:
			_hand.grab()
		else:
			_hand.release()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_H: Events.report(&"asked", &"help")


func _physics_process(_delta: float) -> void:
	var from := _camera.global_position
	var forward := -_camera.global_basis.z
	if _hand.held == null:
		_hand_distance = _crosshair_distance(from, forward)
	_right.global_transform = Transform3D(_camera.global_basis, from + forward * _hand_distance)
	# Left hand sits in the lower-left of the view so its wrist readout is visible.
	_left.global_transform = _camera.global_transform * Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(-0.3, -0.2, -0.6))


## Distance to the first touchable / solid thing under the crosshair (1.2 m when nothing).
func _crosshair_distance(from: Vector3, forward: Vector3) -> float:
	var space := _origin.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, from + forward * reach)
	query.collide_with_areas = true
	var ignore := _ignore.duplicate()
	for _i in 4:
		query.exclude = ignore
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			break
		if hit.collider is Area3D and not hit.collider.has_method(&"touch"):
			ignore.append(hit.rid) # e.g. a Zone volume: look through it
			continue
		return from.distance_to(hit.position)
	return 1.2
