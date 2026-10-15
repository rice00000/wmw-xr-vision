extends Node
## Global signal bus (autoload "Events").
##
## This is the only contract modules share. Emitters never know who listens,
## so any module can be switched off without breaking the others.

## A gameplay fact: something was caught, entered, grabbed, placed, pressed...
## Tasks count these and Training logs them. Emit with [method report].
signal reported(what: StringName, id: StringName, data: Dictionary)

## Show / say an instruction to the player (subtitle + optional voice clip).
signal instruction(text: String, voice: AudioStream)

## Play a stream the caller is holding, where it happened. Feedback is always paired across
## sight and sound, never colour alone, so every visual cue goes out with one of
## these. Handled by the Audio module; silent when that module is off.
signal cue(sound: AudioStream, position: Vector3)

## Give the player items: task rewards, caught creatures, pickups.
signal reward_granted(item_id: StringName, amount: int)

## Ask for measured rounds of [param trial] (a file name in res://content/trials/).
## Sent by Tasks when a task step names a trial, and answered by the station that
## runs that trial, which ignores one that is not its own. [param rounds] is how
## many are still owed (0 = until stopped); -1 withdraws the request (the task was
## dropped, or a save was loaded over it). [param title] says what the rounds are
## for, in words for the station's sign (the task's title; empty when withdrawn).
## Re-sent on every level change and reminder, so the station may arrive late.
signal trial_requested(trial: StringName, rounds: int, title: String)

## A measured attempt at a visual task is about to start. [param condition] is a
## TrialCondition.to_log() dictionary: everything the round was set up with.
signal trial_started(trial: StringName, condition: Dictionary)

## One measured attempt at a visual task is over (drives difficulty + research log).
signal trial_ended(skill: StringName, success: bool, data: Dictionary)

signal task_started(task_id: StringName)
signal task_completed(task_id: StringName)

## Level flow, emitted by Game.
signal level_changing(path: String)
signal level_changed(level: Node)

## Ask the Save module to write to disk now.
signal save_requested

## What the child should do now, and where. [param place] is a [Place] id in the
## world (empty = right here / anywhere). Sent by Tasks whenever the current step
## changes, after a load, and on a reminder; empty [param text] = nothing to do.
## The guide walks to [param place]; the wrist shows [param text].
signal goal_changed(text: String, place: StringName)

## Something the child did was judged. [param kind] is &"good", &"bad" or &"reward".
## One signal gives all three senses: Audio plays row "feedback.<kind>", the player
## rig vibrates and shows a shape mark (tick / cross / star) at [param position].
## The sender adds its own object-specific flash. Never colour alone.
signal feedback(kind: StringName, position: Vector3)

## Read [param text] aloud without a subtitle, e.g. a menu button being pointed at.
## Handled by Audio (text-to-speech when the read_aloud setting is on).
signal read_aloud(text: String)

## The wrist menu opened or closed. While it is open the game is paused.
signal menu_toggled(open: bool)

## Take one [param item_id] out of the inventory and put it in the player's hand.
## Sent by the menu's bag page; answered by the placement layout in the world,
## which moves the item from the inventory into the world.
signal place_requested(item_id: StringName)


func report(what: StringName, id: StringName = &"", data: Dictionary = {}) -> void:
	reported.emit(what, id, data)


func say(text: String, voice: AudioStream = null) -> void:
	instruction.emit(text, voice)


func play_at(sound: AudioStream, position: Vector3) -> void:
	if sound:
		cue.emit(sound, position)


func judge(kind: StringName, position: Vector3) -> void:
	feedback.emit(kind, position)
