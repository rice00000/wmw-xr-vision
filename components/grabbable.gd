class_name Grabbable
extends RigidBody3D
## A physics object hands can pick up. Reports "grabbed:<id>".

signal grabbed(hand: Node3D)
signal released(hand: Node3D)

enum Release {
	THROW, ## falls / flies away with the hand's velocity
	STAY, ## stays exactly where you let go (furniture, decorations)
}

@export var release_mode := Release.THROW
## Reported as "grabbed:<id>". Empty = the node name.
@export var id: StringName = &""

## The hand holding this body, or null.
var holder: Node3D


func grab(hand: Node3D) -> bool:
	if holder:
		return false
	holder = hand
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	grabbed.emit(hand)
	Events.report(&"grabbed", id if not id.is_empty() else StringName(name), {position = global_position})
	return true


func release(hand: Node3D, velocity: Vector3) -> void:
	if hand != holder:
		return
	holder = null
	if release_mode == Release.THROW:
		freeze = false
		linear_velocity = velocity
	released.emit(hand)
