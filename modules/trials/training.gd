extends Node
## Training module (autoload "Training"): difficulty adapter + research log.
##
## [b]Difficulty[/b] is one 0-1 scalar per visual skill, moved by an N-up / 1-down
## staircase on [signal Events.trial_ended]. A trial never reads that scalar
## directly: its runner asks for a [TrialCondition] ([method condition]), which spreads
## the scalar across the named axes of its [TrialDef]. Only axes marked
## [member TrialAxis.driven] follow it, so a failed round stays attributable to
## one variable instead of several moving together.
##
## [b]Log[/b]: every round start, round end and gameplay fact becomes one JSON
## line in user://metrics/<session start>.jsonl. Trial lines carry the complete
## condition, so a result can always be traced back to what the child was shown.
##
## The adapter and the log live together on purpose: splitting them would make two
## modules that have to call each other, which the architecture does not allow.
##
## Part of the trials layer (modules/trials/), but its own autoload: switching
## it off leaves trials running at their TrialDef's probe difficulty, unlogged.

const START_LEVEL := 0.3
const STEP := 0.1
const UP_AFTER := 2
const LOG_DIR := "user://metrics/"

var _levels: Dictionary[StringName, float] = {}
var _streaks: Dictionary[StringName, int] = {}
## Axis name -> pinned value, set by the debug menu. Overrides the staircase.
var _overrides: Dictionary[StringName, float] = {}
var _log: FileAccess


func _ready() -> void:
	Events.trial_started.connect(_on_trial_started)
	Events.trial_ended.connect(_on_trial_ended)
	Events.reported.connect(_on_reported)


func level(skill: StringName) -> float:
	return _levels.get(skill, START_LEVEL)


## Settings for the next round of [param trial_id]. [param probe] rounds run at a
## fixed difficulty and do not move the staircase.
func condition(trial_id: StringName, round_index := 0, probe := false) -> TrialCondition:
	var def := TrialDef.find(trial_id)
	if def == null:
		push_warning("[Training] Unknown trial: %s" % trial_id)
		return TrialCondition.new()
	var difficulty := def.probe_difficulty if probe else level(def.skill)
	return def.condition(difficulty, round_index, probe, _overrides)


## Pin an axis to [param value] for every following round (debug menu).
func pin(axis: StringName, value: float) -> void:
	_overrides[axis] = value


func unpin(axis: StringName) -> void:
	_overrides.erase(axis)


func unpin_all() -> void:
	_overrides.clear()


func is_pinned(axis: StringName) -> bool:
	return _overrides.has(axis)


func _on_trial_started(trial: StringName, round_condition: Dictionary) -> void:
	_write({type = "trial_start", trial = trial, data = round_condition})


func _on_trial_ended(skill: StringName, success: bool, data: Dictionary) -> void:
	var before := level(skill)
	var after := before
	# A probe measures: it must not move the difficulty it is measuring at.
	if not data.get("probe", false):
		var def := TrialDef.find(data.get("trial", &""))
		var step: float = def.step if def else STEP
		var up_after: int = def.up_after if def else UP_AFTER
		if not success:
			after -= step
			_streaks[skill] = 0
		else:
			_streaks[skill] = _streaks.get(skill, 0) + 1
			if _streaks[skill] >= up_after:
				after += step
				_streaks[skill] = 0
		_levels[skill] = clampf(after, 0.0, 1.0)
	_write({
		type = "trial",
		skill = skill,
		success = success,
		level = before, # the level the round actually ran at
		level_after = level(skill),
		data = data,
	})


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
