class_name VoiceLine
extends RefCounted
## One line the guide says: the words on the subtitle and, when there is one, the
## recording. Queued and timed by the Narrator; see core/narrator.gd.

var text := ""
var voice: AudioStream
## Who the line speaks for (&"task", &"station", &"trial"). A newer line on the
## same topic replaces one still waiting, so a stale instruction is never heard.
var topic: StringName = &""


func _init(line_text := "", line_voice: AudioStream = null, line_topic: StringName = &"") -> void:
	text = line_text
	voice = line_voice
	topic = line_topic
