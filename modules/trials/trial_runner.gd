class_name TrialRunner
extends Node
## Starts rounds of its [Trial]: asks Training for the condition of round
## [i]n[/i] and hands it over. Whoever owns the runner decides when a round runs
## and which round it is (in the game, a station, from the goal); the runner
## keeps no count of its own, so there is nothing here to fall out of step.
##
## A run opens with [member TrialDef.probe_rounds] unscored baseline rounds at a
## fixed difficulty and with help off: without that baseline there is nothing to
## compare later performance against. Round [i]n[/i] is a probe when [i]n[/i] is
## below that number, so a run carried on after a reload is no different.
##
## It knows nothing about tasks or stations.

## The trial to run; defaults to the first [Trial] child.
@export var trial: Trial
## Trial id, i.e. the file name in res://content/trials/.
@export var trial_id: StringName = &"search"


func _ready() -> void:
	if trial == null:
		for child in get_children():
			if child is Trial:
				trial = child
				break
	if trial == null:
		push_warning("[TrialRunner] No Trial to run.")


## Starts round [param round_index] (0 = the first of this run) unless one is
## already running.
func run(round_index: int) -> void:
	if trial == null or trial.is_running():
		return
	trial.begin(_condition(round_index))


## Drops the round in progress unscored: nobody wants it any more.
func cancel() -> void:
	if trial and trial.is_running():
		trial.abandon()


func is_running() -> bool:
	return trial != null and trial.is_running()


func _condition(round_index: int) -> TrialCondition:
	var def := TrialDef.find(trial_id)
	if def == null:
		push_warning("[TrialRunner] Unknown trial: %s" % trial_id)
		return TrialCondition.new()
	var probe := round_index < def.probe_rounds
	var training := Game.module(&"Training")
	if training:
		return training.condition(trial_id, round_index, probe)
	# Training switched off: run at the trial's own baseline difficulty.
	return def.condition(def.probe_difficulty, round_index, probe)
