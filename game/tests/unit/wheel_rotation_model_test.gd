extends Node

var _failures := PackedStringArray()

func _ready() -> void:
	var accelerated := WheelRotationModel.integrate_angular_speed(
		0.0, 100.0, 0.0, 0.0, 0.0, 1.0, 0.1, 500.0
	)
	_check(is_equal_approx(accelerated, 10.0), "drive torque should accelerate wheel angular speed")

	var reacted := WheelRotationModel.integrate_angular_speed(
		10.0, 0.0, 0.0, -50.0, 0.0, 1.0, 0.1, 500.0
	)
	_check(is_equal_approx(reacted, 5.0), "tyre reaction torque should feed back into wheel speed")

	var stopped := WheelRotationModel.integrate_angular_speed(
		2.0, 0.0, 100.0, 0.0, 0.0, 1.0, 0.1, 500.0
	)
	_check(is_zero_approx(stopped), "brake torque should stop without reversing the wheel")

	var reverse_stopped := WheelRotationModel.integrate_angular_speed(
		-2.0, 0.0, 100.0, 0.0, 0.0, 1.0, 0.1, 500.0
	)
	_check(is_zero_approx(reverse_stopped), "braking should be symmetric in reverse")

	var damped := WheelRotationModel.integrate_angular_speed(
		20.0, 0.0, 0.0, 0.0, 2.0, 2.0, 0.1, 500.0
	)
	_check(damped < 20.0 and damped > 0.0, "angular damping should reduce free spin")

	var capped := WheelRotationModel.integrate_angular_speed(
		0.0, 10000.0, 0.0, 0.0, 0.0, 1.0, 1.0, 120.0
	)
	_check(is_equal_approx(capped, 120.0), "wheel speed should respect trusted angular speed cap")
	_finish()

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("Wheel rotation model tests passed")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("TEST FAILURE: " + failure)
	get_tree().quit(1)
