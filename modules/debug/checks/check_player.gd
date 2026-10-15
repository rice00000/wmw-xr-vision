extends ModuleCheck
## The player rig itself, which is not a module but is the first thing to test:
## a hand can grab, and B / Y asks the guide for help.
##
## Everything else in the room assumes these two work, so this station is first
## in the row: if it is red, nothing further along means anything.

@export var object: PackedScene

var _grabbed := false
var _asked := false


func _arm() -> void:
	if object:
		add_prop(object.instantiate() as Node3D, Vector3(0.0, 0.1, 0.0))
	Events.reported.connect(_on_reported_fact)
	update(_line())


func _teardown() -> void:
	if Events.reported.is_connected(_on_reported_fact):
		Events.reported.disconnect(_on_reported_fact)


func _on_reported_fact(what: StringName, _id: StringName, _data: Dictionary) -> void:
	if verdict != Verdict.WAITING:
		return
	if what == &"grabbed":
		_grabbed = true
	elif what == &"asked":
		_asked = true
	if _grabbed and _asked:
		pass_now(_line())
	else:
		update(_line())


func _line() -> String:
	return "grab %s   B / Y %s" % ["OK" if _grabbed else "-", "OK" if _asked else "-"]


func auto() -> void:
	for child in _props.get_children():
		if child is Grabbable:
			var hand := Node3D.new()
			(child as Grabbable).grab(hand)
			(child as Grabbable).release(hand, Vector3.ZERO)
			hand.free()
	Events.report(&"asked", &"help")
