class_name SkillDef
extends Resource
## One visual skill a training task practises, in words a child and a parent read.
##
## Lives at res://content/skills/<id>.tres; the file name IS the skill id, the same
## id TrialDef.skill and Training use. Shown wherever a training task is offered,
## started or signposted, so the child always knows what the practice is for.

const DIR := "res://content/skills/"

@export var display_name := ""
## One short sentence: what gets better with practice.
@export_multiline var description := ""

var id: StringName:
	get:
		return StringName(resource_path.get_file().get_basename())


static func find(skill_id: StringName) -> SkillDef:
	var path := "%s%s.tres" % [DIR, skill_id]
	return load(path) as SkillDef if ResourceLoader.exists(path) else null


static func label(skill_id: StringName) -> String:
	var def := find(skill_id)
	if def and not def.display_name.is_empty():
		return def.display_name
	return String(skill_id).capitalize()
