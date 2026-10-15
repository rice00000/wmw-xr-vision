class_name TrialAxis
extends Resource
## One difficulty dimension of a trial: clutter, overlap, contrast...
##
## It maps the trial's single 0-1 difficulty scalar onto a real value the task
## uses. The staircase stays one-dimensional, so it still converges, while every
## axis keeps a name, a logged value and its own range.
##
## Only [member driven] axes follow the difficulty. The rest sit at a fixed value
## and are logged anyway, so a failed round stays attributable to one variable
## instead of four moving at once.

## Looked up with [method TrialCondition.value], e.g. &"clutter".
@export var name: StringName = &""
## Value at difficulty 0.0. May be larger than [member hard]: contrast goes
## *down* as a round gets harder.
@export var easy := 0.0
## Value at difficulty 1.0.
@export var hard := 1.0
## Follow the difficulty scalar. Keep exactly one axis per trial driven unless you
## have a reason not to, and say which one in the trial's notes.
@export var driven := false
## Value used while [member driven] is off. NAN sits at [member easy].
@export var fixed := NAN
## Optional shaping of the 0-1 difficulty before the easy -> hard mix.
@export var curve: Curve


func resolve(difficulty: float) -> float:
	if not driven:
		return easy if is_nan(fixed) else fixed
	var t := curve.sample(difficulty) if curve else difficulty
	return lerpf(easy, hard, clampf(t, 0.0, 1.0))
