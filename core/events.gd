extends Node
## Global signal bus (autoload "Events").
##
## This is the only contract modules share. Emitters never know who listens,
## so any module can be switched off without breaking the others.

## A gameplay fact: something was caught, entered, grabbed, placed, pressed...
## Quests count these and Training logs them. Emit with [method report].
signal reported(what: StringName, id: StringName, data: Dictionary)

## Show / say an instruction to the player (subtitle + optional voice clip).
signal instruction(text: String, voice: AudioStream)

## Give the player items: quest rewards, caught creatures, pickups.
signal reward_granted(item_id: StringName, amount: int)

## One measured attempt at a visual task is over (drives difficulty + research log).
signal trial_ended(skill: StringName, success: bool, data: Dictionary)

signal quest_started(quest_id: StringName)
signal quest_completed(quest_id: StringName)

## Level flow, emitted by Game.
signal level_changing(path: String)
signal level_changed(level: Node)

## Ask the Save module to write to disk now.
signal save_requested


func report(what: StringName, id: StringName = &"", data: Dictionary = {}) -> void:
	reported.emit(what, id, data)


func say(text: String, voice: AudioStream = null) -> void:
	instruction.emit(text, voice)
