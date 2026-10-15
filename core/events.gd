extends Node
## Global signal bus (autoload "Events").
##
## This is the only contract modules share. Emitters never know who listens,
## so any module can be switched off without breaking the others.
##
## It also holds one piece of state: [member goal], the latest snapshot of what
## the child should do, so a station or guide that arrives with a new level reads
## where things stand instead of waiting to be told again.

## A gameplay fact: something was caught, entered, grabbed, placed, pressed...
## Tasks count these and Training logs them. Emit with [method report].
signal reported(what: StringName, id: StringName, data: Dictionary)

## Play a stream the caller is holding, where it happened. Feedback is always paired across
## sight and sound, never colour alone, so every visual cue goes out with one of
## these. Handled by the Audio module; silent when that module is off.
signal cue(sound: AudioStream, position: Vector3)

## Give the player items: task rewards, caught creatures, pickups.
signal reward_granted(item_id: StringName, amount: int)

## A measured attempt at a visual task is about to start. [param condition] is a
## TrialCondition.to_log() dictionary: everything the round was set up with.
signal trial_started(trial: StringName, condition: Dictionary)

## One measured attempt at a visual task is over (drives difficulty + research log).
signal trial_ended(visual_skill: StringName, success: bool, data: Dictionary)

signal task_started(task_id: StringName)
signal task_completed(task_id: StringName)

## Level flow, emitted by Game.
signal level_changing(path: String)
signal level_changed(level: Node)

## Ask the Save module to write to disk now. It also writes by itself after
## every fact and every round, so only a moment with neither needs this.
signal save_requested

## Someone else is about to play, or this player starts over (Profile): write
## what you hold and drop everything the world was doing. The level goes next.
signal profile_closing
## The new profile's files are in place: load from them. [param wiped] = it was
## just wiped (Start over, the Test Room). The first level is built right after.
signal profile_opened(wiped: bool)

## The goal changed: what the child should do now, where, and how far along.
## Sent by Tasks only; [member goal] holds the same snapshot for late arrivals.
## The guide walks to its place, the wrist shows its text, the station whose
## trial it names runs rounds.
signal goal_changed(goal: Goal)

## Something the child did was judged. [param kind] is &"good", &"bad" or &"reward".
## One signal gives all three senses: Audio plays row "feedback.<kind>", the player
## rig vibrates and shows a shape mark (tick / cross / star) at [param position].
## The sender adds its own object-specific flash. Never colour alone.
signal feedback(kind: StringName, position: Vector3)

## Read [param text] aloud without a subtitle, e.g. a menu button being pointed at.
## Handled by Audio (text-to-speech when the read_aloud setting is on).
signal read_aloud(text: String)

## A modal UI (ordinary menu or Debug) opened or closed. Only one is open;
## while open, play pauses and the wrist and guide subtitles hide.
signal menu_toggled(open: bool)

## Take one [param item_id] out of the inventory and put it in the player's hand.
## Sent by the menu's bag page; answered by the placement layout in the world,
## which moves the item from the inventory into the world.
signal place_requested(item_id: StringName)

## The current goal. Never null; an empty [member Goal.task] = nothing to do.
var goal := Goal.new()


func report(what: StringName, id: StringName = &"", data: Dictionary = {}) -> void:
	reported.emit(what, id, data)


## Publishes [param new_goal] when it differs from the current one. Tasks only.
func set_goal(new_goal: Goal) -> void:
	if new_goal.equals(goal):
		return
	goal = new_goal
	goal_changed.emit(goal)


func play_at(sound: AudioStream, position: Vector3) -> void:
	if sound:
		cue.emit(sound, position)


func judge(kind: StringName, position: Vector3) -> void:
	feedback.emit(kind, position)
