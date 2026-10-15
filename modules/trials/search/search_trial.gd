class_name SearchTrial
extends Trial
## "Find the kettle": one round of finding a named object among clutter, the
## first prototype's task (design doc §3).
##
## Places a set of distinct, grabbable objects around the child, names one by
## voice, and scores the pick. Every object is graded to the same contrast, so the
## target cannot be found by brightness alone; distractors crowd in front of it as
## the overlap axis rises.
##
## [b]Axes it reads[/b] (from the round's [TrialCondition], names must match the
## TrialDef): [code]clutter[/code] how many objects, [code]overlap[/code] 0-1 how
## much they crowd and occlude the target, [code]contrast[/code] Weber contrast of
## every object against the surface.
##
## Motion is deliberately [i]not[/i] an axis here. It helped newly sighted people
## tell objects apart (ref [2]), so it is the middle rung of help instead — one
## variable, one controller.

@export var scatter: Scatter
## What the objects stand on. Every object is graded against this material's
## luminance, so the logged contrast is true for this table. Null = each object's
## own [member Contrast.background_luminance].
@export var surface: StandardMaterial3D
## Roots must be [Grabbable]s with an id, each carrying a [Highlight] and a
## [Contrast] child. Each is placed at most once, so this list also caps clutter.
@export var objects: Array[PackedScene] = []

@export_group("Guide")
## Said when the round starts. "%s" becomes the object's name.
@export var prompt := "Find the %s."
## Said after a wrong pick.
@export var retry := "Not that one. Try again."
## Recorded lines per object id, filled in once the guide is recorded.
@export var prompt_voice: Dictionary[StringName, AudioStream] = {}

@export_group("Feedback")
@export var correct_color := Color(0.25, 1.0, 0.4)
@export var wrong_color := Color(1.0, 0.3, 0.25)
## Outline used by the strongest hint.
@export var hint_color := Color(1.0, 0.85, 0.1)
@export var correct_sound: AudioStream
@export var wrong_sound: AudioStream
## How far the right pick rises, so its edges can be seen whole.
@export var lift_height := 0.25

var _placed: Array[Node3D] = []
var _target: Node3D
var _target_id: StringName = &""
var _listeners: Array[Callable] = []


## The object the guide named this round, or null between rounds.
func target() -> Node3D:
	return _target if is_running() else null


## Everything on the table this round, target included.
func placed() -> Array[Node3D]:
	return _placed.duplicate()


func _setup(round_condition: TrialCondition) -> void:
	if scatter == null or objects.is_empty():
		push_warning("[SearchTrial] Needs a Scatter and some objects.")
		return
	scatter.clear()
	scatter.unique = true # "find the cup" needs exactly one cup
	var count := maxi(2, roundi(round_condition.value(&"clutter", 6.0)))
	var overlap := round_condition.value(&"overlap", 0.0)
	_placed = scatter.place(objects, count, overlap)
	if _placed.is_empty():
		return

	_target = _placed.pick_random() as Node3D
	_target_id = _id_of(_target)

	# Same contrast on every object: the target must not pop out by brightness.
	var contrast := round_condition.value(&"contrast", 0.8)
	for node in _placed:
		var grading := _grading(node)
		if grading:
			if surface:
				grading.background_luminance = Trial.luminance(surface)
			grading.apply(contrast)

	# Crowd the target from where the child is sitting.
	for i in roundi(lerpf(0.0, 3.0, clampf(overlap, 0.0, 1.0))):
		var occluder := _placed[(_placed.find(_target) + 1 + i) % _placed.size()]
		if occluder != _target:
			scatter.occlude(occluder, _target, randf_range(0.35, 0.6))

	for node in _placed:
		var body := node as Grabbable
		if body:
			var listener := _on_grabbed.bind(body)
			body.grabbed.connect(listener)
			_listeners.append(listener)

	Events.say(prompt % ItemDef.label(_target_id), prompt_voice.get(_target_id))


func _teardown() -> void:
	for i in _placed.size():
		var body := _placed[i] as Grabbable
		if body and i < _listeners.size() and body.grabbed.is_connected(_listeners[i]):
			body.grabbed.disconnect(_listeners[i])
	_listeners.clear()


## 1 repeats the name, 2 moves the target, 3 outlines it. Weakest first; keep
## TrialDef.max_hint in step with this.
func _hint(level: int) -> void:
	if _target == null:
		return
	var emphasis := _emphasis(_target)
	match level:
		1:
			Events.say(prompt % ItemDef.label(_target_id), prompt_voice.get(_target_id))
		2:
			if emphasis:
				emphasis.wobble()
		3:
			if emphasis:
				emphasis.outline(hint_color)


func _on_grabbed(_hand: Node3D, body: Grabbable) -> void:
	if not is_running():
		return
	var highlight := _emphasis(body)
	if body == _target:
		Events.judge(&"good", body.global_position)
		Events.play_at(correct_sound, body.global_position)
		if highlight:
			highlight.settle()
			highlight.outline(correct_color)
			_release(body)
			highlight.lift(lift_height)
		finish(true, {target = _target_id, picked = _target_id})
		return
	Events.judge(&"bad", body.global_position)
	Events.play_at(wrong_sound, body.global_position)
	if highlight:
		highlight.flash(wrong_color)
	Events.report(&"mispicked", _id_of(body), {position = body.global_position})
	Events.say(retry)
	count_try()


## Let go of the right pick so it can rise clear of the clutter.
func _release(body: Grabbable) -> void:
	var hand := body.holder
	if hand and hand.has_method(&"release"):
		hand.release()


func _id_of(node: Node) -> StringName:
	var body := node as Grabbable
	if body and not body.id.is_empty():
		return body.id
	return StringName(node.name)


func _emphasis(node: Node) -> Highlight:
	for child in node.get_children():
		if child is Highlight:
			return child
	return null


func _grading(node: Node) -> Contrast:
	for child in node.get_children():
		if child is Contrast:
			return child
	return null
