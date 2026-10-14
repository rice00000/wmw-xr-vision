class_name Wander
extends Node
## Moves its parent Node3D between random points around where it started, with a
## little up-and-down flutter. Speed follows the Training level for [member skill].

@export var radius := 1.2
@export var height := 0.6 ## vertical range above the start point
@export var min_speed := 0.25 ## m/s at the easiest level
@export var max_speed := 1.2 ## m/s at the hardest level
## Training skill that sets the speed. Empty = always [member min_speed].
@export var skill: StringName = &"motion"
@export var flutter := 0.05

var _body: Node3D
var _home := Vector3.ZERO
var _position := Vector3.ZERO
var _goal := Vector3.ZERO
var _speed := 0.0
var _time := 0.0


func _ready() -> void:
	_body = get_parent() as Node3D
	_home = _body.position
	_position = _home
	_speed = min_speed
	var training := Game.module(&"Training")
	if training and not skill.is_empty():
		_speed = lerpf(min_speed, max_speed, training.level(skill))
	_pick_goal()


func _physics_process(delta: float) -> void:
	_time += delta
	var to_goal := _goal - _position
	if to_goal.length() < 0.05:
		_pick_goal()
	_position += to_goal.limit_length(_speed * delta)
	_body.position = _position + Vector3.UP * sin(_time * 9.0) * flutter
	var heading := Vector3(to_goal.x, 0.0, to_goal.z)
	if heading.length() > 0.01:
		_body.basis = Basis.looking_at(heading).scaled(_body.scale)


func _pick_goal() -> void:
	_goal = _home + Vector3(randf_range(-radius, radius), randf_range(0.0, height), randf_range(-radius, radius))
