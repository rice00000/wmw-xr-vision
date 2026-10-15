class_name TrialRunner
extends Node
## Runs rounds of its [Trial]: asks Training for the next condition, starts the
## round, waits for it to end, pauses, goes again. When its round budget is up it
## reports "finished:<trial>" on the bus, for whoever was waiting for it.
##
## It owns the shape of a run so a new trial only has to implement one round.
## A run opens with [member TrialDef.probe_rounds] unscored baseline rounds at a
## fixed difficulty and with help off: without that baseline there is nothing to
## compare later performance against.
##
## [b]Who starts it.[/b] Whatever owns it calls [method start] and [method stop]
## (in the game, a station, when someone wants its trial and the child is sitting
## there); the runner itself listens to nothing. [member auto_start] runs it on
## its own. It knows nothing about tasks or stations.

## The trial to run; defaults to the first [Trial] child.
@export var trial: Trial
## Trial id, i.e. the file name in res://content/trials/.
@export var trial_id: StringName = &"search"
## Start without being asked, endlessly.
@export var auto_start := false
## Seconds between rounds, so feedback has time to land.
@export var gap := 1.8
## Stop after this many rounds in total. 0 = keep going. See [method budget].
@export var rounds := 0

var _round := 0
var _probes_left := 0
var _running := false
## The budget "finished" was last reported for, so a stop and a start after the
## last round do not report it twice.
var _reported_for := -1


func _ready() -> void:
	if trial == null:
		for child in get_children():
			if child is Trial:
				trial = child
				break
	if trial == null:
		push_warning("[TrialRunner] No Trial to run.")
		return
	trial.ended.connect(_on_ended)
	trial.abandoned.connect(_on_abandoned)
	configure(trial_id)
	if auto_start:
		start()


## Sets the trial id and what follows from it (the baseline probes). For whoever
## owns this runner and decides its id after the runner is ready.
func configure(id: StringName) -> void:
	trial_id = id
	var def := TrialDef.find(trial_id)
	if def == null:
		push_warning("[TrialRunner] Unknown trial: %s" % trial_id)
		return
	_probes_left = def.probe_rounds


## [param count] more rounds from now (0 = endless), counting the one in progress
## as not yet done. Does not start or stop anything.
func budget(count: int) -> void:
	rounds = 0 if count <= 0 else count + _round


## Runs rounds until the budget is spent. [param count] >= 0 also sets a new
## [method budget] first; -1 keeps the current one, which is how a run paused by
## [method stop] carries on where it left off. [param delay] seconds pass before
## the first round, e.g. while the guide finishes a line.
func start(count := -1, delay := 0.0) -> void:
	if trial == null:
		return
	if count >= 0:
		budget(count)
	if _running:
		return
	_running = true
	if delay > 0.0:
		get_tree().create_timer(delay, false).timeout.connect(_next)
	else:
		_next.call_deferred() # let the level finish coming up first


## Stops after the round in progress. That round still ends and still counts.
func stop() -> void:
	_running = false


## Stops now: no budget, and the round in progress is dropped unscored. Nothing
## is reported, because nobody wants these rounds any more.
func cancel() -> void:
	_running = false
	rounds = 0
	if trial and trial.is_running():
		trial.abandon()


func is_running() -> bool:
	return _running


## Rounds finished so far by this runner.
func round_count() -> int:
	return _round


## Rounds still to run on the current budget; -1 when endless.
func rounds_left() -> int:
	return -1 if rounds <= 0 else maxi(rounds - _round, 0)


func _next() -> void:
	if rounds > 0 and _round >= rounds:
		_running = false
		if _reported_for != rounds:
			_reported_for = rounds
			Events.report(&"finished", trial_id)
		return
	if not _running or trial.is_running():
		return
	trial.begin(_condition())


func _condition() -> TrialCondition:
	var probe := _probes_left > 0
	var training := Game.module(&"Training")
	if training:
		return training.condition(trial_id, _round, probe)
	# Training switched off: run at the trial's own baseline difficulty.
	var def := TrialDef.find(trial_id)
	if def == null:
		return TrialCondition.new()
	return def.condition(def.probe_difficulty, _round, probe)


## A dropped round is not a round: it does not count, use up a probe or finish
## the run. The next one follows as usual if the runner is still going (the debug
## menu's "skip").
func _on_abandoned() -> void:
	if not _running:
		return
	await get_tree().create_timer(gap, false).timeout
	_next()


func _on_ended(_success: bool) -> void:
	_round += 1
	_probes_left = maxi(_probes_left - 1, 0)
	# The last round owed finishes the run even if the child has just stood up.
	var spent := rounds > 0 and _round >= rounds
	if not _running and not spent:
		return
	await get_tree().create_timer(gap, false).timeout
	_next()
