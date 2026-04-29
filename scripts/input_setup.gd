extends Node

# Registers input actions at runtime so project.godot stays portable across Godot versions.

func _ready() -> void:
	_add_key_action("move_forward", [KEY_W])
	_add_key_action("move_back", [KEY_S])
	_add_key_action("move_left", [KEY_A])
	_add_key_action("move_right", [KEY_D])
	_add_key_action("jump", [KEY_SPACE])
	_add_key_action("reel", [KEY_SHIFT])
	_add_key_action("restart", [KEY_R])
	_add_key_action("interact", [KEY_E])
	_add_mouse_action("grapple", MOUSE_BUTTON_LEFT)


func _add_key_action(action: StringName, keys: Array) -> void:
	if InputMap.has_action(action):
		InputMap.erase_action(action)
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _add_mouse_action(action: StringName, button: int) -> void:
	if InputMap.has_action(action):
		InputMap.erase_action(action)
	InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
