extends Node
## Contract tests on the real Tasks/Save/Inventory autoloads, without a world.
## Fixture lists reuse shipped tasks; no production resources are modified.

const PROFILE := &"task_lists_test"
const STONE := &"magic_stone"
var _failures := 0
var _checks := 0
var _finished := 0


func _ready() -> void:
	if Profile.id != PROFILE:
		push_error("Task-list tests require -- --profile=task_lists_test")
		get_tree().quit(2)
		return
	Narrator.read_pace = 0.0
	Narrator.min_seconds = 0.0
	_content()
	_selection()
	_progression()
	_restart()
	_persistence()
	# Let queued save requests flush before deleting this test profile's save.
	Narrator.clear()
	await get_tree().create_timer(1.5).timeout
	DirAccess.remove_absolute(Profile.path(Profile.SAVE_FILE))
	_check(_finished == 5, "all task-list contract sections reached their final assertions")
	print("TASK LIST TEST: %s (%d checks)" % ["PASSED" if _failures == 0 else "%d FAILED" % _failures, _checks])
	get_tree().quit(_failures)


func _content() -> void:
	for list in TaskListDef.all():
		var ids: Array[StringName] = []
		for task_id in list.tasks:
			var task := TaskDef.find(task_id)
			_check(task != null and not ids.has(task_id), "%s references an existing, unique task %s" % [list.id, task_id])
			ids.append(task_id)
			if task == null:
				continue
			_check(not task.steps.is_empty() and task.steps.all(func(step: TaskStep) -> bool:
				return step != null and (step.is_trial() or not step.event.is_empty())),
				"%s has completable steps" % task_id)
			for required in task.requires:
				_check(TaskDef.find(required) != null, "%s prerequisite %s exists" % [task_id, required])
		for required in list.requires:
			_check(TaskDef.find(required) != null, "%s list prerequisite %s exists" % [list.id, required])
	_finished += 1


func _selection() -> void:
	Tasks._lists = TaskListDef.all()
	Tasks.load_state({})
	var lists := Tasks.lists()
	_check(lists.size() == 1 and lists[0].id == &"tutorial" and lists[0].done == 0 and lists[0].total == 4,
		"new players see only the tutorial, with derived completion counts")
	_check(Tasks.offers(&"tutorial") == [&"welcome"] and Tasks.offers(&"practice").is_empty(),
		"tutorial offers only its first unfinished task; practice is locked")
	_check(not Tasks.accept(&"welcome", &"practice") and not Tasks.accept(&"missing", &"tutorial")
		and not Tasks.accept(&"welcome", &"missing"), "unknown tasks, lists and wrong membership cannot be accepted")
	var done := {&"welcome": 1, &"find_it": 1, &"butterflies": 1, &"first_furniture": 1}
	Tasks.load_state({times_done = done})
	lists = Tasks.lists()
	_check(lists.size() == 2 and lists[0].id == &"practice" and lists[1].id == &"tutorial"
		and lists[0].done == 2 and lists[1].done == 4, "unlocked lists have filename order and shared completion counts")
	_check(Tasks.offers(&"tutorial").is_empty() and Tasks.offers(&"practice") == [&"find_it", &"butterflies"],
		"completed automatic tasks stay skipped; free-choice repeatable tasks remain offered")
	Events.report(&"entered", &"island")
	_check(Tasks.current().is_empty(), "a completed tutorial never restarts on its entry event")
	_check(Tasks.accept(&"butterflies", &"practice") and Tasks.save_state().list == "practice",
		"accept records the explicitly selected source list")
	_check(Tasks.offers().is_empty() and not Tasks.accept(&"find_it", &"practice"), "busy tasks block all new offers and selection")
	Events.report(&"entered", &"island")
	_check(Tasks.current() == &"butterflies", "automatic entry cannot interrupt an active task")
	_finished += 1


