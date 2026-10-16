extends Node
## Tasks module (autoload "Tasks"): the thing that drives the game.
##
## [b]One task at a time, and the one truth about it.[/b] It walks the current
## [TaskDef] through its [TaskStep]s, says each instruction (through the
## Narrator), pays the rewards when the task is done, and after every change
## publishes one [Goal] snapshot with [method Events.set_goal]: the step, its
## text, its place, its trial and how far along it is. Nothing else keeps a copy.
## The wrist, the menu, the guide and the stations draw from that snapshot, and a
## level built later reads it from [member Events.goal].
##
## Steps are matched against [signal Events.reported], so anything that reports a
## fact can advance a task without knowing tasks exist.
##
## A step that names a [member TaskStep.trial] runs measured rounds instead of
## watching for a one-off fact. The goal names the trial, and the station that
## runs it sees that and runs rounds while the child sits there. This module
## counts the rounds itself, off [signal Events.trial_ended], and ends the step on
## the last one ("finished:<trial>" is reported then, for the sound and the log).
## Steps and round counts are transient: an unfinished task restarts on reload.
## Only the active task/list identity and task completion counts are saved.
##
## Tasks knows nothing about the map. A step names a [Place] id; the guide and
## the wrist menu turn that into somewhere to walk to.
##
## [b]Layers:[/b] tasks → trials ← stations. This module reads [TrialDef] data
## (to name a task's visual skills) and nothing else from modules/trials/, and never
## touches a station: everything goes over [Events].
##
## [b]For the wrist menu[/b] (through [code]Game.module(&"Tasks")[/code]):
## [method current], [method lists], [method offers], [method accept],
## [method describe], [method remind]. The goal itself is [member Events.goal].
##
## Task data: res://content/tasks/*.tres; lists: res://content/task_lists/*.tres.
## Rewards go through Events.reward_granted; saving through Events.save_requested.
## Both modules are optional. See docs/tasks.md.

var _lists: Array[TaskListDef] = []
var _list: StringName = &""
var _current: StringName = &""
var _step := 0
## Facts counted so far on a fact step; rounds finished so far on a trial step.
var _progress := 0
var _times_done: Dictionary[StringName, int] = {}


func _ready() -> void:
	_lists = TaskListDef.all()
	Events.reported.connect(_on_reported)
	Events.trial_ended.connect(_on_trial_ended)
	Events.level_changed.connect(_on_level_changed)


# -- the menu's API ---------------------------------------------------------

## The active task id, or &"" when the child is free to pick one.
func current() -> StringName:
	return _current


## Available lists, including completed ones, in file order. UI uses these
## snapshots to group tasks; it never decides eligibility or progression.
func lists() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for list in _lists:
		if not _requirements_met(list.requires):
			continue
		var done := 0
		for task_id in list.tasks:
			if is_done(task_id):
				done += 1
		result.append({id = list.id, title = list.title, done = done,
			total = list.tasks.size(), offers = offers(list.id)})
	return result


## Acceptable task ids, optionally within a list. Nothing while one is active.
func offers(list_id: StringName = &"") -> Array[StringName]:
	var ids: Array[StringName] = []
	if not _current.is_empty():
		return ids
	for list in _lists:
		if not list_id.is_empty() and list.id != list_id:
			continue
		if not _requirements_met(list.requires):
			continue
		if list.auto_next:
			var next := _next_task(list)
			if not next.is_empty() and not ids.has(next):
				ids.append(next)
			continue
		for task_id in list.tasks:
			if _available(task_id) and not ids.has(task_id):
				ids.append(task_id)
	return ids


## The list identifies the progression policy when a task belongs to several.
## Omitting it chooses the first list offering this task, in file order.
func accept(task_id: StringName, list_id: StringName = &"") -> bool:
	for list in _lists:
		if (list_id.is_empty() or list.id == list_id) and offers(list.id).has(task_id):
			_activate(task_id, list)
			Events.report(&"accepted", task_id)
			return true
	return false


## Everything the menu shows about a task:
## [code]{title, visual_skills, rewards, place, repeatable, times_done}[/code], where
## visual_skills are display names ([method VisualSkillDef.label]). Empty for an unknown id.
func describe(task_id: StringName) -> Dictionary:
	var task := TaskDef.find(task_id)
	if task == null:
		return {}
	var visual_skills := PackedStringArray()
	for visual_skill in task.visual_skills():
		visual_skills.append(VisualSkillDef.label(visual_skill))
	var rewards: Dictionary = {}
	for item in task.rewards:
		rewards[item] = task.rewards[item]
	return {
		title = task.title,
		visual_skills = visual_skills,
		rewards = rewards,
		place = task.place(),
		repeatable = task.repeatable,
		times_done = times_done(task_id),
	}


## Says the current instruction again. Also on B / Y ("what should I do?").
## Asking again while it is being said, or still waiting to be, says it once.
func remind() -> void:
	var step := current_step()
	if step:
		Narrator.say(step.instruction, step.voice, &"task")


# -- the rest of the module --------------------------------------------------

## The current step, or null when no task is running.
func current_step() -> TaskStep:
	var task := TaskDef.find(_current)
	return task.steps[_step] if task and _step < task.steps.size() else null


