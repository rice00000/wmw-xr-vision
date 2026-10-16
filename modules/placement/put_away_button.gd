class_name PutAwayButton
extends Touchable
## The "put away" button for furniture held by a hand, anchored in front of
## the player when grabbed. The holding hand cannot press it (it would be pressed by
## accident while carrying); the other hand can. Its look is
## content/effects/put_away_icon.tscn, instanced as the child "Visual".

signal pressed(item: Node3D)

## Reachable position below the eyes at grab time, along the rig's forward direction.
@export var reach_offset := Vector3(0.0, -0.3, -0.45)

var item: Node3D

var _anchor := Vector3.ZERO


## Anchors a button for [param node] until it is let go; null hides it.
func show_for(node: Node3D) -> void:
	item = node
	visible = node != null
	set_deferred(&"monitorable", visible) # may be called from inside a touch
	if node:
		var camera := Game.player.get_node(^"Camera") as Node3D
		_anchor = camera.position + reach_offset
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
	global_position = Game.player.to_global(_anchor)
	var camera := Game.player.get_node(^"Camera") as Node3D
	var eye := camera.global_position
	eye.y = global_position.y
	if not eye.is_equal_approx(global_position):
		look_at(eye, Vector3.UP, true)


func _on_touch(_hand: Node3D) -> void:
	if item:
		pressed.emit(item)
