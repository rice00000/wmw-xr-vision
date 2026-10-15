class_name TrialDef
extends Resource
## How one kind of measured round is set up: the skill it trains, its difficulty
## axes, how quickly help arrives, how a run of rounds is shaped.
##
## A task is what the child is asked to do; a [TrialDef] is how one round of
## the measurable part of it is built. Lives at res://content/trials/<id>.tres —
## the file name IS the trial id, like ItemDef. A new trial needs a file here and
## a [Trial] subclass in modules/trials/<kind>/; a new difficulty axis needs only
## a row in [member axes]. Trials know nothing about tasks or stations: tasks
## read this file to name a task's skills, stations run the rounds it describes.

const DIR := "res://content/trials/"

@export var title := ""
## Which staircase this trial moves. Trials training the same skill share progress.
@export var skill: StringName = &"search"
@export var axes: Array[TrialAxis] = []
## Free notes: which axis is driven and why, what the contrast metric is, etc.
@export_multiline var notes := ""

@export_group("Staircase")
## Correct rounds in a row before it gets harder. 2 up / 1 down converges on
## about 71% correct, which is the usual target for this kind of training.
@export var up_after := 2
@export var step := 0.1

@export_group("Help")
## Seconds of no progress before the first hint. 0 = never hint unasked.
@export var hint_after := 8.0
## Added to [member hint_after] each round, so help fades as the child improves.
@export var hint_fade := 1.5
## Highest hint level this trial offers (see [method Trial._hint]).
@export var max_hint := 3

@export_group("Run")
## Unscored baseline rounds before training starts. Repeat the same probe later
## to get a pre / post comparison out of the log.
@export var probe_rounds := 3
## Fixed difficulty the probe rounds run at.
@export var probe_difficulty := 0.3

var id: StringName:
	get:
		return StringName(resource_path.get_file().get_basename())


static func find(trial_id: StringName) -> TrialDef:
	var path := "%s%s.tres" % [DIR, trial_id]
	return load(path) as TrialDef if ResourceLoader.exists(path) else null


## Resolves every axis at [param difficulty] into the settings for one round.
## [param overrides] pins axes by name (the debug menu).
func condition(difficulty: float, round_index := 0, probe := false, overrides: Dictionary = {}) -> TrialCondition:
	var trial_condition := TrialCondition.new()
	trial_condition.trial = id
	trial_condition.skill = skill
	trial_condition.difficulty = difficulty
	trial_condition.round_index = round_index
	trial_condition.probe = probe
	for axis in axes:
		if axis == null or axis.name.is_empty():
			continue
		var resolved: float = overrides.get(axis.name, axis.resolve(difficulty))
		trial_condition.set_value(axis.name, resolved)
	return trial_condition
