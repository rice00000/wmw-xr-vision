class_name Placeable
extends Grabbable
## Furniture, carried the way it will stand: upright, on whatever is under the
## hand (floor, table), turned only by a twist of the wrist, in steps that tick
## in the hand. Let go and it stays exactly as shown, reporting "placed:<id>".
## Pieces lower than [constant REACH] get a handle that tall, so a seated child
## never has to reach the floor for a rug. See DecorLayout.
## Convention: the origin is at the bottom of the model.

## Turns snap to this, so furniture stands square to the world and to each other.
const TURN_STEP := PI / 4.0
## How high above its base a hand can still take it (m).
const REACH := 0.6

## False: hangs from the hand instead of standing on what is below (a picture frame).
@export var snap_to_floor := true

var _step := 0


func _init() -> void:
	release_mode = Release.STAY


func _ready() -> void:
	released.connect(func(_hand: Node3D) -> void: Events.report(&"placed", id, {position = global_position}))
	_add_handle()


func grab(hand: Node3D) -> bool:
	_step = _step_of(global_basis)
	return super(hand)


func carry(hand: Transform3D) -> void:
	var step := _step_of((hand * grip).basis)
	if step != _step:
		_step = step
		if holder.has_method(&"pulse"):
			holder.pulse(0.2, 0.03)
	var turn := Basis(Vector3.UP, step * TURN_STEP)
	var xform := Transform3D(turn, hand.origin - turn * grip.affine_inverse().origin) # the grip point stays in the hand
	if snap_to_floor:
		var from := Vector3(xform.origin.x, hand.origin.y, xform.origin.z)
		var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 5.0)
		query.exclude = [get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			xform.origin.y = hit.position.y
	global_transform = xform


## The nearest turn step to [param pose], by its twist about the vertical alone.
static func _step_of(pose: Basis) -> int:
	var q := pose.get_rotation_quaternion()
	return posmod(roundi(2.0 * atan2(q.y, q.w) / TURN_STEP), roundi(TAU / TURN_STEP))


func _add_handle() -> void:
	var box := AABB() # from the origin, which is on the bottom
	for part: CollisionShape3D in find_children("*", "CollisionShape3D", false, false):
		box = box.merge(part.transform * part.shape.get_debug_mesh().get_aabb())
	if box.end.y >= REACH:
		return
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = Vector3(box.size.x, REACH, box.size.z)
	shape.position = Vector3(box.get_center().x, REACH * 0.5, box.get_center().z)
	var handle := Area3D.new()
	handle.name = "Handle"
	handle.monitoring = false
	handle.add_child(shape)
	add_child(handle)
