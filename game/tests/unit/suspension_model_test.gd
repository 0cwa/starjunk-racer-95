extends Node

var _failures := PackedStringArray()

func _ready() -> void:
	_check(is_zero_approx(SuspensionModel.compression_m(0.34, 0.34, 0.18)), "rest length must have zero compression")
	_check(absf(SuspensionModel.compression_m(0.34, 0.25, 0.18) - 0.09) < 0.000001, "contact distance must map to compression")
	_check(absf(SuspensionModel.compression_m(0.34, 0.0, 0.18) - 0.18) < 0.000001, "compression must clamp to travel")
	_check(is_zero_approx(SuspensionModel.compression_m(0.34, 0.5, 0.18)), "droop must not create negative compression")

	var velocity := SuspensionModel.compression_velocity_mps(0.05, 0.07, 0.01)
	_check(absf(velocity - 2.0) < 0.000001, "compression velocity must be positive during bump")
	_check(is_zero_approx(SuspensionModel.compression_velocity_mps(0.0, 1.0, 0.0)), "invalid delta must be safe")

	const SPRING := 26000.0
	const BUMP := 3200.0
	const REBOUND := 4300.0
	const MAX_FORCE := 16000.0

	var static_force := SuspensionModel.normal_force_n(0.10, 0.0, SPRING, BUMP, REBOUND, MAX_FORCE)
	_check(absf(static_force - 2600.0) < 0.001, "static spring force must follow Hooke's law")

	var bump_force := SuspensionModel.normal_force_n(0.10, 0.25, SPRING, BUMP, REBOUND, MAX_FORCE)
	_check(bump_force > static_force, "bump damping must increase upward normal force")

	var rebound_force := SuspensionModel.normal_force_n(0.10, -0.25, SPRING, BUMP, REBOUND, MAX_FORCE)
	_check(rebound_force < static_force, "rebound damping must reduce upward normal force while extending")
	_check(rebound_force >= 0.0, "suspension must never pull the car toward the road")

	var fast_rebound := SuspensionModel.normal_force_n(0.01, -20.0, SPRING, BUMP, REBOUND, MAX_FORCE)
	_check(is_zero_approx(fast_rebound), "large rebound damping must clamp at zero instead of pulling")

	var bottomed := SuspensionModel.normal_force_n(0.18, 20.0, SPRING, BUMP, REBOUND, MAX_FORCE)
	_check(absf(bottomed - MAX_FORCE) < 0.001, "suspension force must clamp at configured maximum")

	_finish()

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("Suspension model tests passed")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("TEST FAILURE: " + failure)
	get_tree().quit(1)
