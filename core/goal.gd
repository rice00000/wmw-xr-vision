class_name Goal
extends RefCounted
## What the child should be doing right now: one snapshot of the current task
## step, published by Tasks on [signal Events.goal_changed] and kept in
## [member Events.goal] for anything that arrives later (a level's stations and
## guide, the wrist menu).
##
## Everyone who shows the goal draws it from here and keeps no copy of their own,
## so the wrist, the menu, the guide, the station's sign and its rounds can never
## disagree. A new snapshot replaces the old one whole.

## Task id; empty = nothing to do.
var task: StringName = &""
## Which time the task is being done (0 = the first), so a repeat is a new run.
var run := 0
var step := 0
## The instruction's first line, with progress, for the wrist and the menu.
var text := ""
## The [Place] id the step happens at; empty = wherever the child is.
var place: StringName = &""
## The fact a fact step waits for ("grabbed:magic_ball"); empty on a trial step.
var waiting_for := ""
## The trial a trial step runs; empty on a fact step.
var trial: StringName = &""
## The task's title, for a station's sign.
var title := ""
## Facts counted or rounds finished on this step so far.
var done := 0
## Facts or rounds the step needs.
var needed := 1


## Which step of which run this is, as text: "find_it#1/0". Empty when there is
## nothing to do.
func key() -> String:
	return "" if task.is_empty() else "%s#%d/%d" % [task, run, step]


func rounds_left() -> int:
	return maxi(needed - done, 0)


func equals(other: Goal) -> bool:
	return other != null and task == other.task and run == other.run and step == other.step and text == other.text \
		and place == other.place and waiting_for == other.waiting_for and trial == other.trial \
		and title == other.title and done == other.done and needed == other.needed
