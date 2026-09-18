extends Node

var _failures := PackedStringArray()

func _ready() -> void:
	_check(is_zero_approx(WheelSlipKinematics.slip_angle_rad(0.0, 0.0)), "stationary wheel must have zero slip angle")
	_check(is_zero_approx(WheelSlipKinematics.slip_angle_rad(20.0, 0.0)), "straight velocity must have zero slip angle")

	var angle := WheelSlipKinematics.slip_angle_rad(10.0, 1.0)
	_check(angle > 0.0, "rightward contact velocity must produce positive slip angle")
	_check(absf(angle - atan2(1.0, 10.0)) < 0.000001, "normal-speed slip angle must use forward speed")

	var mirror := WheelSlipKinematics.slip_angle_rad(10.0, -1.0)
	_check(absf(angle + mirror) < 0.000001, "slip-angle calculation must be symmetric")

	var low_speed := WheelSlipKinematics.slip_angle_rad(0.05, 0.05)
	_check(absf(low_speed) < deg_to_rad(10.0), "low-speed floor must suppress near-rest angle explosion")

	const RADIUS := 0.32
	var rolling_omega := WheelSlipKinematics.wheel_angular_speed_for_rolling(12.0, RADIUS)
	_check(absf(rolling_omega * RADIUS - 12.0) < 0.000001, "rolling angular speed must match road speed")
	_check(absf(WheelSlipKinematics.longitudinal_slip_ratio(12.0, rolling_omega, RADIUS)) < 0.000001, "pure rolling must have zero longitudinal slip")

	var locked := WheelSlipKinematics.longitudinal_slip_ratio(12.0, 0.0, RADIUS)
	_check(absf(locked + 1.0) < 0.000001, "locked wheel at forward speed must have -1 slip ratio")

	var spinning := WheelSlipKinematics.longitudinal_slip_ratio(10.0, 50.0, RADIUS)
	_check(spinning > 0.0, "wheel overspeed must produce positive acceleration slip")

	var low_speed_ratio := WheelSlipKinematics.longitudinal_slip_ratio(0.01, 0.0, RADIUS)
	_check(absf(low_speed_ratio) < 0.05, "near-rest longitudinal slip must remain small and finite")

	_check(is_zero_approx(WheelSlipKinematics.longitudinal_slip_ratio(10.0, 20.0, 0.0)), "invalid wheel radius must safely return zero slip")
	_check(is_zero_approx(WheelSlipKinematics.wheel_angular_speed_for_rolling(10.0, 0.0)), "invalid wheel radius must safely return zero rolling speed")

	_finish()

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("Wheel slip kinematics tests passed")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("TEST FAILURE: " + failure)
	get_tree().quit(1)
