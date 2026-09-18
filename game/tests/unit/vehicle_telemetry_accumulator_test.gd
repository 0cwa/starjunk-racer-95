extends Node

var _failures := PackedStringArray()

func _ready() -> void:
	var body := RigidBody3D.new()
	add_child(body)
	body.position = Vector3.ZERO
	var telemetry := VehicleTelemetryAccumulator.new()
	telemetry.begin(body.global_position)

	body.position = Vector3(0.0, 0.0, -1.0)
	body.linear_velocity = Vector3(1.0, 0.0, -4.0)
	body.angular_velocity = Vector3(0.0, 0.5, 0.0)
	telemetry.sample(0.5, body, [
		{"grounded": true, "slip_angle_rad": deg_to_rad(5.0), "longitudinal_slip_ratio": 0.10, "wheel_angular_speed_rad_s": 20.0},
		{"grounded": true, "slip_angle_rad": deg_to_rad(-7.0), "longitudinal_slip_ratio": -0.20, "wheel_angular_speed_rad_s": -30.0},
		{"grounded": false},
		{"grounded": false},
	])

	body.position = Vector3(0.0, 0.0, -3.0)
	body.linear_velocity = Vector3(2.0, 0.0, -6.0)
	body.angular_velocity = Vector3(0.0, -0.75, 0.0)
	telemetry.sample(0.5, body, [
		{"grounded": true, "slip_angle_rad": deg_to_rad(9.0), "longitudinal_slip_ratio": 0.30, "wheel_angular_speed_rad_s": 40.0},
		{"grounded": true, "slip_angle_rad": deg_to_rad(3.0), "longitudinal_slip_ratio": -0.40, "wheel_angular_speed_rad_s": -50.0},
		{"grounded": true, "slip_angle_rad": deg_to_rad(-1.0), "longitudinal_slip_ratio": 0.05, "wheel_angular_speed_rad_s": 10.0},
		{"grounded": true, "slip_angle_rad": deg_to_rad(-2.0), "longitudinal_slip_ratio": 0.15, "wheel_angular_speed_rad_s": 25.0},
	])

	var result := telemetry.summary("test", &"prototype", 1.0, 0.0, body.linear_velocity.length())
	_check(int(result.sample_count) == 2, "sample count should accumulate")
	_check(is_equal_approx(float(result.elapsed_seconds), 1.0), "elapsed time should accumulate")
	_check(is_equal_approx(float(result.distance_m), 3.0), "distance should accumulate from positions")
	_check(float(result.max_speed_mps) >= body.linear_velocity.length(), "max speed should include the fastest sample")
	_check(float(result.max_abs_lateral_speed_mps) >= 2.0, "lateral speed should use vehicle local X")
	_check(is_equal_approx(float(result.max_abs_yaw_rate_rad_s), 0.75), "yaw rate should use local Y")
	_check(is_equal_approx(float(result.max_abs_wheel_slip_angle_deg), 9.0), "max lateral slip should be tracked")
	_check(is_equal_approx(float(result.max_abs_longitudinal_slip_ratio), 0.40), "max longitudinal slip should be tracked")
	_check(absf(float(result.mean_abs_longitudinal_slip_ratio) - 0.20) < 0.0001, "mean longitudinal slip should use grounded wheel samples")
	_check(is_equal_approx(float(result.max_abs_wheel_angular_speed_rad_s), 50.0), "wheel angular speed should be tracked")
	_check(is_equal_approx(float(result.grounded_wheel_sample_ratio), 0.75), "grounded ratio should include all wheel samples")
	_finish()

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("Vehicle telemetry accumulator tests passed")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("TEST FAILURE: " + failure)
	get_tree().quit(1)
