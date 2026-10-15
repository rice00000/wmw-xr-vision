extends ModuleCheck
## Inventory: a granted item lands in the count.

@export var item: StringName = &"magic_stone"


func _arm() -> void:
	add_button(&"grant", "Give 1\n%s" % ItemDef.label(item))
	update("%s %d" % [ItemDef.label(item), mod().count(item)])


func _on_press(id: StringName) -> void:
	if id != &"grant":
		return
	var before: int = mod().count(item)
	Events.reward_granted.emit(item, 1)
	var after: int = mod().count(item)
	var trace := "%s %d -> %d" % [ItemDef.label(item), before, after]
	if after == before + 1:
		pass_now(trace)
	else:
		fail_now(trace)


func auto() -> void:
	_on_press(&"grant")
