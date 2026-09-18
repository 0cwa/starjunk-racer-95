extends Node

var _failures := PackedStringArray()

func _ready() -> void:
	_test_simulation_is_neutral()
	_test_speed_sensitive_steering()
	_test_countersteer_direction()
	_test_yaw_stability()
	_test_grip_recovery()
	_finish()

func _test_simulation_is_neutral() -> void:
	var driver := 0.63
	var result := HandlingAssistModel.assisted_steer_input(driver, 42.0, 7.0, 0.0, 0.0)
	_check(is_equal_approx(result, driver), "zero assist must preserve driver steering")
	_check(is_zero_approx(HandlingAssistModel.yaw_stability_torque_nm(1.5, 20.0, 5.0, 900.0, 2.45, 0.0)), "zero yaw assist must produce zero torque")

func _test_speed_sensitive_steering() -> void:
	var low_speed := HandlingAssistModel.assisted_steer_input(1.0, 0.0, 0.0, 1.0, 0.0)
	var high_speed := HandlingAssistModel.assisted_steer_input(1.0, 50.0, 0.0, 1.0, 0.0)
	_check(is_equal_approx(low_speed, 1.0), "speed assist must not reduce stationary steering")
	_check(high_speed < low_speed and high_speed >= 0.5, "speed assist should reduce but not erase high-speed steering")

func _test_countersteer_direction() -> void:
	var slide_right := HandlingAssistModel.assisted_steer_input(0.0, 18.0, 6.0, 0.0, 1.0)
	var slide_left := HandlingAssistModel.assisted_steer_input(0.0, 18.0, -6.0, 0.0, 1.0)
	_check(slide_right < 0.0, "rightward chassis slide should request right countersteer")
	_check(slide_left > 0.0, "leftward chassis slide should request left countersteer")
	_check(is_equal_approx(absf(slide_right), absf(slide_left)), "countersteer should be symmetric")

func _test_yaw_stability() -> void:
	var no_slide := HandlingAssistModel.yaw_stability_torque_nm(1.0, 20.0, 0.0, 900.0, 2.45, 1.0)
	var positive_yaw := HandlingAssistModel.yaw_stability_torque_nm(1.0, 20.0, 5.0, 900.0, 2.45, 1.0)
	var negative_yaw := HandlingAssistModel.yaw_stability_torque_nm(-1.0, 20.0, 5.0, 900.0, 2.45, 1.0)
	_check(is_zero_approx(no_slide), "yaw stability should not damp non-sliding rotation")
	_check(positive_yaw < 0.0, "positive yaw should receive negative corrective torque while sliding")
	_check(negative_yaw > 0.0, "negative yaw should receive positive corrective torque while sliding")
	_check(is_equal_approx(absf(positive_yaw), absf(negative_yaw)), "yaw stability should be symmetric")

func _test_grip_recovery() -> void:
	var base := TireForceModel.DEFAULT_SLIDE_GRIP_RATIO
	var simulation := HandlingAssistModel.slide_grip_ratio(base, 0.0)
	var arcade := HandlingAssistModel.slide_grip_ratio(base, 1.0)
	_check(is_equal_approx(simulation, base), "zero recovery assist must preserve the tyre model")
	_check(arcade > base and arcade <= 1.0, "recovery assist should raise only the sliding-grip plateau")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("Handling assist model tests passed")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("TEST FAILURE: " + failure)
	get_tree().quit(1)