func _progression() -> void:
	var ordered := _list("ordered", [&"welcome", &"first_furniture"], true)
	var choices := _list("choices", [&"welcome", &"first_furniture"], false)
	Tasks._lists.assign([ordered, choices])
	var done := {&"butterflies": 1}
	Tasks.load_state({times_done = done})
	_check(Tasks.offers() == [&"welcome", &"first_furniture"], "offers deduplicate tasks shared across lists")
	_check(Tasks.accept(&"welcome", &"choices"), "a shared task can be selected from the free-choice list")
	Save.reload()
	_check(Tasks.current() == &"welcome" and Tasks.save_state().list == "choices",
		"reloading a shared task preserves the explicitly selected list")
	_finish_welcome()
	_check(Tasks.current().is_empty() and Tasks.times_done(&"welcome") == 1,
		"the selected free-choice list returns to selection instead of following another list")
	_check(Tasks.lists()[0].done == 1 and Tasks.lists()[1].done == 1,
		"completing a shared task advances every list's derived count")
	Tasks.load_state({times_done = done})
	_check(Tasks.accept(&"welcome", &"ordered"), "the same task can instead use ordered progression")
	_finish_welcome()
	_check(Tasks.current() == &"first_furniture" and Tasks.save_state().list == "ordered",
		"automatic progression keeps the selected list")
	Save.reload()
	_check(Tasks.current() == &"first_furniture" and Tasks.save_state().list == "ordered",
		"automatic activation is saved with the preceding completion")
	Events.report(&"opened", &"menu")
	Events.report(&"placed", &"chair")
	_check(Tasks.current().is_empty() and Tasks.offers().is_empty(), "an automatic list ends after its final nonrepeatable task")
	Tasks._lists.assign([_list("blocked", [&"butterflies", &"welcome"], true)])
	Tasks.load_state({})
	_check(Tasks.offers().is_empty(), "a locked first unfinished task blocks later automatic tasks")
	Tasks._lists.assign([_list("free", [&"butterflies", &"welcome"], false)])
	_check(Tasks.offers() == [&"welcome"], "free-choice lists independently filter task prerequisites")
	var entry := _list("entry", [&"welcome"], false)
	entry.start_on = "entered:*"
	entry.requires.assign([&"find_it"])
	Tasks._lists.assign([entry, _list("fallback", [&"first_furniture"], false)])
	Events.report(&"entered", &"island")
	_check(Tasks.current().is_empty(), "entry events respect whole-list prerequisites")
	Tasks.load_state({times_done = {&"find_it": 1}})
	Events.report(&"entered", &"island")
	_check(Tasks.current() == &"welcome", "an unlocked list matches wildcard entry facts")
	_finish_welcome()
	_check(Tasks.current().is_empty(), "entry facts received while busy are not replayed after completion")
	var second := _list("second", [&"first_furniture"], false)
	second.start_on = "entered:*"
	Tasks._lists.assign([entry, second])
	Tasks.load_state({times_done = {&"find_it": 1, &"butterflies": 1}})
	Events.report(&"entered", &"island")
	_check(Tasks.current() == &"welcome" and Tasks.save_state().list == "entry",
		"the first eligible list wins when multiple entry events match")
	_finished += 1


