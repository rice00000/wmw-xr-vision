extends Node
## Debug module (autoload "Debug"): the hidden panel the team sets difficulty from
## by hand, which the design wants before the staircase takes over.
##
## Press the menu button on either controller to show it. It is built from the
## running trial's [TrialDef] axes, so a new trial or a new axis needs no change
## here. Pinned axes stop following the staircase until unpinned.
##
## Untick this autoload for any build a child will use.

const BUTTON := preload("res://components/touch_button.tscn")
const STEP := 0.05
## Where the panel appears relative to the player's head.
const OFFSET := Vector3(0.0, -0.15, -0.65)
## The hand-test room, one button away: see docs/hand-testing.md.
const TESTBED := "res://levels/testbed/testbed.tscn"

var _panel: Node3D
var _label: Label3D
var _trial: StringName = &""
## The last round's condition, as TrialCondition.to_log().
var _round: Dictionary = {}
var _selected := 0


func _ready() -> void:
	Events.reported.connect(_on_reported)
	Events.trial_started.connect(_on_trial_started)


func _on_trial_started(trial: StringName, round_condition: Dictionary) -> void:
	_trial = trial
	_round = round_condition
	_refresh()


func _on_reported(what: StringName, id: StringName, _data: Dictionary) -> void:
	if what == &"asked" and id == &"menu":
		_toggle()
		return
	if what != &"pressed" or _panel == null or not _panel.visible:
		return
	match id:
		&"dbg_axis":
			var names := _axis_names()
			if not names.is_empty():
				_selected = (_selected + 1) % names.size()
		&"dbg_down":
			_nudge(-STEP)
		&"dbg_up":
			_nudge(STEP)
		&"dbg_auto":
			var training := Game.module(&"Training")
			if training:
				training.unpin_all()
		&"dbg_skip":
			for trial in get_tree().get_nodes_in_group(Trial.GROUP):
				trial.abandon()
		&"dbg_tests":
			_panel.visible = false
			Game.change_level(TESTBED)
	_refresh()


func _toggle() -> void:
	if _panel == null:
		_build()
	if _panel == null:
		return
	_panel.visible = not _panel.visible
	if _panel.visible:
		_place()
		_refresh()


## Pins the selected axis one step away from where it is now. Steps are in the
## axis's own units, so a count axis moves in counts and a 0-1 axis in hundredths.
func _nudge(delta: float) -> void:
	var training := Game.module(&"Training")
	var axis := _selected_axis()
	if training == null or axis == null:
		return
	var scale := maxf(absf(axis.easy - axis.hard), 0.001)
	var value: float = _round.get("axis_%s" % axis.name, axis.resolve(_difficulty()))
	var low := minf(axis.easy, axis.hard)
	var high := maxf(axis.easy, axis.hard)
	training.pin(axis.name, clampf(value + delta * scale, low, high))


func _refresh() -> void:
	if _label == null:
		return
	var def := TrialDef.find(_trial)
	if def == null:
		_label.text = "No trial running.\nStart a level with a TrialRunner."
		return
	var training := Game.module(&"Training")
	var lines := PackedStringArray([
		"%s    difficulty %.2f%s" % [
			def.id, _difficulty(), "" if training else "   (Training off: read-only)"
		],
		"round %d%s" % [_round.get("round", 0), "  PROBE" if _round.get("probe", false) else ""],
		"",
	])
	var names := _axis_names()
	for i in names.size():
		var axis := def.axes[i]
		var pinned: bool = training != null and training.is_pinned(axis.name)
		lines.append("%s %-9s %7.2f  %s" % [
			">" if i == _selected else " ",
			axis.name,
			_round.get("axis_%s" % axis.name, axis.resolve(_difficulty())),
			"PINNED" if pinned else ("driven" if axis.driven else "fixed"),
		])
	_label.text = "\n".join(lines)


func _difficulty() -> float:
	return _round.get("difficulty", 0.0)


func _axis_names() -> PackedStringArray:
	var def := TrialDef.find(_trial)
	var names := PackedStringArray()
	if def:
		for axis in def.axes:
			if axis:
				names.append(String(axis.name))
	return names


func _selected_axis() -> TrialAxis:
	var def := TrialDef.find(_trial)
	if def == null or _selected >= def.axes.size():
		return null
	return def.axes[_selected]


func _build() -> void:
	if not is_instance_valid(Game.player):
		return
	_panel = Node3D.new()
	_panel.name = "DebugPanel"
	_label = Label3D.new()
	_label.pixel_size = 0.0007
	_label.font_size = 40
	_label.outline_size = 12
	_label.position = Vector3(0.0, 0.22, 0.0)
	_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_panel.add_child(_label)
	var buttons := [
		[&"dbg_axis", "Axis"], [&"dbg_down", "-"], [&"dbg_up", "+"],
		[&"dbg_auto", "Auto"], [&"dbg_skip", "Skip"], [&"dbg_tests", "Tests"],
	]
	for i in buttons.size():
		var button := BUTTON.instantiate() as TouchButton
		button.id = buttons[i][0]
		button.text = buttons[i][1]
		button.position = Vector3((i - (buttons.size() - 1) * 0.5) * 0.24, 0.0, 0.0)
		_panel.add_child(button)
	Game.player.add_child(_panel)
	_panel.visible = false


## In front of the head, upright, facing the player.
func _place() -> void:
	var player := Game.player
	if not is_instance_valid(player) or not player.has_node(^"Camera"):
		return
	var camera := player.get_node(^"Camera") as Node3D
	var forward := -camera.global_basis.z
	forward.y = 0.0
	if forward.length() < 0.01:
		forward = Vector3.FORWARD
	var spot := camera.global_position + camera.global_basis * OFFSET
	_panel.global_position = spot
	_panel.look_at(spot - forward.normalized(), Vector3.UP)
