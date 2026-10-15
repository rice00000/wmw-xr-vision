extends ModuleCheck
## Tasks, narrative half: a step advances on the fact it waits for, the next
## step follows, and the reward is paid at the end.
##
## Runs res://content/tasks/selftest.tres, which is outside the game's chain (not
## offered, nothing chains to it). Tasks runs one task at a time, so whatever the
## child was doing is put aside while this station holds the slot and put back the
## moment it decides (or the room is left), so hand-testing never shows up in a
## child's progress.

const TASK := &"selftest"
const REWARD := &"magic_stone"

var _stones_before := 0
## The child's own task progress, while this station has borrowed the slot.
var _saved := {}
var _holding := false


func _arm() -> void:
	add_button(&"go", "Report\na fact")
	_saved = mod().save_state()
	_holding = true
	mod().load_state({})
	_stones_before = _stones()
	mod().start(TASK)
	Events.task_completed.connect(_on_completed)
	update(_where())


func _teardown() -> void:
	if Events.task_completed.is_connected(_on_completed):
		Events.task_completed.disconnect(_on_completed)
	_give_back()


func _exit_tree() -> void:
	_give_back()


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
	# Synchronously, before Tasks asks for a save: the save must hold the child's
	# task, not this one.
	_give_back()
	if Game.module(&"Inventory") == null:
		pass_now("both steps done (no Inventory to pay into)")
		return
	var after := _stones()
	var trace := "both steps done, %s %d -> %d" % [ItemDef.label(REWARD), _stones_before, after]
	if after == _stones_before + 1:
		pass_now(trace)
	else:
		fail_now(trace)


func _give_back() -> void:
	if not _holding or mod() == null:
		return
	_holding = false
	mod().load_state(_saved)


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
