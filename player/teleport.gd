extends Node3D
## Comfort teleport: push the right stick forward to aim with the right hand,
## let go to jump there. Only floors (surfaces facing up) are valid targets.
## Delete this node if you don't want teleporting.

@export var stick_action := &"primary"
@export var max_distance := 8.0

@onready var _player := get_parent() as Player
@onready var _controller := _player.get_node(^"RightController") as XRController3D
@onready var _marker := $Marker as Node3D

var _target: Variant = null # Vector3 while aiming at a valid floor


func _physics_process(_delta: float) -> void:
	if _controller.get_vector2(stick_action).y > 0.6:
		_aim()
	elif _marker.visible:
		_marker.visible = false
		if _target != null:
			_player.place(Transform3D(_player.global_basis, _target))


func _aim() -> void:
	var from := _controller.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from - _controller.global_basis.z * max_distance)
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(query)
	var valid: bool = not hit.is_empty() and hit.normal.y > 0.7
	_target = hit.position if valid else null
	_marker.visible = valid
	if valid:
		_marker.global_position = hit.position
