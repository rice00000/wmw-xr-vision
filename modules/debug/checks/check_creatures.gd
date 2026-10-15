extends ModuleCheck
## Creatures: touching one catches it — it reports "caught:<id>" and leaves.
## What a catch is worth is the trial's business ([CatchTrial]), not the
## creature's, so that is all there is to check here.
##
## The creature is pinned still and given no time limit: this station is about
## catching, not about chasing, and a station that can time out would report a
## FAIL nobody caused.

## Seconds to wait for the creature to be gone after the catch.
const GONE_DEADLINE := 1.5

@export var creature: PackedScene

var _node: Catchable
var _id: StringName = &""
var _reported := false
var _signalled := false
var _waited := 0.0


func _arm() -> void:
	if creature == null:
		fail_now("no creature scene set on this station")
		return
	_node = creature.instantiate() as Catchable
	if _node == null:
		fail_now("that scene is not a Catchable")
		return
	_node.time_limit = 0.0
	_id = _node.id
	for child in _node.get_children():
		if child is Wander:
			child.queue_free()
	add_prop(_node, Vector3(0.0, 0.35, 0.0))
	_reported = false
	_signalled = false
	_waited = 0.0
	_node.caught.connect(func(_where: Vector3) -> void: _signalled = true)
	Events.reported.connect(_on_reported_fact)
	update("%s not caught yet" % ItemDef.label(_id))


func _teardown() -> void:
	if Events.reported.is_connected(_on_reported_fact):
		Events.reported.disconnect(_on_reported_fact)


func _on_reported_fact(what: StringName, id: StringName, _data: Dictionary) -> void:
	if what == &"caught" and id == _id:
		_reported = true
		update("caught, waiting for it to go")


func _tick() -> void:
	if verdict != Verdict.WAITING or not _reported:
		return
	_waited += 0.25
	var gone := not is_instance_valid(_node)
	if gone and _signalled:
		pass_now("caught:%s reported, and it is gone" % _id)
	elif _waited >= GONE_DEADLINE:
		fail_now("caught:%s reported, %s" % [_id,
			"but it is still there" if not gone else "but no caught signal"])


func auto() -> void:
	if is_instance_valid(_node):
		_node.touch(null)
