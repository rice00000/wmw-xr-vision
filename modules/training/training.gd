extends Node
## Training module (autoload "Training"): adaptive difficulty + research log.
##
## Difficulty: one level per visual skill (0 = easiest, 1 = hardest), moved by a
## simple 2-down / 1-up staircase on Events.trial_ended. Gameplay reads it via level().
## Log: every trial and gameplay fact is appended as one JSON line to
## user://metrics/<session start>.jsonl for researchers.
##
## Skills used so far: &"motion" (catch moving targets), &"search" (find a target in clutter).
## These are placeholders until the training design is validated with vision researchers.

const START_LEVEL := 0.3
const STEP := 0.1
const LOG_DIR := "user://metrics/"

var _levels: Dictionary[StringName, float] = {}
var _streaks: Dictionary[StringName, int] = {}
var _log: FileAccess


func _ready() -> void:
	Events.trial_ended.connect(_on_trial_ended)
	Events.reported.connect(_on_reported)


func level(skill: StringName) -> float:
	return _levels.get(skill, START_LEVEL)


func _on_trial_ended(skill: StringName, success: bool, data: Dictionary) -> void:
	var before := level(skill)
	var after := before
	if not success:
		after -= STEP
		_streaks[skill] = 0
	else:
		_streaks[skill] = _streaks.get(skill, 0) + 1
		if _streaks[skill] >= 2:
			after += STEP
			_streaks[skill] = 0
	_levels[skill] = clampf(after, 0.0, 1.0)
	_write({type = "trial", skill = skill, success = success, level = before, data = data})


func _on_reported(what: StringName, id: StringName, data: Dictionary) -> void:
	_write({type = "event", what = what, id = id, data = data})


func _write(entry: Dictionary) -> void:
	if _log == null:
		DirAccess.make_dir_recursive_absolute(LOG_DIR)
		var stamp := Time.get_datetime_string_from_system().replace(":", "-")
		_log = FileAccess.open("%s%s.jsonl" % [LOG_DIR, stamp], FileAccess.WRITE)
		if _log == null:
			return
	entry.time = Time.get_unix_time_from_system()
	_log.store_line(JSON.stringify(entry))
	_log.flush()


func save_state() -> Dictionary:
	return {levels = _levels.duplicate()}


func load_state(data: Dictionary) -> void:
	_levels.assign(data.get("levels", {}))
	_streaks.clear()
