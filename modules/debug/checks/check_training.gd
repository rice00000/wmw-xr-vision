extends ModuleCheck
## Training: the staircase goes up after two right and down after one wrong.
##
## Moves the throwaway "selftest" visual skill, never a visual skill the game trains, so the
## number on this sign is the only thing that changes.

const VISUAL_SKILL := &"selftest_staircase"

var _trace: Array[float] = []


func _arm() -> void:
	add_button(&"right", "Right")
	add_button(&"wrong", "Wrong")
	var start: float = mod().level(VISUAL_SKILL)
	_trace = [start]
	update(_line())


func _on_press(id: StringName) -> void:
	if id != &"right" and id != &"wrong":
		return
	Events.trial_ended.emit(VISUAL_SKILL, id == &"right", {trial = &"selftest"})
	var now: float = mod().level(VISUAL_SKILL)
	_trace.append(now)
	update(_line())
	if _trace.size() < 4:
		return
	var went_up := _trace[2] > _trace[0]
	var came_down := _trace[3] < _trace[2]
	if went_up and came_down:
		pass_now(_line())
	else:
		fail_now("%s   %s" % [_line(), "no rise after two right" if not went_up else "no drop after wrong"])


func _line() -> String:
	var parts := PackedStringArray()
	for level in _trace:
		parts.append("%.2f" % level)
	return " -> ".join(parts)


func auto() -> void:
	_on_press(&"right")
	_on_press(&"right")
	_on_press(&"wrong")
