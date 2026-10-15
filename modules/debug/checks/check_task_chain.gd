extends ModuleCheck
## Tasks, narrative half: a step advances on the fact it waits for, the next
## step follows, and the reward is paid at the end.
##
## Runs res://content/tasks/selftest.tres, which is outside the game's chain (not
## offered, nothing chains to it). The Test Room runs on its own throwaway
## profile, so this simply clears the task slot and takes it: no child's progress
## is in it to keep.

const TASK := &"selftest"
const REWARD := &"magic_stone"

var _stones_before := 0


func _arm() -> void:
	add_button(&"go", "Report\na fact")
	mod().load_state({})
	_stones_before = _stones()
	mod().start(TASK)
	Events.task_completed.connect(_on_completed)
	update(_where())


func _teardown() -> void:
	if Events.task_completed.is_connected(_on_completed):
		Events.task_completed.disconnect(_on_completed)


func _on_press(id: StringName) -> void:
	if id != &"go":
		return
	# Re-read right before the fact goes out: the reward lands inside this call,
	# and other stations may have moved the count since this one was armed.
	_stones_before = _stones()
	Events.report(&"selftest", &"step")
	if verdict == Verdict.WAITING:
		update(_where())


func _on_completed(task_id: StringName) -> void:
	if task_id != TASK:
		return
	if Game.module(&"Inventory") == null:
		pass_now("both steps done (no Inventory to pay into)")
		return
	var after := _stones()
	var trace := "both steps done, %s %d -> %d" % [ItemDef.label(REWARD), _stones_before, after]
	if after == _stones_before + 1:
		pass_now(trace)
	else:
		fail_now(trace)


func _stones() -> int:
	var inventory := Game.module(&"Inventory")
	return int(inventory.count(REWARD)) if inventory else 0


func _where() -> String:
	var task := TaskDef.find(TASK)
	var step: TaskStep = mod().current_step() if mod().current() == TASK else null
	var index := task.steps.find(step) if task and step else -1
	return "not running" if index < 0 else "step %d of %d" % [index + 1, task.steps.size()]


func auto() -> void:
	_on_press(&"go")
	_on_press(&"go")
