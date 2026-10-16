class_name TaskDef
extends Resource
## One task: what the child is asked to do, in order, and what they get for it.
##
## This is the game's driver. Everything the child does is a task — the welcome,
## the measured "find the cup" rounds at the picnic table, catching butterflies,
## furnishing the house. TaskListDef owns selection and automatic progression.
## Lives at res://content/tasks/<id>.tres; the file name is the task id.
##
## A task is a list of [TaskStep]s. A step either waits for a fact on the bus or
## runs rounds of a measured [Trial] (see [TrialDef]). That is the only
## distinction, and it is a data field, not a second system.
##
## The child does one task at a time ([method Tasks.current]). Which ones they may
## pick next depends on its list, [member requires] and [member repeatable].
## See docs/tasks.md for the content authoring contract.

const DIR := "res://content/tasks/"

@export var title := ""
@export var steps: Array[TaskStep] = []
## Paid when the task is done, every time. Magic Stones are the only currency, so
## in practice this is [code]{&"magic_stone": n}[/code].
@export var rewards: Dictionary[StringName, int] = {}
@export_multiline var completed_text := ""

@export_group("Availability")
## Tasks that must each have been completed at least once before this is offered.
@export var requires: Array[StringName] = []
## Can be done again once done, for more stones and more practice.
@export var repeatable := false

var id: StringName:
	get:
		return StringName(resource_path.get_file().get_basename())


## Visual skill ids the task's trial steps train, in step order, without repeats.
func visual_skills() -> Array[StringName]:
	var found: Array[StringName] = []
	for step in steps:
		if step == null or not step.is_trial():
			continue
		var trial := TrialDef.find(step.trial)
		if trial and not found.has(trial.visual_skill):
			found.append(trial.visual_skill)
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
