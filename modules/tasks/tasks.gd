extends Node
## Tasks module (autoload "Tasks"): the thing that drives the game.
##
## [b]One task at a time.[/b] It walks the current [TaskDef] through its
## [TaskStep]s, says each instruction, tells everyone what to do and where
## ([signal Events.goal_changed]), and pays the rewards when the task is done.
## Steps are matched against [signal Events.reported], so anything that reports a
## fact can advance a task without knowing tasks exist.
##
## A step that names a [member TaskStep.trial] asks for measured rounds instead of
## watching for a one-off fact: the request goes out as
## [signal Events.trial_requested] (with the task's title, for the sign) and the
## station that runs that trial answers it.
## The step then waits for "finished:<trial>" like any other fact, so measured
## play and narrative play are one list, not two systems. When a trial step is
## left early (abandoned, or a save is loaded over it) the request is withdrawn
## by sending it again with [code]rounds = -1[/code].
##
## Tasks knows nothing about the map. A step names a [Place] id; the guide and
## the wrist menu turn that into somewhere to walk to.
##
## [b]Layers:[/b] tasks → trials ← stations. This module reads [TrialDef] data
## (to name a task's skills) and nothing else from modules/trials/, and never
## touches a station: requests and facts go over [Events].
##
## [b]For the wrist menu[/b] (through [code]Game.module(&"Tasks")[/code]):
## [method current], [method goal], [method goal_place], [method offers],
## [method accept], [method abandon], [method describe], [method remind].
##
## Task data: res://content/tasks/*.tres. Rewards go out as
## [signal Events.reward_granted], so this works with or without an Inventory.

## Sent with [signal Events.trial_requested] to take a request back.
const WITHDRAWN := -1

var _defs: Array[TaskDef] = []
var _current: StringName = &""
var _step := 0
## Facts counted so far on a fact step.
var _progress := 0
## Rounds finished so far on a trial step. The step still ends on
## "finished:<trial>"; this is what the goal line and the station sign count.
var _rounds := 0
var _times_done: Dictionary[StringName, int] = {}
## When the last reward line will have been heard (ticks, ms). Lines this module
## says before then wait their turn, so the next task's first instruction never
## cuts "here is your Magic Stone" off.
var _line_free_at := 0
## About how long a line takes to be read out, in ms per character. The smoke
## test turns it down so it does not sit through every line.
var line_pace := 65


func _ready() -> void:
	_defs = TaskDef.all()
	Events.reported.connect(_on_reported)
	Events.trial_ended.connect(_on_trial_ended)
	Events.level_changed.connect(_on_level_changed)
	# After loading a save, say the current instruction once the first level is up.
	Events.level_changed.connect(func(_level: Node) -> void: remind(), CONNECT_ONE_SHOT)


# -- the menu's API ---------------------------------------------------------

## The active task id, or &"" when the child is free to pick one.
func current() -> StringName:
	return _current


## One short line for the wrist and the menu: what to do now, and how far along.
## Empty when no task is running.
func goal() -> String:
	var step := current_step()
	if step == null:
		return ""
	var line := step.instruction.get_slice("\n", 0)
	if step.is_trial():
		return "%s  (%d/%d)" % [line, _rounds, maxi(step.count, 1)]
	if step.needed() > 1:
		return "%s  (%d/%d)" % [line, _progress, step.needed()]
	return line


## The [Place] id the current step happens at. Empty = wherever the child is.
func goal_place() -> StringName:
	var step := current_step()
	return step.place if step else &""


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
	_withdraw()
	_current = &""
	_step = 0
	_progress = 0
	_rounds = 0
	Events.save_requested.emit()
	_announce()
	return true


## Everything the menu shows about a task:
## [code]{title, skills, rewards, place, repeatable, times_done, can_abandon}[/code], where
## skills are display names ([method SkillDef.label]). Empty for an unknown id.
func describe(task_id: StringName) -> Dictionary:
	var task := TaskDef.find(task_id)
	if task == null:
		return {}
	var skills := PackedStringArray()
	for skill in task.skills():
		skills.append(SkillDef.label(skill))
	var rewards: Dictionary = {}
	for item in task.rewards:
		rewards[item] = task.rewards[item]
	return {
		title = task.title,
		skills = skills,
		rewards = rewards,
		place = task.place(),
		repeatable = task.repeatable,
		can_abandon = task.abandonable,
		times_done = times_done(task_id),
	}


## Says the current instruction again, re-announces the goal and re-asks for any
## trial still owed. Also on B / Y ("what should I do?").
func remind() -> void:
	var step := current_step()
	if step:
		Events.say(step.instruction, step.voice)
	_announce()


# -- the rest of the module --------------------------------------------------

## The current step, or null when no task is running.
func current_step() -> TaskStep:
	var task := TaskDef.find(_current)
	return task.steps[_step] if task and _step < task.steps.size() else null


