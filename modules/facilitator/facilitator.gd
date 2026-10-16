extends Node
## Facilitator panel: for the adult beside the child. Menu + left Y, consumed as
## one chord by Player. Training pins difficulty; Saves lists every save, newest
## played first, a page at a time, and names new ones with an on-panel keyboard:
## Start fresh plays a new game, Copy this save keeps a checkpoint of this one.
## Control layout is in facilitator_panel.tscn; viewport/ray input is shared code.

const PANEL := preload("res://modules/facilitator/facilitator_panel.tscn")
const STEP := 0.05
const PAGE_SIZE := 5
const KEYS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
const NAME_LENGTH := 20

var is_open := false

var _panel: ViewportUI
var _trial: StringName = &""
var _round: Dictionary = {}
var _page := 0
var _typed := ""


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
		var keys := _panel.content.find_child("Keys", true, false)
		for key in KEYS:
			var button := _button("fac_key_" + key, key)
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			keys.add_child(button)
		for button: Button in _panel.content.find_children("*", "Button", true, false):
			button.pressed.connect(_action.bind(StringName(button.name)))
	is_open = true
	_refresh()
	_panel.place()
	_panel.show()
	Game.hold_pause(&"facilitator", true)
	Events.menu_toggled.emit(true)


func close() -> void:
	if not is_open:
		return
	is_open = false
	if is_instance_valid(_panel):
		_panel.hide()
	Game.hold_pause(&"facilitator", false)
	Events.menu_toggled.emit(false)


func _on_reported(what: StringName, id: StringName, _data: Dictionary) -> void:
	if what == &"asked" and id == &"facilitator":
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
	if String(id).begins_with("fac_key_"):
		_type(String(id).right(1))
		return
	match id:
		&"fac_close":
			close()
		&"fac_training":
			_show(&"Training")
		&"fac_saves", &"fac_cancel":
			_show(&"Saves")
		&"fac_auto":
			var training := Game.module(&"Training")
			if training:
				training.unpin_all()
			_refresh_axes()
		&"fac_skip":
			close()
			for trial in get_tree().get_nodes_in_group(Trial.GROUP):
				trial.abandon()
		&"fac_prev", &"fac_next":
			_page += -1 if id == &"fac_prev" else 1
			_refresh_saves()
		&"fac_new_save":
			_typed = ""
			_refresh_name()
			_show(&"Naming")
		&"fac_space":
			_type(" ")
		&"fac_erase":
			_typed = _typed.left(-1)
			_refresh_name()
		&"fac_create":
			Profile.switch(Profile.new_save(_typed.strip_edges()))
		&"fac_copy":
			Save.write()
			Profile.copy(_typed.strip_edges())
			_refresh_saves()
			_show(&"Saves")


func _refresh() -> void:
	var def := TrialDef.find(_trial)
	var summary := _panel.content.find_child("Summary", true, false) as Label
	summary.text = "%s\nDifficulty %.2f   |   Round %d%s\nChanges apply next round." % [
		def.title, _round.get("difficulty", 0.0), _round.get("round", 0),
		"   |   PROBE" if _round.get("probe", false) else "",
	] if def else "No trial running.\nSit at a station to adjust its axes."
	_refresh_axes()
	_refresh_saves()


func _show(page: StringName) -> void:
	for child in _panel.content.find_child("Pages", true, false).get_children():
		child.visible = child.name == page


func _refresh_saves() -> void:
	var played := {}
	for save in Profile.saves():
		played[save] = Profile.played(save)
	var saves: Array = played.keys()
	saves.sort_custom(func(a: StringName, b: StringName) -> bool: return played[a] > played[b])
	var pages := maxi(1, ceili(saves.size() / float(PAGE_SIZE)))
	_page = clampi(_page, 0, pages - 1)
	var container := _panel.content.find_child("Slots", true, false) as VBoxContainer
	for row in container.get_children():
		container.remove_child(row)
		row.queue_free()
	for save: StringName in saves.slice(_page * PAGE_SIZE, (_page + 1) * PAGE_SIZE):
		var playing := save == Profile.id
		var button := _button("fac_slot_%s" % save, "%s   ·   %s" % [Profile.label(save),
			"Playing now" if playing else _when(played[save])])
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.disabled = playing
		button.pressed.connect(_load.bind(save, StringName(button.name)))
		container.add_child(button)
	(_panel.content.find_child("Page", true, false) as Label).text = "Page %d / %d" % [_page + 1, pages]
	(_panel.content.find_child("fac_prev", true, false) as Button).disabled = _page == 0
	(_panel.content.find_child("fac_next", true, false) as Button).disabled = _page == pages - 1


## Local date and time of a save's last write: "2026-10-15 14:32".
func _when(time: int) -> String:
	if time == 0:
		return "Not played yet"
	var bias: int = Time.get_time_zone_from_system().bias
	return Time.get_datetime_string_from_unix_time(time + bias * 60, true).left(16)


func _load(save: StringName, id: StringName) -> void:
	Events.report(&"pressed", id, {position = _panel.global_position})
	Profile.switch(save)


func _type(text: String) -> void:
	if _typed.length() < NAME_LENGTH:
		_typed += text
		_refresh_name()


func _refresh_name() -> void:
	(_panel.content.find_child("Name", true, false) as Label).text = "Name: %s_" % _typed


func _button(id: String, text: String) -> Button:
	var button := Button.new()
	button.name = id
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	return button


func _refresh_axes() -> void:
	var container := _panel.content.find_child("Axes", true, false) as VBoxContainer
	for row in container.get_children():
		container.remove_child(row)
		row.queue_free()
	var training := Game.module(&"Training")
	var def := TrialDef.find(_trial)
	(_panel.content.find_child("fac_auto", true, false) as Button).disabled = training == null or def == null
	(_panel.content.find_child("fac_skip", true, false) as Button).disabled = def == null
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
			var button := _button("fac_%s_%s" % [axis.name, "down" if direction < 0 else "up"],
				"-" if direction < 0 else "+")
			button.custom_minimum_size = Vector2(80, 64)
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
