extends Node
## Quest module (autoload "Quests"): step-by-step quests driven by Events.reported.
## Quest data: res://content/quests/*.tres (QuestDef). Completing a quest grants its
## rewards through Events.reward_granted, so it works with or without an Inventory.

var _defs: Array[QuestDef] = []
var _active: Dictionary[StringName, Vector2i] = {} # quest id -> (step index, progress)
var _done: Dictionary[StringName, bool] = {}


func _ready() -> void:
	_defs = QuestDef.all()
	Events.reported.connect(_on_reported)
	# After loading a save, repeat the current instructions once the first level is up.
	Events.level_changed.connect(func(_level: Node) -> void: remind(), CONNECT_ONE_SHOT)


func start(quest_id: StringName) -> void:
	if _active.has(quest_id) or _done.has(quest_id):
		return
	var quest := QuestDef.find(quest_id)
	if quest == null:
		push_warning("[Quests] Unknown quest: %s" % quest_id)
		return
	Events.quest_started.emit(quest_id)
	_enter_step(quest, 0)


func is_active(quest_id: StringName) -> bool:
	return _active.has(quest_id)


func is_done(quest_id: StringName) -> bool:
	return _done.has(quest_id)


func current_step(quest_id: StringName) -> QuestStep:
	var quest := QuestDef.find(quest_id)
	return quest.steps[_active[quest_id].x] if quest and _active.has(quest_id) else null


## Repeat the instruction of every active step.
func remind() -> void:
	for quest_id in _active:
		var step := current_step(quest_id)
		if step:
			Events.say(step.instruction, step.voice)


func _on_reported(what: StringName, id: StringName, _data: Dictionary) -> void:
	if what == &"asked" and id == &"help":
		remind()
	for quest_id in _active.keys():
		var step := current_step(quest_id)
		if step == null or not step.matches(what, id):
			continue
		var state := _active[quest_id] + Vector2i(0, 1)
		if state.y < step.count:
			_active[quest_id] = state
		else:
			_enter_step(QuestDef.find(quest_id), state.x + 1)
	for quest in _defs:
		if not quest.start_on.is_empty() and QuestStep.key_matches(quest.start_on, what, id):
			start(quest.id)


func _enter_step(quest: QuestDef, index: int) -> void:
	if index < quest.steps.size():
		_active[quest.id] = Vector2i(index, 0)
		var step := quest.steps[index]
		Events.say(step.instruction, step.voice)
		return
	_active.erase(quest.id)
	_done[quest.id] = true
	for item_id in quest.rewards:
		Events.reward_granted.emit(item_id, quest.rewards[item_id])
	Events.quest_completed.emit(quest.id)
	Events.say(quest.completed_text)
	Events.save_requested.emit()
	if not quest.next.is_empty():
		start(quest.next)


func save_state() -> Dictionary:
	return {active = _active.duplicate(), done = _done.keys()}


func load_state(data: Dictionary) -> void:
	_active.assign(data.get("active", {}))
	_done.clear()
	for quest_id: StringName in data.get("done", []):
		_done[quest_id] = true
