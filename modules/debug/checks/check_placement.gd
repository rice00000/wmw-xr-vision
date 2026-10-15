extends ModuleCheck
## Placement: furniture comes out of the bag into your hand, settles where it is
## let go, and goes back into the bag from the button floating over it.
##
## Uses its own DecorLayout (own save key, away from the real world) and the
## real Events.place_requested path the wrist menu's bag page uses.

const LAYOUT := preload("res://modules/placement/decor_layout.tscn")

@export var item: StringName = &"chair"

var _layout: DecorLayout
var _before := 0
var _seen: Dictionary[StringName, bool] = {}


func _arm() -> void:
	add_button(&"take", "Take a\nchair out")
	_layout = LAYOUT.instantiate() as DecorLayout
	_layout.name = "%sLayout" % name
	_layout.save_key = StringName("%s_layout" % name)
	_props.add_child(_layout)
	_seen.clear()
	Events.reported.connect(_on_fact)
	update(_line())


func _teardown() -> void:
	if Events.reported.is_connected(_on_fact):
		Events.reported.disconnect(_on_fact)


func _on_press(id: StringName) -> void:
	if id != &"take" or _seen.has(&"taken_out"):
		return
	mod().add(item, 1) # as if just bought
	_before = mod().count(item)
	Events.place_requested.emit(item)
	if not _seen.has(&"taken_out"):
		fail_now("nothing came out of the bag")


func _on_fact(what: StringName, id: StringName, _data: Dictionary) -> void:
	if id != item or not [&"taken_out", &"placed", &"put_away"].has(what) or verdict != Verdict.WAITING:
		return
	_seen[what] = true
	if _seen.size() < 3:
		update(_line())
		return
	var count: int = mod().count(item)
	var trace := "%s   %s %d -> %d" % [_line(), ItemDef.label(item), _before, count]
	if count == _before and _layout.items().is_empty():
		pass_now(trace)
	else:
		fail_now(trace)


func _line() -> String:
	var steps := PackedStringArray()
	for fact: StringName in [&"taken_out", &"placed", &"put_away"]:
		steps.append("%s %s" % [String(fact).replace("_", " "), "OK" if _seen.has(fact) else "-"])
	return "   ".join(steps)


## The tester's part: take it out, let go, pick it up again, press Put away with
## the other hand.
func auto() -> void:
	_on_press(&"take")
	var chair := _layout.items()[0] as Grabbable if not _layout.items().is_empty() else null
	if chair == null or chair.holder == null:
		fail_now("the chair did not land in a hand")
		return
	var hand := chair.holder
	hand.release()
	hand.hold(chair)
	var other: Node = null
	for node in get_tree().get_nodes_in_group(&"hand"):
		if node != hand:
			other = node
	var button := _layout.get_node(^"PutAwayButton") as Touchable
	if other == null or not button.touch(other):
		fail_now("the Put away button did not take the other hand's touch")
