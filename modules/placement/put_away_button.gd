class_name PutAwayButton
extends Touchable
## The small "put away" button a [DecorLayout] floats over the item a hand is
## holding. The hand that holds the item cannot press it (it would be pressed by
## accident while carrying); the other hand can. Its look is
## content/effects/put_away_icon.tscn, instanced as the child "Visual".

signal pressed(item: Node3D)

## Height above the top of the item.
@export var gap := 0.12

var item: Node3D

var _top := 0.0


## Floats over [param node] until it is let go; null hides the button.
func show_for(node: Node3D) -> void:
	item = node
	visible = node != null
	set_deferred(&"monitorable", visible) # may be called from inside a touch
	if node:
		_top = DecorLayout._local_bounds(node).end.y
		_follow()


func can_touch(hand: Node3D) -> bool:
	if item == null or not is_instance_valid(item) or not visible:
		return false
	return hand != (item as Grabbable).holder if item is Grabbable else true


func _process(_delta: float) -> void:
	if item and not is_instance_valid(item):
		show_for(null)
	elif item:
		_follow()


func _follow() -> void:
	global_position = item.global_position + Vector3.UP * (_top * item.scale.y + gap)
	var camera := Game.player.get_node_or_null(^"Camera") as Node3D if is_instance_valid(Game.player) else null
	if camera:
		var eye := camera.global_position
		eye.y = global_position.y
		if not eye.is_equal_approx(global_position):
			look_at(eye, Vector3.UP, true)


func _on_touch(_hand: Node3D) -> void:
	if item:
		pressed.emit(item)