## The fact the current step is waiting for ("grabbed:magic_ball",
## "finished:search"), or "" when idle. Lets a scene node such as the guide
## react to a step without knowing which task it belongs to.
func waiting_for() -> String:
	var step := current_step()
	return step.key() if step else ""


## Rounds done and rounds needed on the current trial step; (0, 0) otherwise.
func rounds() -> Vector2i:
	var step := current_step()
	return Vector2i(_rounds, maxi(step.count, 1)) if step and step.is_trial() else Vector2i.ZERO


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


func _on_level_changed(_level: Node) -> void:
	_announce.call_deferred() # the level's stations and guide may only just exist


## Tells everyone what to do now and asks for any rounds still owed.
func _announce() -> void:
	Events.goal_changed.emit(goal(), goal_place())
	var step := current_step()
	if step and step.is_trial():
		Events.trial_requested.emit(step.trial, maxi(step.count - _rounds, 1), TaskDef.find(_current).title)


## Takes back the request a trial step made, so its station stands down.
func _withdraw() -> void:
	var step := current_step()
	if step and step.is_trial():
		Events.trial_requested.emit(step.trial, WITHDRAWN, "")


func _on_trial_ended(_skill: StringName, _success: bool, data: Dictionary) -> void:
	var step := current_step()
	if step and step.is_trial() and step.trial == StringName(str(data.get("trial", ""))):
		_rounds += 1
		# Only the line changes. Re-asking here would count this round twice: the
		# station has not finished its own bookkeeping for it yet.
		Events.goal_changed.emit(goal(), goal_place())


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
				Events.goal_changed.emit(goal(), goal_place())
		return
	for task in _defs:
		if not task.start_on.is_empty() and TaskStep.key_matches(task.start_on, what, id):
			if start(task.id):
				return


func _enter_step(task: TaskDef, index: int) -> void:
	_step = index
	_progress = 0
	_rounds = 0
	if index < task.steps.size():
		var step := task.steps[index]
		_say(step.instruction, step.voice, _step_key())
		_announce()
		return
	_complete(task)


func _complete(task: TaskDef) -> void:
	var first := times_done(task.id) == 0
	_times_done[task.id] = times_done(task.id) + 1
	_current = &""
	_step = 0
	for item_id in task.rewards:
		Events.reward_granted.emit(item_id, task.rewards[item_id])
	if not task.rewards.is_empty():
		Events.judge(&"reward", _where_the_child_is())
	Events.task_completed.emit(task.id)
	if not task.completed_text.is_empty():
		_say(task.completed_text, null, "", true)
	if first and not task.next.is_empty() and start(task.next):
		Events.save_requested.emit()
		return
	_announce() # nothing to do: the menu offers what is next
	Events.save_requested.emit()


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
		rounds = _rounds,
		times_done = _times_done.duplicate(),
	}


func load_state(data: Dictionary) -> void:
	_withdraw()
	_current = StringName(str(data.get("current", "")))
	_step = _number(data.get("step", 0))
	_progress = _number(data.get("progress", 0))
	_rounds = _number(data.get("rounds", 0))
	_times_done.clear()
	var done: Variant = data.get("times_done", {})
	if done is Dictionary:
		for task_id in done:
			_times_done[StringName(str(task_id))] = _number(done[task_id])
	if not _current.is_empty() and current_step() == null: # the task file changed under the save
		_current = &""
	_resume.call_deferred()


## A saved count, or 0 when the save is from an older version and holds
## something else there.
static func _number(value: Variant) -> int:
	return int(value) if value is int or value is float else 0


## After a load. A save made in the pause after a trial step's last round holds
## every round but not the "finished" that would have ended the step: end it now
## rather than ask for one round more than the step wants.
func _resume() -> void:
	var step := current_step()
	if step and step.is_trial() and _rounds >= maxi(step.count, 1):
		_enter_step(TaskDef.find(_current), _step + 1)
		return
	_announce()


## Says a line of this module's, after any line still being heard that must not
## be cut off. [param hold] makes this line one of those: the reward line. A line
## that has to wait its turn also holds the next one back, so they come out in
## order. [param key] ties a delayed line to its step ([method _step_key]), so a
## step already left by the time its turn comes is not announced.
func _say(text: String, voice: AudioStream = null, key := "", hold := false) -> void:
	var now := Time.get_ticks_msec()
	var at := maxi(now, _line_free_at)
	if at > now or hold:
		_line_free_at = at + _line_ms(text)
	if at == now:
		Events.say(text, voice)
		return
	get_tree().create_timer((at - now) / 1000.0, false).timeout.connect(func() -> void:
		if key.is_empty() or key == _step_key():
			Events.say(text, voice))


func _step_key() -> String:
	return "%s/%d" % [_current, _step]


## About how long a line takes to read out or read, in ms.
func _line_ms(text: String) -> int:
	return clampi(text.length() * line_pace, 30 * line_pace, 110 * line_pace)
