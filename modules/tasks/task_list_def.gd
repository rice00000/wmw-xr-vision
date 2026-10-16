class_name TaskListDef
extends Resource
## An ordered collection of task ids, stored in content/task_lists/<id>.tres.
## Tasks may belong to several lists; completion and rewards belong to the task.
## Lists keep no saved cursor: Tasks derives progress from completed tasks.

const DIR := "res://content/task_lists/"

@export var title := ""
@export var tasks: Array[StringName] = []
## True: offer the first unfinished task and advance after each completion.
## False: offer all unlocked, unfinished or repeatable tasks for free selection.
@export var auto_next := false
## Tasks that must have been completed before this list becomes available.
@export var requires: Array[StringName] = []
## Start the first unfinished task when this fact occurs and no task is active.
## Empty means the player selects from the menu. Completed lists never auto-start.
@export var start_on := ""

var id: StringName:
	get:
		return StringName(resource_path.get_file().get_basename())


static func all() -> Array[TaskListDef]:
	var lists: Array[TaskListDef] = []
	var files := ResourceLoader.list_directory(DIR)
	files.sort()
	for file in files:
		var list := load(DIR + file) as TaskListDef if file.ends_with(".tres") else null
		if list:
			lists.append(list)
	return lists
