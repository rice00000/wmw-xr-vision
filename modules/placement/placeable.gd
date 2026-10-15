class_name Placeable
extends Node
## Child of a Grabbable (release mode STAY) that turns it into decoration:
## when let go it settles upright on whatever is below (floor, table) and reports
## "placed:<item_id>". Furniture scenes from the shop carry one; see DecorLayout.
## Convention: the furniture's origin is at the bottom of the model.

## Empty = the Grabbable's id.
@export var item_id: StringName = &""
@export var snap_to_floor := true
## > 0 snaps the position to a grid of this size (meters).
@export var grid := 0.0

@onready var _body := get_parent() as Grabbable


func _ready() -> void:
	if item_id.is_empty():
		item_id = _body.id
	_body.released.connect(_on_released)


func _on_released(_hand: Node3D) -> void:
	settle()
	Events.report(&"placed", item_id, {position = _body.global_position})


## Stands the body upright on whatever is below it, without reporting anything.
func settle() -> void:
	var xform := Transform3D(Basis(Vector3.UP, _body.global_rotation.y), _body.global_position)
	if grid > 0.0:
		xform.origin.x = snappedf(xform.origin.x, grid)
		xform.origin.z = snappedf(xform.origin.z, grid)
	if snap_to_floor:
		var from := xform.origin + Vector3.UP * 0.1
		var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 5.0)
		query.exclude = [_body.get_rid()]
		var hit := _body.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			xform.origin.y = hit.position.y
	_body.global_transform = xform
