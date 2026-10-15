class_name TaskStep
extends Resource
## One step of a [TaskDef].
##
## A step is one of two things, and that is the whole vocabulary of the game:
## [br]- a [b]fact step[/b]: wait until "[member event]" has been reported
##   [member count] times ("caught:butterfly" ×3, "entered:meadow");
## [br]- a [b]trial step[/b]: run [member count] measured rounds of [member trial],
##   the adaptive, logged kind of round ([Trial], [TrialDef]).
##
## Both count up to [method needed]: facts reported, or rounds finished. A trial
## step's goal names the trial, and the [Station] that runs it does so while the
## child sits there; [Tasks] counts the rounds as they end.

## Fact to wait for, e.g. "caught:butterfly". "caught:*" matches any id.
## Ignored when [member trial] is set.
@export var event := ""
## Times the fact must be reported, or — for a trial step — rounds to run.
@export var count := 1
## Run this trial instead of waiting for a fact: a file name in
## res://content/trials/. The [Station] for that trial answers; its rounds start
## when the child sits down there, and until then the step simply waits.
@export var trial: StringName = &""
## Where this step happens: a [Place] id in the world. The guide leads there.
## Empty = wherever the child is (the guide stays close by).
@export var place: StringName = &""
## Shown (and spoken, with [member voice]) when the step starts.
@export_multiline var instruction := ""
@export var voice: AudioStream


## True for a step that runs measured rounds rather than watching the bus.
func is_trial() -> bool:
	return not trial.is_empty()


## Facts to count, or rounds to run.
func needed() -> int:
	return maxi(count, 1)


## Whether a reported fact counts towards this step. Never for a trial step:
## rounds are counted off the rounds themselves.
func matches(what: StringName, id: StringName) -> bool:
	return not is_trial() and TaskStep.key_matches(event, what, id)


static func key_matches(pattern: String, what: StringName, id: StringName) -> bool:
	return pattern == "%s:%s" % [what, id] or pattern == "%s:*" % what
