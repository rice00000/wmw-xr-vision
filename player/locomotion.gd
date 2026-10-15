extends Node
## Smooth movement (left stick) and snap turning (right stick).
## Stops at walls. Delete this node for room-scale / teleport-only play.
##
## Three things must all allow stick walking: [member enabled] (the level's seated
## switch), the child's Settings.move_mode (&"walk"; &"teleport" walks only by
## teleport) and the world not being paused (wrist menu open). Snap turning follows
## Settings.turn_degrees and stops only while paused. Both settings are read live.

@export var enabled := true
@export var move_speed := 1.5 ## m/s
@export_range(0.0, 0.9) var deadzone := 0.25

@onready var _origin := get_parent() as XROrigin3D
@onready var _camera := _origin.get_node(^"Camera") as XRCamera3D
@onready var _left := _origin.get_node(^"LeftController") as XRController3D
@onready var _right := _origin.get_node(^"RightController") as XRController3D

var _can_turn := true


func _physics_process(delta: float) -> void:
	step(_left.get_vector2(&"primary"), _right.get_vector2(&"primary"), delta)


## One frame of movement from the two sticks. Split out so it can be driven
## without controllers (tests, a future keyboard rig).
func step(move: Vector2, turn: Vector2, delta: float) -> void:
	if can_walk() and move.length() > deadzone:
		_move(move.limit_length(1.0), delta)
	if can_turn():
		_snap_turn(turn)


func can_walk() -> bool:
	return enabled and String(Settings.value(&"move_mode")) == "walk" and not get_tree().paused


func can_turn() -> bool:
	return not get_tree().paused


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
	var degrees := float(Settings.value(&"turn_degrees"))
	var turn := Transform3D(Basis(Vector3.UP, deg_to_rad(degrees) * -signf(stick.x)), Vector3.ZERO)
	_origin.global_transform = (turn * _origin.global_transform.translated(-pivot)).translated(pivot)
