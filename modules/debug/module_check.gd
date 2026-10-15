class_name ModuleCheck
extends Node3D
## One hand-test station in the Test Room: a sign that says what it is checking,
## what to do, what counts as a pass, and a verdict you can read from across the
## room. One per module, so the whole project can be hand-checked in a minute
## without reading any code.
##
## [b]The bar[/b] is that nobody has to remember anything. The sign carries the
## criterion, the station carries the props, and the verdict goes green or red by
## itself. There is nothing to count, compare or look up.
##
## A subclass fills in [member title] / [member checks] / [member action] /
## [member pass_when] (usually from the scene), builds its props in
## [method _arm], decides in [method _on_press] or its own signals, and calls
## [method pass_now] or [method fail_now]. [method auto] does the tester's part
## in code, which is what lets the headless smoke test run the very same checks —
## one definition, two ways to run it, so the room can never drift from the suite.
##
## A station whose [member module] autoload is switched off reports OFF instead of
## failing: that is the architecture's "every module is removable" rule being
## visible rather than asserted.

const GROUP := &"module_check"
const BUTTON := preload("res://components/touch_button.tscn")

enum Verdict {
	OFF, ## the module is switched off; nothing to check
	WAITING, ## nobody has done the action yet
	PASS,
	FAIL,
}

const COLORS := {
	Verdict.OFF: Color(0.45, 0.45, 0.5),
	Verdict.WAITING: Color(0.85, 0.85, 0.9),
	Verdict.PASS: Color(0.25, 0.95, 0.45),
	Verdict.FAIL: Color(1.0, 0.33, 0.28),
}

## Autoload this station needs, e.g. &"Inventory". Empty = no module needed.
@export var module: StringName = &""
## Heading on the sign. Empty = the node name.
@export var title := ""
## One line: what this station proves.
@export var checks := ""
## One line: what the tester does. Keep it to a single move.
@export var action := ""
## One line: the criterion, in the same words as the verdict.
@export var pass_when := ""

var verdict := Verdict.WAITING
## Live numbers under the verdict, e.g. "magic_stone 0 -> 1". Set it from the subclass.
var note := ""

var _module_node: Node
var _buttons := 0
var _header: Label3D
var _result: Label3D
var _props: Node3D


func _ready() -> void:
	add_to_group(GROUP)
	if title.is_empty():
		title = String(name).capitalize()
	_props = Node3D.new()
	_props.name = "Props"
	add_child(_props)
	_build_sign()
	Events.reported.connect(_on_reported)
	_module_node = Game.module(module) if not module.is_empty() else self
	if _module_node == null:
		verdict = Verdict.OFF
		_refresh()
		return
	_arm()
	var poll := Timer.new()
	poll.wait_time = 0.25
	poll.timeout.connect(_tick)
	add_child(poll)
	poll.start()
	_refresh()


## The module this station checks, or null when it is switched off.
func mod() -> Node:
	return _module_node


## First verdict wins: a station that has decided must not change its mind
## because something else on the bus looked like its event.
func pass_now(with_note := "") -> void:
	if verdict != Verdict.WAITING:
		return
	if not with_note.is_empty():
		note = with_note
	verdict = Verdict.PASS
	_refresh()


func fail_now(with_note := "") -> void:
	if verdict != Verdict.WAITING:
		return
	if not with_note.is_empty():
		note = with_note
	verdict = Verdict.FAIL
	_refresh()


## Re-draw the sign after changing [member note] without deciding anything.
func update(with_note := "") -> void:
	if not with_note.is_empty():
		note = with_note
	_refresh()


## Back to WAITING and set up again, so the station can be re-run.
func reset() -> void:
	if _module_node == null:
		return
	_teardown()
	for child in _props.get_children():
		_props.remove_child(child)
		child.queue_free()
	_buttons = 0
	verdict = Verdict.WAITING
	note = ""
	_arm.call_deferred()
	_refresh()


## Does the tester's part in code. Called by the room's RUN ALL button and by
## the headless smoke test. Subclasses that need to wait for something await it.
func auto() -> void:
	pass


# -- for subclasses ---------------------------------------------------------

## Build the props: buttons, objects to grab, an orb to touch.
func _arm() -> void:
	pass


## Undo anything [method _arm] did outside [member _props].
func _teardown() -> void:
	pass


## Polled four times a second, for anything that cannot announce itself (a panel
## opening, a counter moving). Empty by default.
func _tick() -> void:
	pass


## A TouchButton this station added was touched.
func _on_press(_id: StringName) -> void:
	pass


## Adds a labelled button in a row in front of the sign and returns it. Its id is
## "<station name>_<id>", so two stations can both have a "Go" button.
func add_button(id: StringName, label: String) -> TouchButton:
	var button := BUTTON.instantiate() as TouchButton
	button.id = button_id(id)
	button.text = label
	button.position = Vector3(-0.3 + _buttons * 0.3, 0.95, 0.12)
	_buttons += 1
	_props.add_child(button)
	return button


func button_id(id: StringName) -> StringName:
	return StringName("%s_%s" % [name, id])


## Puts [param node] on the station's pedestal, [param offset] from its middle.
func add_prop(node: Node3D, offset := Vector3.ZERO) -> Node3D:
	_props.add_child(node)
	node.position = Vector3(0.0, 0.76, 0.0) + offset
	return node


# -- internals --------------------------------------------------------------

func _on_reported(what: StringName, id: StringName, _data: Dictionary) -> void:
	if verdict == Verdict.OFF:
		return
	if what == &"pressed" and String(id).begins_with("%s_" % name):
		_on_press(StringName(String(id).trim_prefix("%s_" % name)))


func _refresh() -> void:
	if _header == null:
		return
	_header.text = "\n".join(PackedStringArray([
		title.to_upper(),
		"",
		"CHECK   %s" % checks,
		"DO      %s" % (action if verdict != Verdict.OFF else "nothing: this module is switched off"),
		"PASS    %s" % pass_when,
	]))
	var word: String = ["MODULE OFF", "WAITING", "PASS", "FAIL"][verdict]
	_result.text = word if note.is_empty() else "%s    %s" % [word, note]
	_result.modulate = COLORS[verdict]
	_result.outline_modulate = Color(0, 0, 0, 1)


func _build_sign() -> void:
	var pedestal := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.7, 0.72, 0.5)
	pedestal.mesh = box
	pedestal.position = Vector3(0.0, 0.36, 0.0)
	add_child(pedestal)

	_header = Label3D.new()
	_header.pixel_size = 0.0007
	_header.font_size = 38
	_header.outline_size = 10
	_header.position = Vector3(0.0, 1.62, 0.0)
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(_header)

	_result = Label3D.new()
	_result.pixel_size = 0.0014
	_result.font_size = 48
	_result.outline_size = 12
	_result.position = Vector3(0.0, 1.26, 0.0)
	add_child(_result)
