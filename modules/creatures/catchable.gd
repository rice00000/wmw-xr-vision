class_name Catchable
extends Touchable
## A creature you catch by touching it. That is all it does: it reports
## "caught:<id>" or, after [member time_limit], "escaped:<id>", emits the matching
## signal, and leaves. Whoever put it there ([CatchTrial]) judges the attempt and
## ends the round, so there is exactly one path from a catch to the research log.

signal caught(position: Vector3)
signal escaped(position: Vector3)

@export var id: StringName = &"butterfly"
## Seconds before it flies away. 0 = never. Counts game time, so it waits while
## the wrist menu has the world paused.
@export var time_limit := 0.0

var _done := false


func _ready() -> void:
	if time_limit > 0.0:
		get_tree().create_timer(time_limit, false).timeout.connect(escape)


func is_done() -> bool:
	return _done


func _on_touch(_hand: Node3D) -> void:
	if _done:
		return
	_done = true
	var where := global_position
	Events.report(&"caught", id, {position = where})
	caught.emit(where)
	var tween := create_tween()
	tween.tween_property(self, ^"scale", Vector3.ONE * 0.01, 0.25)
	tween.tween_callback(queue_free)


## Flies off up and away, uncaught.
func escape() -> void:
	if _done or not is_inside_tree():
		return
	_done = true
	var where := global_position
	Events.report(&"escaped", id, {position = where})
	escaped.emit(where)
	for child in get_children():
		if child is Wander:
			child.queue_free()
	var tween := create_tween().set_parallel()
	tween.tween_property(self, ^"position", position + Vector3(0.0, 2.5, -1.5), 1.2)
	tween.tween_property(self, ^"scale", Vector3.ONE * 0.01, 1.2)
	tween.chain().tween_callback(queue_free)
