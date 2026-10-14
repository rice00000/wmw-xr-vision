class_name Catchable
extends Touchable
## A creature you catch by touching it. On catch it reports "caught:<id>", ends a
## successful training trial (with reaction time), gives one <id> item, then vanishes.
## With a time limit it escapes instead: "escaped:<id>" and a failed trial.

@export var id: StringName = &"butterfly"
## Training skill this attempt counts toward.
@export var skill: StringName = &"motion"
## Give the player one <id> item when caught (their collection).
@export var collect := true
## Seconds before it flies away. 0 = never.
@export var time_limit := 0.0

var _born_ms := 0
var _done := false


func _ready() -> void:
	_born_ms = Time.get_ticks_msec()
	if time_limit > 0.0:
		get_tree().create_timer(time_limit).timeout.connect(_escape)


func _on_touch(_hand: Node3D) -> void:
	if _done:
		return
	Events.report(&"caught", id)
	_finish(true)
	if collect:
		Events.reward_granted.emit(id, 1)


func _escape() -> void:
	if _done:
		return
	Events.report(&"escaped", id)
	_finish(false)


func _finish(success: bool) -> void:
	_done = true
	Events.trial_ended.emit(skill, success, {id = id, seconds = (Time.get_ticks_msec() - _born_ms) / 1000.0})
	var tween := create_tween()
	tween.tween_property(self, ^"scale", Vector3.ONE * 0.01, 0.25)
	tween.tween_callback(queue_free)
