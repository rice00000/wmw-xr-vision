class_name TaskDef
extends Resource
## One task: what the child is asked to do, in order, and what they get for it.
##
## This is the game's driver. Everything the child does is a task — the welcome,
## the measured "find the cup" rounds at the picnic table, catching butterflies,
## furnishing the house — so there is one place to look for "what happens next"
## and one way to add it. Lives at res://content/tasks/<id>.tres; the file name IS
## the task id.
##
## A task is a list of [TaskStep]s. A step either waits for a fact on the bus or
## runs rounds of a measured [Trial] (see [TrialDef]). That is the only
## distinction, and it is a data field, not a second system.
##
## The child does one task at a time ([method Tasks.current]). Which ones they may
## pick next from the wrist menu ([method Tasks.offers]) is said here too:
## [member offered], [member requires], [member repeatable].

const DIR := "res://content/tasks/"

@export var title := ""
## Starts by itself when this fact is reported and no task is running, e.g.
## "entered:island". Only once, unless [member repeatable]. Empty = only by being
## accepted from the menu or chained from another task's [member next].
@export var start_on := ""
@export var steps: Array[TaskStep] = []
## Paid when the task is done, every time. Magic Stones are the only currency, so
## in practice this is [code]{&"magic_stone": n}[/code].
@export var rewards: Dictionary[StringName, int] = {}
@export_multiline var completed_text := ""
## Task started automatically the [i]first[/i] time this one is completed. Doing a
## repeatable task again does not walk the chain again.
@export var next: StringName = &""

@export_group("Offer")
## Listed in [method Tasks.offers] once [member requires] are met. Off for tasks
## that only ever start by themselves (the welcome) or are internal (self-test).
@export var offered := true
## Tasks that must each have been completed at least once before this is offered.
@export var requires: Array[StringName] = []
## Can be done again once done, for more stones and more practice.
@export var repeatable := false
## The child may drop it from the menu. Off for the welcome, which teaches the menu.
@export var abandonable := true

var id: StringName:
	get:
		return StringName(resource_path.get_file().get_basename())


## Skill ids the task's trial steps train, in step order, without repeats.
func skills() -> Array[StringName]:
	var found: Array[StringName] = []
	for step in steps:
		if step == null or not step.is_trial():
			continue
		var trial := TrialDef.find(step.trial)
		if trial and not found.has(trial.skill):
			found.append(trial.skill)
	return found


## Where the task happens: the first step that names a [Place]. Empty = anywhere.
func place() -> StringName:
	for step in steps:
		if step and not step.place.is_empty() and step.is_trial():
			return step.place
	for step in steps:
		if step and not step.place.is_empty():
			return step.place
	return &""


static func find(task_id: StringName) -> TaskDef:
	var path := "%s%s.tres" % [DIR, task_id]
	return load(path) as TaskDef if ResourceLoader.exists(path) else null


static func all() -> Array[TaskDef]:
	var tasks: Array[TaskDef] = []
	for file in ResourceLoader.list_directory(DIR):
		var task := load(DIR + file) as TaskDef if file.ends_with(".tres") else null
		if task:
			tasks.append(task)
	return tasks
