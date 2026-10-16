class_name CatchTrial
extends Trial
## "Catch the butterfly": one round is one creature, in front of the child, until
## it is caught (success) or flies away (fail). Trains following something that
## moves (visual skill "motion").
##
## The creature is any scene whose root reports [code]caught(position)[/code] and
## [code]escaped(position)[/code] signals and has a [code]time_limit[/code]
## ([Catchable] does). It is duck-typed so this module never names another one.
## A [Wander] child, if any, gets its speed from the round; a [Contrast] child its
## grade; a [Highlight] child shows the hints.
##
## [b]Axes it reads[/b]: [code]speed[/code] m/s it wanders at, [code]size[/code]
## scale of the creature, [code]distance[/code] m in front of the child's eyes,
## [code]contrast[/code] Weber contrast against [member surface],
## [code]time_limit[/code] seconds before it escapes.

## The creature to put out each round.
@export var creature: PackedScene
## Where the child sits, facing -Z. The creature comes out in front of it.
@export var anchor: Node3D
## What the creature is graded against: the meadow it is seen over. Null = the
## creature's own [member Contrast.background_luminance].
@export var surface: StandardMaterial3D
## Eye height above [member anchor] when the child's head is not there (a free-play
## round started from code).
@export var eye_height := 1.1

@export_group("Guide")
## Said on the first round of a run, and again by the first hint.
@export var prompt := "Catch the butterfly with your hand!"
@export var prompt_voice: AudioStream

@export_group("Feedback")
@export var caught_color := Color(0.25, 1.0, 0.4)
## Outline used by the strongest hint.
@export var hint_color := Color(1.0, 0.85, 0.1)

var _creature: Node3D
var _id: StringName = &""


## The creature out this round, or null between rounds.
func current() -> Node3D:
	return _creature if is_running() and is_instance_valid(_creature) else null


func _setup(round_condition: TrialCondition) -> void:
	if creature == null or anchor == null:
		push_warning("[CatchTrial] Needs a creature scene and an anchor.")
		return
	var node := creature.instantiate() as Node3D
	if node == null or not node.has_signal(&"caught") or not node.has_signal(&"escaped"):
		push_warning("[CatchTrial] The creature must have caught / escaped signals.")
		return
	_creature = node
	_id = StringName(str(node.get(&"id"))) if &"id" in node else StringName(node.name)
	if &"time_limit" in node:
		node.set(&"time_limit", round_condition.value(&"time_limit", 10.0))

	var forward := -anchor.global_basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	var side := anchor.global_basis.x * randf_range(-0.25, 0.25)
	var spot := _eye() + forward * round_condition.value(&"distance", 0.6) + side + Vector3.DOWN * 0.15
	var stage := anchor.get_parent() as Node3D
	node.position = stage.to_local(spot)
	node.scale = Vector3.ONE * round_condition.value(&"size", 1.0)
	stage.add_child(node)

	var wander := _child(node, "Wander")
	if wander:
		wander.set(&"speed", round_condition.value(&"speed", 0.3))
	var grading := _child(node, "Contrast") as Contrast
	if grading:
		if surface:
			grading.background_luminance = Trial.luminance(surface)
		grading.apply(round_condition.value(&"contrast", 0.8))
	node.connect(&"caught", _on_caught)
	node.connect(&"escaped", _on_escaped)
	if round_condition.round_index == 0:
		Narrator.say(prompt, prompt_voice, &"trial")


func _teardown() -> void:
	if not is_instance_valid(_creature):
		_creature = null
		return
	if _creature.is_connected(&"caught", _on_caught):
		_creature.disconnect(&"caught", _on_caught)
	if _creature.is_connected(&"escaped", _on_escaped):
		_creature.disconnect(&"escaped", _on_escaped)
	# Abandoned from the facilitator panel: nobody caught it and it did not fly off.
	if _creature.has_method(&"is_done") and not _creature.call(&"is_done"):
		_creature.queue_free()
	_creature = null


## 1 says it again and slows it down, 2 stops it so it hovers and flutters in
## place, 3 outlines it. Weakest first; keep TrialDef.max_hint in step.
func _hint(level: int) -> void:
	if not is_instance_valid(_creature):
		return
	var wander := _child(_creature, "Wander")
	match level:
		1:
			Narrator.say(prompt, prompt_voice, &"trial")
			if wander:
				wander.set(&"speed", float(wander.get(&"speed")) * 0.5)
		2:
			if wander:
				wander.set(&"speed", 0.0)
				wander.set(&"flutter", 0.07)
		3:
			var emphasis := _child(_creature, "Highlight") as Highlight
			if emphasis:
				emphasis.outline(hint_color)


func _on_caught(where: Vector3) -> void:
	if not is_running():
		return
	Events.judge(&"good", where)
	var emphasis := _child(_creature, "Highlight") as Highlight
	if emphasis:
		emphasis.outline(caught_color)
	finish(true, {target = _id, result = "caught"})


func _on_escaped(where: Vector3) -> void:
	if not is_running():
		return
	Events.judge(&"bad", where)
	finish(false, {target = _id, result = "escaped"})


## The child's eyes when they are sitting here, else where they would be.
func _eye() -> Vector3:
	var fallback := anchor.global_position + Vector3.UP * eye_height
	var player := Game.player
	if not is_instance_valid(player):
		return fallback
	var head := player.get_node_or_null(^"Camera") as Node3D
	if head == null:
		return fallback
	var flat := head.global_position - anchor.global_position
	flat.y = 0.0
	return head.global_position if flat.length() < 1.5 else fallback


## First child of [param node] whose script's class or name is [param kind].
func _child(node: Node, kind: String) -> Node:
	if node == null:
		return null
	for child in node.get_children():
		var script := child.get_script() as Script
		if child.name == kind or (script and script.get_global_name() == kind):
			return child
	return null