func _restart() -> void:
	Tasks._lists = TaskListDef.all()
	Tasks.load_state({current = "welcome", step = 2, progress = 99})
	_check(Tasks.current() == &"welcome" and Tasks.save_state().list == "tutorial"
		and Events.goal.step == 0 and Events.goal.done == 0, "old saves resolve the source list and ignore transient progress")
	Events.report(&"grabbed", &"magic_ball")
	_check(Events.goal.step == 1, "fact steps advance and publish the new wrist objective")
	var state := Tasks.save_state()
	_check(state.size() == 3 and not state.has("step") and not state.has("progress"), "only task/list identity and completion are persisted")
	Tasks.load_state(state)
	_check(Events.goal.step == 0 and Events.goal.waiting_for == "grabbed:magic_ball", "unfinished multistage tasks restart at their first step")
	Tasks.load_state({current = "find_it", progress = 4,
		times_done = {&"welcome": 1, &"find_it": 1, &"butterflies": 1, &"first_furniture": 1}})
	_check(Tasks.current() == &"find_it" and Tasks.save_state().list == "practice" and Events.goal.done == 0,
		"legacy repeatable tasks resolve to an available practice list and restart")
	for invalid in [
		{current = "missing", list = "tutorial"},
		{current = "welcome", list = "missing"},
		{current = "welcome", list = "practice"},
		{current = "butterflies", list = "tutorial"},
	]:
		invalid.times_done = {&"welcome": 2}
		Tasks.load_state(invalid)
		_check(Tasks.current().is_empty() and Tasks.times_done(&"welcome") == 2,
			"unavailable saved selection clears safely while keeping completion: %s" % invalid)
	_finished += 1


func _persistence() -> void:
	Tasks._lists = TaskListDef.all()
	Inventory.load_state({})
	Tasks.load_state({times_done = {&"welcome": 1, &"find_it": 1, &"butterflies": 1}})
	_check(Tasks.accept(&"first_furniture", &"tutorial"), "furniture task can start after its prerequisites")
	# No Save.write(): acceptance must already have reached disk synchronously.
	Save.reload()
	_check(Tasks.current() == &"first_furniture" and Events.goal.step == 0, "activation is durable before the next frame")
	Inventory.add(&"chair", 1)
	Events.report(&"opened", &"menu")
	Events.save_requested.emit() # model a persisted purchase, with zero money left
	Save.reload()
	_check(Inventory.count(&"chair") == 1 and Inventory.count(STONE) == 0 and Events.goal.step == 0,
		"furniture restart retains the owned piece without requiring another purchase")
	Events.report(&"opened", &"menu")
	Events.report(&"placed", &"chair")
	Save.reload() # completion/reward must already be on disk, without another write
	_check(Tasks.current().is_empty() and Tasks.times_done(&"first_furniture") == 1 and Inventory.count(STONE) == 1,
		"completion and reward are durable together before the next frame")
	Save.reload()
	Events.report(&"placed", &"chair")
	_check(Tasks.times_done(&"first_furniture") == 1 and Inventory.count(STONE) == 1,
		"reloading and duplicate placement facts cannot repay a completed task")
	_check(Tasks.accept(&"find_it", &"practice"), "unlocked practice starts a repeatable task")
	Events.trial_ended.emit(&"search", true, {trial = "catch"})
	_check(Events.goal.done == 0, "unrelated trial results do not advance the active task")
	for i in 5:
		Events.trial_ended.emit(&"search", true, {trial = "search"})
	Save.reload()
	_check(Tasks.current().is_empty() and Tasks.times_done(&"find_it") == 2 and Inventory.count(STONE) == 3,
		"repeat completion saves exactly one new count and reward without auto-advancing")
	var file := FileAccess.open(Profile.path(Profile.SAVE_FILE), FileAccess.WRITE)
	file.store_string("{\"old_save\":true}")
	file.close()
	Save.reload()
	_check(Tasks.current().is_empty() and Inventory.count(STONE) == 0, "unrecognised plain JSON saves reset safely")
	_finished += 1


func _list(id: String, tasks: Array[StringName], auto_next: bool) -> TaskListDef:
	var list := TaskListDef.new()
	list.resource_path = "res://tests/fixtures/%s.tres" % id
	list.tasks = tasks
	list.auto_next = auto_next
	return list


func _finish_welcome() -> void:
	Events.report(&"grabbed", &"magic_ball")
	Events.report(&"opened", &"menu")
	Events.report(&"entered", &"picnic")


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("  [%s] %s" % ["ok" if ok else "FAIL", message])
