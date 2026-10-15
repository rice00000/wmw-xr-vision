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
## line in the player's own log, <profile>/metrics/<session start>.jsonl (see
## Profile). A session starts when a profile is opened and its first line says
## whose it is and whether they just started over; Start over never deletes a
## log. Trial lines carry the complete condition, so a result can always be traced
## back to what the child was shown.
##
## The adapter and the log live together on purpose: splitting them would make two
## modules that have to call each other, which the architecture does not allow.
##
## Part of the trials layer (modules/trials/), but its own autoload: switching
## it off leaves trials running at their TrialDef's probe difficulty, unlogged.

const START_LEVEL := 0.3
const STEP := 0.1
const UP_AFTER := 2

var _levels: Dictionary[StringName, float] = {}
var _streaks: Dictionary[StringName, int] = {}
## Axis name -> pinned value, set by the debug menu. Overrides the staircase
## until unpinned or until another profile is opened.
var _overrides: Dictionary[StringName, float] = {}
var _log: FileAccess
## The first line of the next log: who, and whether they just started over.
var _session := {type = "session", wiped = false}


func _ready() -> void:
	Events.trial_started.connect(_on_trial_started)
	Events.trial_ended.connect(_on_trial_ended)
	Events.reported.connect(_on_reported)
	Events.profile_closing.connect(func() -> void:
		_log = null # the next line opens the next player's log
		_overrides.clear())
	Events.profile_opened.connect(func(wiped: bool) -> void: _session = {type = "session", wiped = wiped})


func level(visual_skill: StringName) -> float:
	return _levels.get(visual_skill, START_LEVEL)


## Settings for the next round of [param trial_id]. [param probe] rounds run at a
## fixed difficulty and do not move the staircase.
func condition(trial_id: StringName, round_index := 0, probe := false) -> TrialCondition:
	var def := TrialDef.find(trial_id)
	if def == null:
		push_warning("[Training] Unknown trial: %s" % trial_id)
		return TrialCondition.new()
	var difficulty := def.probe_difficulty if probe else level(def.visual_skill)
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


func _on_trial_ended(visual_skill: StringName, success: bool, data: Dictionary) -> void:
	var before := level(visual_skill)
	var after := before
	# A probe measures: it must not move the difficulty it is measuring at.
	if not data.get("probe", false):
		var def := TrialDef.find(data.get("trial", &""))
		var step: float = def.step if def else STEP
		var up_after: int = def.up_after if def else UP_AFTER
		if not success:
			after -= step
			_streaks[visual_skill] = 0
		else:
			_streaks[visual_skill] = _streaks.get(visual_skill, 0) + 1
			if _streaks[visual_skill] >= up_after:
				after += step
				_streaks[visual_skill] = 0
		_levels[visual_skill] = clampf(after, 0.0, 1.0)
	_write({
		type = "trial",
		visual_skill = visual_skill,
		success = success,
		level = before, # the level the round actually ran at
		level_after = level(visual_skill),
		data = data,
	})


func _on_reported(what: StringName, id: StringName, data: Dictionary) -> void:
	_write({type = "event", what = what, id = id, data = data})


func _write(entry: Dictionary) -> void:
	if _log == null and not _open_log():
		return
	entry.time = Time.get_unix_time_from_system()
	_log.store_line(JSON.stringify(entry))
	_log.flush()


## Opens this session's log in the player's folder, appending when a session
## started in the same second already has the name.
func _open_log() -> bool:
	var folder := Profile.path("metrics/")
	DirAccess.make_dir_recursive_absolute(folder)
	var file := "%s%s.jsonl" % [folder, Time.get_datetime_string_from_system().replace(":", "-")]
	_log = FileAccess.open(file, FileAccess.READ_WRITE if FileAccess.file_exists(file) else FileAccess.WRITE)
	if _log == null:
		return false
	_log.seek_end()
	var session := _session.duplicate()
	session.profile = String(Profile.id)
	session.time = Time.get_unix_time_from_system()
	_log.store_line(JSON.stringify(session))
	return true


func save_state() -> Dictionary:
	return {levels = _levels.duplicate(), streaks = _streaks.duplicate()}


func load_state(data: Dictionary) -> void:
	_levels.assign(data.get("levels", {}))
	_streaks.assign(data.get("streaks", {}))
