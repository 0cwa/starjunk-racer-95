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
	_check(_max_abs_wheel_speed() > 0.1, "driving should create wheel angular speed")

	_race.set_realism(1.0)
	_check(is_equal_approx(_race.vehicle.realism, 1.0), "realism slider path should update vehicle handling")
	_check(is_equal_approx(float(_race.realism_slider.value), 1.0), "HUD slider should reflect programmatic realism")

	_race.reset_vehicle()
	_check(_race.vehicle.linear_velocity.length() < 0.0001, "reset should clear linear velocity immediately")
	_check(_race.vehicle.angular_velocity.length() < 0.0001, "reset should clear angular velocity immediately")
	_check(_max_abs_wheel_speed() < 0.0001, "reset should clear wheel angular speed immediately")
	var reset_position := _race.vehicle.global_position
	await get_tree().physics_frame
	_check(_finite_vec3(_race.vehicle.global_position), "vehicle position must remain finite after reset")
	_check(_race.vehicle.global_position.distance_to(reset_position) < 0.05, "vehicle should remain near spawn on the first post-reset physics frame")
	_finish()

func _physics_frames(count: int) -> void:
	for _index in range(count):
		await get_tree().physics_frame

func _max_abs_wheel_speed() -> float:
	var maximum := 0.0
	for child in _race.vehicle.get_children():
		if child is RaycastWheel3D:
			maximum = maxf(maximum, absf(child.wheel_angular_speed_rad_s))
	return maximum

func _finite_vec3(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)

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
