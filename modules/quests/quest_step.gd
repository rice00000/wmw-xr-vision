class_name QuestStep
extends Resource
## One quest step: done once a fact ("what:id") has been reported [member count] times.

## Fact to wait for, e.g. "caught:butterfly_blue". "caught:*" matches any id.
@export var event := "entered:home"
@export var count := 1
## Shown (and spoken, with [member voice]) when the step starts.
@export_multiline var instruction := ""
@export var voice: AudioStream


func matches(what: StringName, id: StringName) -> bool:
	return QuestStep.key_matches(event, what, id)


static func key_matches(pattern: String, what: StringName, id: StringName) -> bool:
	return pattern == "%s:%s" % [what, id] or pattern == "%s:*" % what
