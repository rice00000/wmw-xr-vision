extends Node
## Player settings (autoload "Settings"): comfort, sound, reading aloud.
##
## Not part of a save slot's progress, so settings survive "start over".
## Stored in user://settings.cfg, or user://settings_<slot>.cfg when launched
## with `-- --slot=<name>`, so the test suite never touches real settings.
## Read with [method value]; listen to [signal changed] to follow edits live.
## The child edits them on the wrist menu's Settings page; Audio follows the
## volumes and read_aloud, the player rig is expected to follow the rest.

signal changed(key: StringName, value: Variant)

const DEFAULTS := {
	&"volume_master": 1.0, ## 0-1
	&"volume_voice": 1.0, ## 0-1, the guide and read-aloud
	&"read_aloud": true, ## speak instructions and pointed-at menu labels
	&"subtitles": true,
	&"haptics": 1.0, ## 0-1 vibration strength
	&"move_mode": &"walk", ## &"walk" (stick + teleport) or &"teleport" (teleport only)
	&"turn_degrees": 30.0, ## snap turn step
}

var _values: Dictionary = DEFAULTS.duplicate()
var _path := "user://settings.cfg"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--slot="):
			_path = "user://settings_%s.cfg" % arg.trim_prefix("--slot=")
	reload()


## Re-reads the settings file, announcing every value that differs. A missing
## key keeps its default, so an older file never leaves a setting undefined.
func reload() -> void:
	var file := ConfigFile.new()
	var stored := {}
	if file.load(_path) == OK:
		for key: StringName in DEFAULTS:
			stored[key] = file.get_value("settings", key, DEFAULTS[key])
	for key: StringName in DEFAULTS:
		var loaded: Variant = stored.get(key, DEFAULTS[key])
		if _values[key] != loaded:
			_values[key] = loaded
			changed.emit(key, loaded)


func value(key: StringName) -> Variant:
	return _values.get(key, DEFAULTS.get(key))


func set_value(key: StringName, new_value: Variant) -> void:
	if not DEFAULTS.has(key):
		push_warning("[Settings] Unknown setting: %s" % key)
		return
	if _values[key] == new_value:
		return
	_values[key] = new_value
	changed.emit(key, new_value)
	_write()


## Everything back to [constant DEFAULTS].
func reset() -> void:
	for key: StringName in DEFAULTS:
		set_value(key, DEFAULTS[key])


func _write() -> void:
	var file := ConfigFile.new()
	for key: StringName in _values:
		file.set_value("settings", key, _values[key])
	file.save(_path)
