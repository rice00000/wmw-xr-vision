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
## The count is saved with everything else, so a reload carries on with the right
## round and the right number of baseline probes.
##
## Tasks knows nothing about the map. A step names a [Place] id; the guide and
## the wrist menu turn that into somewhere to walk to.
##
## [b]Layers:[/b] tasks → trials ← stations. This module reads [TrialDef] data
## (to name a task's visual skills) and nothing else from modules/trials/, and never
## touches a station: everything goes over [Events].
##
## [b]For the wrist menu[/b] (through [code]Game.module(&"Tasks")[/code]):
## [method current], [method offers], [method accept], [method abandon],
## [method describe], [method remind]. The goal itself is [member Events.goal].
##
## Task data: res://content/tasks/*.tres. Rewards go out as
## [signal Events.reward_granted], so this works with or without an Inventory.

var _defs: Array[TaskDef] = []
var _current: StringName = &""
var _step := 0
## Facts counted so far on a fact step; rounds finished so far on a trial step.
var _progress := 0
var _times_done: Dictionary[StringName, int] = {}


func _ready() -> void:
	_defs = TaskDef.all()
	Events.reported.connect(_on_reported)
	Events.trial_ended.connect(_on_trial_ended)
	Events.level_changed.connect(_on_level_changed)


# -- the menu's API ---------------------------------------------------------

## The active task id, or &"" when the child is free to pick one.
func current() -> StringName:
	return _current


## Task ids the child can accept now, in file order. Empty while one is running.
func offers() -> Array[StringName]:
	var ids: Array[StringName] = []
	if not _current.is_empty():
		return ids
	for task in _defs:
		if not task.offered or (times_done(task.id) > 0 and not task.repeatable):
			continue
		var met := true
		for needed in task.requires:
			met = met and times_done(needed) > 0
		if met:
			ids.append(task.id)
	return ids


## Starts [param task_id] if it is on offer. Reports "accepted:<id>".
func accept(task_id: StringName) -> bool:
	if not offers().has(task_id):
		return false
	Events.report(&"accepted", task_id)
	return start(task_id)


## Drops the current task, progress and all. Refused for a task that is not
## [member TaskDef.abandonable] (the welcome). Returns whether it was dropped.
func abandon() -> bool:
	var task := TaskDef.find(_current)
	if task == null or not task.abandonable:
		return false
	_current = &""
	_step = 0
	_progress = 0
	Narrator.drop(&"task")
	_publish()
	return true


## Everything the menu shows about a task:
## [code]{title, visual_skills, rewards, place, repeatable, times_done, can_abandon}[/code], where
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
		can_abandon = task.abandonable,
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


## Starts a task whether or not it is on offer: a chain, [member TaskDef.start_on],
## the Test Room. Refused while another task is running, or for a task already
## done that is not repeatable.
func start(task_id: StringName) -> bool:
	if not _current.is_empty():
		return false
	var task := TaskDef.find(task_id)
	if task == null:
		push_warning("[Tasks] Unknown task: %s" % task_id)
		return false
	if times_done(task_id) > 0 and not task.repeatable:
		return false
	_current = task_id
	Events.task_started.emit(task_id)
	_enter_step(task, 0)
	return true


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
	for task in _defs:
		if not task.start_on.is_empty() and TaskStep.key_matches(task.start_on, what, id):
			if start(task.id):
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
	var first := times_done(task.id) == 0
	_times_done[task.id] = times_done(task.id) + 1
	_current = &""
	_step = 0
	Narrator.drop(&"task")
	for item_id in task.rewards:
		Events.reward_granted.emit(item_id, task.rewards[item_id])
	if not task.rewards.is_empty():
		Events.judge(&"reward", _where_the_child_is())
	Events.task_completed.emit(task.id)
	Narrator.say(task.completed_text) # on no topic, so the next task's first line queues behind it
	if first and not task.next.is_empty() and start(task.next):
		return
	_publish() # nothing to do: the menu offers what is next


func _where_the_child_is() -> Vector3:
	var player := Game.player
	if not is_instance_valid(player):
		return Vector3.ZERO
	var head := player.get_node_or_null(^"Camera") as Node3D
	return head.global_position if head else player.global_position


func save_state() -> Dictionary:
	return {
		current = String(_current),
		step = _step,
		progress = _progress,
		times_done = _times_done.duplicate(),
	}


func load_state(data: Dictionary) -> void:
	_current = StringName(data.get("current", ""))
	_step = data.get("step", 0)
	_progress = data.get("progress", 0)
	_times_done.assign(data.get("times_done", {}))
	if not _current.is_empty() and current_step() == null: # the task file changed under the save
		_current = &""
	_publish()
