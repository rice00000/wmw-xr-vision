class_name TrialCondition
extends RefCounted
## The exact settings one round runs at.
##
## A trial reads difficulty from here and nowhere else, so everything a round
## depended on can be written to the research log in one place
## ([method to_log]) and replayed later.

var trial: StringName = &""
## Staircase bucket, from the TrialDef. Trials training the same thing share one.
var visual_skill: StringName = &""
## The difficulty scalar these values were resolved from (0 = easiest).
var difficulty := 0.0
## 0-based round number in this session. Help fades as it grows.
var round_index := 0
## Unscored measurement round: no help, and the result does not move the
## staircase. Run the same probe before and after training for a pre / post.
var probe := false

var _values: Dictionary[StringName, float] = {}


func value(axis: StringName, default := 0.0) -> float:
	return _values.get(axis, default)


func set_value(axis: StringName, new_value: float) -> void:
	_values[axis] = new_value


func values() -> Dictionary[StringName, float]:
	return _values.duplicate()


## Flat dictionary for one line of the research log: axes come out as
## "axis_clutter", "axis_overlap"... next to the round's bookkeeping.
func to_log() -> Dictionary:
	var entry := {
		trial = trial,
		visual_skill = visual_skill,
		difficulty = difficulty,
		round = round_index,
		probe = probe,
	}
	for axis in _values:
		entry["axis_%s" % axis] = _values[axis]
	return entry
