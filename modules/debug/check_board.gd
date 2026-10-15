class_name CheckBoard
extends Node3D
## The Test Room's board: every station's verdict in one list, a tally, and two
## buttons — RUN ALL does every station's action in code, RESET puts them all
## back to WAITING.
##
## RUN ALL is the thirty-second sweep: press it, read one number, and you know
## whether the build is sound. Doing the stations by hand is the slower, more
## honest pass, and the two share one definition of every check, so the room can
## never say something the smoke test does not.

const BUTTON := preload("res://components/touch_button.tscn")

var _label: Label3D
var _running := false


func _ready() -> void:
	_label = Label3D.new()
	_label.pixel_size = 0.0011
	_label.font_size = 40
	_label.outline_size = 12
	_label.position = Vector3(0.0, 1.75, 0.0)
	add_child(_label)
	for i in 2:
		var button := BUTTON.instantiate() as TouchButton
		button.id = [&"board_run", &"board_reset"][i]
		button.text = ["RUN ALL", "RESET"][i]
		button.position = Vector3(-0.2 + i * 0.4, 0.95, 0.12)
		add_child(button)
	Events.reported.connect(_on_reported)
	var poll := Timer.new()
	poll.wait_time = 0.25
	poll.timeout.connect(_refresh)
	add_child(poll)
	poll.start()
	_refresh()


func stations() -> Array[Node]:
	var found := get_tree().get_nodes_in_group(ModuleCheck.GROUP)
	found.sort_custom(func(a: Node, b: Node) -> bool: return a.name < b.name)
	return found


func _on_reported(what: StringName, id: StringName, _data: Dictionary) -> void:
	if what != &"pressed":
		return
	if id == &"board_run":
		run_all()
	elif id == &"board_reset":
		for station in stations():
			station.reset()
		_refresh()


## Does every station's action, in order, waiting for the ones that need time.
func run_all() -> void:
	if _running:
		return
	_running = true
	for station in stations():
		if station.verdict == ModuleCheck.Verdict.OFF:
			continue
		await station.auto()
	_running = false
	_refresh()


func _refresh() -> void:
	var lines := PackedStringArray(["TEST ROOM"])
	var passed := 0
	var checked := 0
	var failed := 0
	for station in stations():
		var word: String = ["off", "...", "PASS", "FAIL"][station.verdict]
		lines.append("  %-14s %s" % [station.title, word])
		if station.verdict == ModuleCheck.Verdict.PASS:
			passed += 1
		if station.verdict == ModuleCheck.Verdict.FAIL:
			failed += 1
		if station.verdict != ModuleCheck.Verdict.OFF:
			checked += 1
	lines.insert(1, "%d / %d PASS%s" % [passed, checked, "   %d FAILED" % failed if failed else ""])
	lines.insert(2, "")
	_label.text = "\n".join(lines)
	_label.modulate = Color(1.0, 0.35, 0.3) if failed else (
		Color(0.3, 1.0, 0.5) if checked > 0 and passed == checked else Color(0.9, 0.9, 0.95))
