extends ModuleCheck
## Save: a number written to disk comes back after a reload.

var value := 0


func _arm() -> void:
	add_button(&"add", "Add 1")
	add_button(&"check", "Save +\nreload")
	update("counter %d" % value)


func _on_press(id: StringName) -> void:
	match id:
		&"add":
			value += 1
			update("counter %d" % value)
		&"check":
			var wanted := value
			mod().write()
			value = -1 # clobber it: only a real restore can put it back
			mod().reload() # re-read without writing first, which would cheat
			if value == wanted:
				pass_now("counter %d came back off disk" % value)
			else:
				fail_now("wanted %d, got %d" % [wanted, value])


func auto() -> void:
	_on_press(&"add")
	_on_press(&"check")


func save_state() -> Dictionary:
	return {value = value}


func load_state(data: Dictionary) -> void:
	value = data.get("value", 0)
