extends Node

var _failures := PackedStringArray()
var _race: PrototypeRace

func _ready() -> void:
	var packed: PackedScene = load("res://src/race/prototype_race.tscn")
	_check(packed != null, "prototype race scene should load")
	if packed == null:
		_finish()
		return

	_race = packed.instantiate()
	_race.input_enabled = false
	add_child(_race)
	await get_tree().process_frame

	_check(_race.vehicle != null, "prototype race should build a player vehicle")
	_check(_race.checkpoint_count() == 8, "prototype race should build eight ordered checkpoints")
	_check(_race.realism_slider != null, "prototype race should expose the realism slider")
	_check(InputMap.has_action("drive_throttle"), "prototype race should register default input actions")

	await _physics_frames(150)
	_check(_race.vehicle.grounded_wheel_count() >= 3, "prototype car should settle on the test surface")

	var start := _race.vehicle.global_position
	_race.vehicle.set_controls(0.45, 0.0, 0.0)
	await _physics_frames(90)
	_race.vehicle.set_controls(0.0, 0.0, 0.0)
	_check(_race.vehicle.global_position.distance_to(start) > 0.25, "prototype car should respond to throttle")

	_race.set_realism(1.0)
	_check(is_equal_approx(_race.vehicle.realism, 1.0), "realism slider path should update vehicle handling")
	_check(is_equal_approx(float(_race.realism_slider.value), 1.0), "HUD slider should reflect programmatic realism")

	_race.reset_vehicle()
	await get_tree().physics_frame
	_check(_race.vehicle.linear_velocity.length() < 0.05, "reset should clear linear velocity")
	_check(_race.vehicle.angular_velocity.length() < 0.05, "reset should clear angular velocity")
	_finish()

func _physics_frames(count: int) -> void:
	for _index in range(count):
		await get_tree().physics_frame

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("Playable prototype race integration test passed")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("TEST FAILURE: " + failure)
	get_tree().quit(1)
