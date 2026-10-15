class_name VisualSkillDef
extends Resource
## One visual skill a training task practises, in words a child and a parent read.
##
## Lives at res://content/visual_skills/<id>.tres; the file name IS the visual skill id, the same
## id TrialDef.visual_skill and Training use. Shown wherever a training task is offered,
## started or signposted, so the child always knows what the practice is for.

const DIR := "res://content/visual_skills/"

@export var display_name := ""
## One short sentence: what gets better with practice.
@export_multiline var description := ""

var id: StringName:
	get:
		return StringName(resource_path.get_file().get_basename())


static func find(visual_skill_id: StringName) -> VisualSkillDef:
	var path := "%s%s.tres" % [DIR, visual_skill_id]
	return load(path) as VisualSkillDef if ResourceLoader.exists(path) else null


static func label(visual_skill_id: StringName) -> String:
	var def := find(visual_skill_id)
	if def and not def.display_name.is_empty():
		return def.display_name
	return String(visual_skill_id).capitalize()
