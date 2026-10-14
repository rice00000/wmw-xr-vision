extends Node
## Smooth movement (left stick) and snap turning (right stick).
## Stops at walls. Delete this node for room-scale / teleport-only play.

@export var enabled := true
@export var move_speed := 1.5 ## m/s
@export var snap_degrees := 30.0
@export_range(0.0, 0.9) var deadzone := 0.25

@onready var _origin := get_parent() as XROrigin3D
@onready var _camera := _origin.get_node(^"Camera") as XRCamera3D
@onready var _left := _origin.get_node(^"LeftController") as XRController3D
@onready var _right := _origin.get_node(^"RightController") as XRController3D

var _can_turn := true


func _physics_process(delta: float) -> void:
	if not enabled:
		return
	var stick := _left.get_vector2(&"primary")
	if stick.length() > deadzone:
		_move(stick.limit_length(1.0), delta)
	_snap_turn(_right.get_vector2(&"primary"))


func _move(stick: Vector2, delta: float) -> void:
	var forward := -_camera.global_basis.z
	var right := _camera.global_basis.x
	forward.y = 0.0
	right.y = 0.0
	var motion := (right.normalized() * stick.x + forward.normalized() * stick.y) * move_speed * delta
	var knee := Vector3(_camera.global_position.x, _origin.global_position.y + 0.4, _camera.global_position.z)
	var query := PhysicsRayQueryParameters3D.create(knee, knee + motion + motion.normalized() * 0.25)
	if _origin.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		_origin.global_position += motion


func _snap_turn(stick: Vector2) -> void:
	if absf(stick.x) < deadzone or absf(stick.x) < absf(stick.y):
		_can_turn = true
		return
	if not _can_turn:
		return
	_can_turn = false
	var pivot := _camera.global_position
	pivot.y = _origin.global_position.y
	var turn := Transform3D(Basis(Vector3.UP, deg_to_rad(snap_degrees) * -signf(stick.x)), Vector3.ZERO)
	_origin.global_transform = (turn * _origin.global_transform.translated(-pivot)).translated(pivot)
