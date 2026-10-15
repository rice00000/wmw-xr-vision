extends Node
## Profile (autoload "Profile"): who is playing. Several children share one
## headset, so everything that belongs to a child lives in their own folder:
## [codeblock]
## user://profiles/<id>/save.json     progress (the Save module)
## user://profiles/<id>/settings.cfg  comfort and sound (Settings)
## user://profiles/<id>/metrics/      the research log (Training)
## [/codeblock]
## The team calls each profile a save and picks it in the debug panel; a child
## never sees this.
##
## [b]Opening a profile is the one way state is replaced[/b], and boot, switching
## save, Start over and the Test Room all go through it: the world fades out,
## [signal Events.profile_closing] lets everyone write and drop what they hold,
## the level is freed, the files are swapped (or wiped), [signal
## Events.profile_opened] has every module load from them, and the first level is
## built fresh. Nothing is patched in place, so nothing from the last save or
## the last game can be left behind.
##
## Start over wipes the progress and the settings and keeps the research log,
## which marks the reset. The Test Room runs on its own throwaway profile, wiped
## every time it is opened, so hand-testing never lands in a child's data.
##
## [code]-- --profile=<id>[/code] picks one for this run only (the test suite, the
## playtest tools) without changing the headset's save.

const ROOT := "user://profiles/"
const INDEX := "user://profiles.cfg"
const TEST_ROOM := &"test_room"
const TESTBED := "res://levels/testbed/testbed.tscn"
const SAVE_FILE := "save.json"
const SETTINGS_FILE := "settings.cfg"

## The profile in use.
var id: StringName = &""

## Chosen on the command line: never written back as the headset's save.
var _pinned := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--profile="):
			id = StringName(arg.trim_prefix("--profile="))
			_pinned = true
	if not _pinned and OS.get_cmdline_args().has(TESTBED): # F6 on the Test Room
		id = TEST_ROOM
		DirAccess.remove_absolute(path(SAVE_FILE))
		DirAccess.remove_absolute(path(SETTINGS_FILE))
		return
	if id.is_empty():
		id = StringName(_index().get_value("profiles", "current", ""))
	if not _pinned and not saves().has(id):
		id = saves()[0] if not saves().is_empty() else new_save()
		_remember()


## This profile's folder, with [param file] appended. The folder exists.
func path(file := "") -> String:
	var folder := "%s%s/" % [ROOT, id]
	DirAccess.make_dir_recursive_absolute(folder)
	return folder + file


## The saves on this headset, oldest first. Not the Test Room.
func saves() -> Array[StringName]:
	var found: Array[StringName] = []
	for save: String in _index().get_value("profiles", "saves", []):
		found.append(StringName(save))
	return found


## What the debug panel calls [param save]: "Save 2", "Test Room".
func label(save: StringName = id) -> String:
	if save == TEST_ROOM:
		return "Test Room"
	if String(save).begins_with("s") and String(save).substr(1).is_valid_int():
		return "Save %s" % String(save).substr(1)
	return String(save)


## Adds a save and returns its id. Does not switch to it.
func new_save() -> StringName:
	var known := saves()
	var number := 1
	while known.has(StringName("s%d" % number)):
		number += 1
	var save := StringName("s%d" % number)
	known.append(save)
	var index := _index()
	index.set_value("profiles", "saves", known.map(func(s: StringName) -> String: return String(s)))
	index.save(INDEX)
	return save


func is_test_room() -> bool:
	return id == TEST_ROOM


## The save in use, or the one used again on leaving the Test Room.
func current_save() -> StringName:
	return id if not is_test_room() else StringName(_index().get_value("profiles", "current", ""))


## Plays [param save] from where it left off.
func switch(save: StringName) -> void:
	_open(save, false, "")


## This save's game from the very beginning: progress and settings wiped, the
## research log kept.
func start_over() -> void:
	_open(id, true, "")


## The Test Room on a fresh throwaway profile.
func open_test_room() -> void:
	_open(TEST_ROOM, true, TESTBED)


func _open(profile: StringName, wipe: bool, level: String) -> void:
	if Game.is_changing():
		return
	if level.is_empty():
		level = Game.home_level if not Game.home_level.is_empty() else Game.level.scene_file_path # F6
	Events.profile_closing.emit()
	Game.change_level(level, _swap.bind(profile, wipe))


## Between the old level going and the new one coming: no level is in the tree.
func _swap(profile: StringName, wipe: bool) -> void:
	id = profile
	if wipe:
		DirAccess.remove_absolute(path(SAVE_FILE))
		DirAccess.remove_absolute(path(SETTINGS_FILE))
	if not is_test_room():
		_remember()
	Events.profile_opened.emit(wipe)


func _remember() -> void:
	if _pinned:
		return
	var index := _index()
	index.set_value("profiles", "current", String(id))
	index.save(INDEX)


func _index() -> ConfigFile:
	var index := ConfigFile.new()
	index.load(INDEX)
	return index
