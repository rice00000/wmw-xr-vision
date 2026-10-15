class_name Trial
extends Node
## Base for one measured round — the task manager of the design doc.
##
## A subclass sets a round up in [method _setup], calls [method finish] when the
## child gets it right or wrong, counts wrong attempts with [method count_try],
## and renders help in [method _hint]. This base owns everything a researcher
## needs: time, tries, the hint level reached and the round's full condition, all
## emitted from one place so no trial can log a different shape.
##
## It talks only through [Events] and the [TrialCondition] it is handed, never to
## Training, Vision, Tasks or audio, so a trial keeps working with any of those
## modules switched off.
##
## [b]Help[/b] escalates by itself: [member TrialDef.hint_after] seconds of no
## progress raises the hint level by one, and each round pushes that delay out by
## [member TrialDef.hint_fade], so help fades as the child improves. Pressing B / Y
## asks for the next hint immediately. Probe rounds get no help at all.

## Emitted after [signal Events.trial_ended], for whoever drives the rounds.
signal ended(success: bool)
## The round was dropped unscored ([method abandon]). It does not count as a round.
signal abandoned

## Settings for the round in progress. Null between rounds.
var condition: TrialCondition
## Wrong attempts so far this round.
var tries := 0
## Highest hint level reached this round. 0 = solved unaided.
var hint_level := 0

var _running := false
## Seconds this round has been running, in game time: the wrist menu pauses the
## world, and a round must not count (or hint through) time nobody could play.
var _elapsed := 0.0
## [member _elapsed] at which the next hint is due; 0 = none due.
var _hint_at := 0.0
var _held := false
var _def: TrialDef


## Every Trial joins this, so tools can find the running trial without a reference.
const GROUP := &"trial"


## Linear luminance of a material's albedo: what a [Contrast] grades an object
## against when the round says which surface it is seen on.
static func luminance(material: StandardMaterial3D) -> float:
	var linear := material.albedo_color.srgb_to_linear()
	return Vector3(linear.r, linear.g, linear.b).dot(Contrast.LUMA)


func _ready() -> void:
	add_to_group(GROUP)
	Events.reported.connect(_on_reported)


## Starts one round. Called by [TrialRunner].
func begin(round_condition: TrialCondition) -> void:
	if _running or round_condition == null:
		return
	condition = round_condition
	_def = TrialDef.find(condition.trial)
	tries = 0
	hint_level = 0
	_elapsed = 0.0
	_held = false
	_running = true
	_setup(condition)
	_arm_hint()
	Events.trial_started.emit(condition.trial, condition.to_log())


## Ends the round. [param extra] adds trial-specific fields to the log line.
func finish(success: bool, extra: Dictionary = {}) -> void:
	if not _running:
		return
	_running = false
	_hint_at = 0.0
	var data := condition.to_log()
	data.merge({seconds = seconds(), tries = tries, hint = hint_level}, true)
	data.merge(extra, true)
	_teardown()
	Events.trial_ended.emit(condition.skill, success, data)
	ended.emit(success)


## Drops the round without scoring it: no trial_ended, nothing in the log. For
## the debug menu, so trying a setting out does not land in the research data.
func abandon() -> void:
	if not _running:
		return
	_running = false
	_hint_at = 0.0
	_teardown()
	abandoned.emit()


## Call on every wrong attempt. Also restarts the hint clock: a child who is
## trying is not stuck.
func count_try() -> void:
	tries += 1
	_arm_hint()


func is_running() -> bool:
	return _running


func seconds() -> float:
	return _elapsed


## Stops the round's clock and its hints without ending it: nobody is there to
## play it (the child stood up from the station). The round stays out, and a pick
## made meanwhile still scores, but the time logged is only time somebody was there.
func hold(on: bool) -> void:
	_held = on


func is_held() -> bool:
	return _held


## Raises the hint level now, as if the child had waited (or asked).
func escalate() -> void:
	if not _running or _def == null or hint_level >= _def.max_hint:
		return
	hint_level += 1
	_hint(hint_level)
	_arm_hint()


# -- for subclasses ---------------------------------------------------------

## Build the round: place things, pick a target, say what to do.
func _setup(_round_condition: TrialCondition) -> void:
	pass


## Clean the round up. Called before [signal Events.trial_ended].
func _teardown() -> void:
	pass


## Render help at [param level] (1 = gentlest). What each level means is the
## trial's business; keep them ordered weakest to strongest and keep
## [member TrialDef.max_hint] in step.
func _hint(_level: int) -> void:
	pass


# -- internals --------------------------------------------------------------

func _process(delta: float) -> void:
	if not _running or _held:
		return
	_elapsed += delta
	if _hint_at > 0.0 and _elapsed >= _hint_at:
		escalate()


func _arm_hint() -> void:
	var delay := _hint_delay()
	_hint_at = _elapsed + delay if delay > 0.0 else 0.0


func _hint_delay() -> float:
	if _def == null or condition == null or condition.probe: # probes are unaided
		return 0.0
	if hint_level >= _def.max_hint or _def.hint_after <= 0.0:
		return 0.0
	return maxf(0.0, _def.hint_after + _def.hint_fade * condition.round_index)


## B / Y ("what should I do?") asks for the next hint.
func _on_reported(what: StringName, id: StringName, _data: Dictionary) -> void:
	if _running and what == &"asked" and id == &"help":
		escalate()
