class_name QuestDef
extends Resource
## A linear quest: steps happen one after another.
## Lives at res://content/quests/<id>.tres. The file name IS the quest id.

const DIR := "res://content/quests/"

@export var title := ""
## Starts by itself when this fact is reported, e.g. "entered:backyard". Empty = only via start() / next.
@export var start_on := ""
@export var steps: Array[QuestStep] = []
@export var rewards: Dictionary[StringName, int] = {}
@export_multiline var completed_text := ""
## Quest started automatically when this one is completed.
@export var next: StringName = &""

var id: StringName:
	get:
		return StringName(resource_path.get_file().get_basename())


static func find(quest_id: StringName) -> QuestDef:
	var path := "%s%s.tres" % [DIR, quest_id]
	return load(path) as QuestDef if ResourceLoader.exists(path) else null


static func all() -> Array[QuestDef]:
	var quests: Array[QuestDef] = []
	for file in ResourceLoader.list_directory(DIR):
		var quest := load(DIR + file) as QuestDef if file.ends_with(".tres") else null
		if quest:
			quests.append(quest)
	return quests