func times_done(task_id: StringName) -> int:
	return _times_done.get(task_id, 0)


func is_done(task_id: StringName) -> bool:
	return times_done(task_id) > 0


func _requirements_met(required: Array[StringName]) -> bool:
	for task_id in required:
		if not is_done(task_id):
			return false
	return true


func _available(task_id: StringName) -> bool:
	var task := TaskDef.find(task_id)
	return task != null and not task.steps.is_empty() and _requirements_met(task.requires) \
		and (task.repeatable or not is_done(task_id))


func _find_list(list_id: StringName) -> TaskListDef:
	for list in _lists:
		if list.id == list_id:
			return list
	return null


## Automatic entry and progression always choose the first unfinished task.
## A completed repeatable task can still be selected from a free-choice list.
func _next_task(list: TaskListDef) -> StringName:
	if list == null or not _requirements_met(list.requires):
		return &""
	for task_id in list.tasks:
		if not is_done(task_id):
			return task_id if _available(task_id) else &""
	return &""


func _activate(task_id: StringName, list: TaskListDef) -> void:
	_current = task_id
	_list = list.id
	Events.task_started.emit(task_id)
	_enter_step(TaskDef.find(task_id), 0)
	Events.save_requested.emit()


## A new level (or another player's game) is up: say where things stand.
func _on_level_changed(_level: Node) -> void:
	remind()


## The one place the goal is made. Called after every change to the state above.
func _publish() -> void:
	var goal := Goal.new()
	var step := current_step()
	if step:
		goal.task = _current
		goal.run = times_done(_current)
		goal.step = _step
		goal.place = step.place
		goal.title = TaskDef.find(_current).title
		goal.done = _progress
		goal.needed = step.needed()
		goal.trial = step.trial
		goal.waiting_for = "" if step.is_trial() else step.event
		goal.text = step.instruction.get_slice("\n", 0)
		if step.is_trial() or step.needed() > 1:
			goal.text = "%s  (%d/%d)" % [goal.text, _progress, step.needed()]
	Events.set_goal(goal)


func _on_trial_ended(_visual_skill: StringName, _success: bool, data: Dictionary) -> void:
	var step := current_step()
	if step == null or not step.is_trial() or step.trial != StringName(str(data.get("trial", ""))):
		return
	_progress += 1
	if _progress < step.needed():
		_publish()
		return
	Events.report(&"finished", step.trial)
	_enter_step(TaskDef.find(_current), _step + 1)


func _on_reported(what: StringName, id: StringName, _data: Dictionary) -> void:
	if what == &"asked" and id == &"help":
		remind()
	var step := current_step()
	if step:
		if step.matches(what, id):
			_progress += 1
			if _progress >= step.needed():
				_enter_step(TaskDef.find(_current), _step + 1)
			else:
				_publish()
		return
	if not _current.is_empty():
		return
	for list in _lists:
		if not list.start_on.is_empty() and TaskStep.key_matches(list.start_on, what, id):
			var task_id := _next_task(list)
			if not task_id.is_empty():
				_activate(task_id, list)
				return


func _enter_step(task: TaskDef, index: int) -> void:
	_step = index
	_progress = 0
	if index < task.steps.size():
		var step := task.steps[index]
		Narrator.say(step.instruction, step.voice, &"task")
		_publish()
		return
	_complete(task)


func _complete(task: TaskDef) -> void:
	var list := _find_list(_list)
	_times_done[task.id] = times_done(task.id) + 1
	Narrator.drop(&"task")
	# Keep the active identity until rewards are applied: reward listeners cannot
	# accept another task halfway through settlement.
	for item_id in task.rewards:
		Events.reward_granted.emit(item_id, task.rewards[item_id])
	_current = &""
	_list = &""
	_step = 0
	_progress = 0
	# Completion and inventory are captured together, before announcing success.
	Events.save_requested.emit()
	if not task.rewards.is_empty():
		Events.judge(&"reward", _where_the_child_is())
	Events.task_completed.emit(task.id)
	Narrator.say(task.completed_text)
	var next := _next_task(list) if list and list.auto_next else &""
	if _current.is_empty() and not next.is_empty():
		_activate(next, list)
	else:
		_publish()


func _where_the_child_is() -> Vector3:
	var player := Game.player
	if not is_instance_valid(player):
		return Vector3.ZERO
	var head := player.get_node_or_null(^"Camera") as Node3D
	return head.global_position if head else player.global_position


func save_state() -> Dictionary:
	return {current = String(_current), list = String(_list), times_done = _times_done.duplicate()}


func load_state(data: Dictionary) -> void:
	Narrator.drop(&"task")
	_current = &""
	_list = &""
	_step = 0
	_progress = 0
	_publish() # cancel any live round before restoring a task from its beginning
	_times_done.assign(data.get("times_done", {}))
	var task_id := StringName(data.get("current", ""))
	var list_id := StringName(data.get("list", ""))
	# Older saves have no source list. Resolve it using today's availability;
	# their step/progress fields are deliberately ignored. No rewards are replayed.
	for list in _lists:
		if (list_id.is_empty() or list.id == list_id) and offers(list.id).has(task_id):
			_current = task_id
			_list = list.id
			break
	_publish()
