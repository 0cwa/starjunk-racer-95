class_name DefaultInputBindings
extends RefCounted

static func ensure_defaults() -> void:
	_add_key_action(&"drive_throttle", [KEY_W, KEY_UP])
	_add_key_action(&"drive_brake", [KEY_S, KEY_DOWN])
	_add_key_action(&"drive_steer_left", [KEY_A, KEY_LEFT])
	_add_key_action(&"drive_steer_right", [KEY_D, KEY_RIGHT])
	_add_key_action(&"race_reset", [KEY_R])
	_add_key_action(&"realism_decrease", [KEY_BRACKETLEFT])
	_add_key_action(&"realism_increase", [KEY_BRACKETRIGHT])

	_add_axis_action(&"drive_steer_left", JOY_AXIS_LEFT_X, -1.0)
	_add_axis_action(&"drive_steer_right", JOY_AXIS_LEFT_X, 1.0)
	_add_axis_action(&"drive_brake", JOY_AXIS_TRIGGER_LEFT, 1.0)
	_add_axis_action(&"drive_throttle", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_add_button_action(&"race_reset", JOY_BUTTON_BACK)

static func _add_key_action(action: StringName, physical_keys: Array[int]) -> void:
	_ensure_action(action)
	for keycode in physical_keys:
		var event := InputEventKey.new()
		event.physical_keycode = keycode
		_add_event_if_missing(action, event)

static func _add_axis_action(action: StringName, axis: JoyAxis, axis_value: float) -> void:
	_ensure_action(action)
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = axis_value
	_add_event_if_missing(action, event)

static func _add_button_action(action: StringName, button: JoyButton) -> void:
	_ensure_action(action)
	var event := InputEventJoypadButton.new()
	event.button_index = button
	_add_event_if_missing(action, event)

static func _ensure_action(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)

static func _add_event_if_missing(action: StringName, event: InputEvent) -> void:
	for existing in InputMap.action_get_events(action):
		if existing.as_text() == event.as_text():
			return
	InputMap.action_add_event(action, event)
