extends ModuleCheck
## Debug: the hidden panel opens on the Menu button.
##
## The one station with nothing on its pedestal — the thing it checks is a
## controller button, and the panel appears in front of your face, not here.


func _arm() -> void:
	update("panel not opened yet")


func _tick() -> void:
	if verdict != Verdict.WAITING or not is_instance_valid(Game.player):
		return
	var panel := Game.player.get_node_or_null(^"DebugPanel") as Node3D
	if panel and panel.visible:
		pass_now("panel open in front of you")


func auto() -> void:
	Events.report(&"asked", &"menu")
	_tick()
