extends Node
## Team UI: Menu + left Y, consumed as one chord by Player.
## Control layout is in debug_panel.tscn; viewport/ray input is shared code.

const PANEL := preload("res://modules/debug/debug_panel.tscn")
const STEP := 0.05

var is_open := false

var _panel: ViewportUI
var _trial: StringName = &""
var _round: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(&"xr_ui")
	Events.reported.connect(_on_reported)
	Events.trial_started.connect(_on_trial_started)
	Events.profile_closing.connect(_reset)
	Events.level_changing.connect(func(_path: String) -> void: _reset())
	Events.trial_ended.connect(func(_visual_skill: StringName, _success: bool, _data: Dictionary) -> void:
		_trial = &""
		_round = {}
		if is_open:
			_refresh())
	var xr := XRServer.find_interface("OpenXR")
	if xr:
		xr.pose_recentered.connect(_recentre)


func open() -> void:
	if is_open or not is_instance_valid(Game.player):
		return
	get_tree().call_group(&"xr_ui", &"close")
	if not is_instance_valid(_panel):
		_panel = PANEL.instantiate() as ViewportUI
		Game.player.add_child(_panel)
		for button: Button in _panel.content.find_children("*", "Button", true, false):
			button.pressed.connect(_action.bind(StringName(button.name)))
	is_open = true
	_refresh()
	_panel.place()
	_panel.show()
	Game.hold_pause(&"debug", true)
	Events.menu_toggled.emit(true)


func close() -> void:
	if not is_open:
		return
	is_open = false
	if is_instance_valid(_panel):
		_panel.hide()
	Game.hold_pause(&"debug", false)
	Events.menu_toggled.emit(false)


func _on_reported(what: StringName, id: StringName, _data: Dictionary) -> void:
	if what == &"asked" and id == &"debug":
		if is_open:
			close()
		else:
			open()


func _on_trial_started(trial: StringName, condition: Dictionary) -> void:
	_trial = trial
	_round = condition
	if is_open:
		_refresh()


func _action(id: StringName) -> void:
	Events.report(&"pressed", id, {position = _panel.global_position})
	match id:
		&"dbg_close":
			close()
		&"dbg_training", &"dbg_saves":
			_panel.content.find_child("Training", true, false).visible = id == &"dbg_training"
			_panel.content.find_child("Saves", true, false).visible = id == &"dbg_saves"
		&"dbg_auto":
			var training := Game.module(&"Training")
			if training:
				training.unpin_all()
			_refresh_axes()
		&"dbg_skip":
			close()
			for trial in get_tree().get_nodes_in_group(Trial.GROUP):
				trial.abandon()
		&"dbg_save":
			var saves := Profile.saves()
			if saves.is_empty():
				saves.append(Profile.new_save())
			Profile.switch(saves[(saves.find(Profile.current_save()) + 1) % saves.size()])
		&"dbg_new_save":
			Profile.switch(Profile.new_save())
		&"dbg_tests":
			if Profile.is_test_room():
				Profile.switch(Profile.current_save())
			else:
				Profile.open_test_room()


func _refresh() -> void:
	var def := TrialDef.find(_trial)
	var summary := _panel.content.find_child("Summary", true, false) as Label
	summary.text = "%s\nDifficulty %.2f   |   Round %d%s\nChanges apply next round." % [
		def.title, _round.get("difficulty", 0.0), _round.get("round", 0),
		"   |   PROBE" if _round.get("probe", false) else "",
	] if def else "No trial running.\nSit at a station to adjust its axes."
	(_panel.content.find_child("Who", true, false) as Label).text = "Playing: %s" % Profile.label()
	(_panel.content.find_child("dbg_tests", true, false) as Button).text = "Return to save" if Profile.is_test_room() else "Open Test Room"
	_refresh_axes()


func _refresh_axes() -> void:
	var container := _panel.content.find_child("Axes", true, false) as VBoxContainer
	for row in container.get_children():
		container.remove_child(row)
		row.queue_free()
	var training := Game.module(&"Training")
	var def := TrialDef.find(_trial)
	(_panel.content.find_child("dbg_auto", true, false) as Button).disabled = training == null or def == null
	(_panel.content.find_child("dbg_skip", true, false) as Button).disabled = def == null
	if def == null:
		return
	for axis in def.axes:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		container.add_child(row)
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var pinned: bool = training != null and training.is_pinned(axis.name)
		label.text = "%s   %.2f   %s" % [String(axis.name).capitalize(), _axis_value(axis),
			"PINNED" if pinned else ("driven" if axis.driven else "fixed")]
		row.add_child(label)
		for direction in [-1, 1]:
			var button := Button.new()
			button.name = "dbg_%s_%s" % [axis.name, "down" if direction < 0 else "up"]
			button.text = "-" if direction < 0 else "+"
			button.custom_minimum_size = Vector2(80, 64)
			button.focus_mode = Control.FOCUS_NONE
			button.disabled = training == null
			row.add_child(button)
			button.pressed.connect(_nudge.bind(axis, direction, StringName(button.name)))


func _axis_value(axis: TrialAxis) -> float:
	var training := Game.module(&"Training")
	if training:
		return training.condition(_trial, _round.get("round", 0), _round.get("probe", false)).value(axis.name)
	return _round.get("axis_%s" % axis.name, axis.resolve(_round.get("difficulty", 0.0)))


func _nudge(axis: TrialAxis, direction: int, id: StringName) -> void:
	var training := Game.module(&"Training")
	var step := maxf(absf(axis.easy - axis.hard), 0.001) * STEP
	training.pin(axis.name, clampf(_axis_value(axis) + direction * step,
		minf(axis.easy, axis.hard), maxf(axis.easy, axis.hard)))
	Events.report(&"pressed", id, {position = _panel.global_position})
	_refresh_axes()


func _recentre() -> void:
	await get_tree().process_frame
	if is_open:
		_panel.place()


func _reset() -> void:
	close()
	_trial = &""
	_round = {}
