class_name VehicleTelemetryAccumulator
extends RefCounted

var sample_count: int = 0
var elapsed_seconds: float = 0.0
var distance_m: float = 0.0
var max_speed_mps: float = 0.0
var _speed_sum_mps: float = 0.0
var max_abs_lateral_speed_mps: float = 0.0
var max_abs_yaw_rate_rad_s: float = 0.0
var max_abs_wheel_slip_angle_deg: float = 0.0
var _abs_wheel_slip_angle_sum_deg: float = 0.0
var max_abs_longitudinal_slip_ratio: float = 0.0
var _abs_longitudinal_slip_sum: float = 0.0
var max_abs_wheel_angular_speed_rad_s: float = 0.0
var _grounded_wheel_samples: int = 0
var _wheel_samples: int = 0
var _previous_position := Vector3.ZERO
var _started := false

func begin(position: Vector3) -> void:
	_previous_position = position
	_started = true

func sample(delta_seconds: float, body: RigidBody3D, wheel_samples: Array[Dictionary]) -> void:
	if not _started:
		begin(body.global_position)
	if delta_seconds <= 0.0:
		return
	var basis := body.global_transform.basis.orthonormalized()
	var speed := body.linear_velocity.length()
	var lateral_speed := body.linear_velocity.dot(basis.x)
	var yaw_rate := body.angular_velocity.dot(basis.y)
	distance_m += body.global_position.distance_to(_previous_position)
	_previous_position = body.global_position
	elapsed_seconds += delta_seconds
	sample_count += 1
	_speed_sum_mps += speed
	max_speed_mps = maxf(max_speed_mps, speed)
	max_abs_lateral_speed_mps = maxf(max_abs_lateral_speed_mps, absf(lateral_speed))
	max_abs_yaw_rate_rad_s = maxf(max_abs_yaw_rate_rad_s, absf(yaw_rate))
	for wheel_sample in wheel_samples:
		_wheel_samples += 1
		if not bool(wheel_sample.get("grounded", false)):
			continue
		_grounded_wheel_samples += 1
		var slip_deg := absf(rad_to_deg(float(wheel_sample.get("slip_angle_rad", 0.0))))
		_abs_wheel_slip_angle_sum_deg += slip_deg
		max_abs_wheel_slip_angle_deg = maxf(max_abs_wheel_slip_angle_deg, slip_deg)
		var longitudinal_slip := absf(float(wheel_sample.get("longitudinal_slip_ratio", 0.0)))
		_abs_longitudinal_slip_sum += longitudinal_slip
		max_abs_longitudinal_slip_ratio = maxf(max_abs_longitudinal_slip_ratio, longitudinal_slip)
		max_abs_wheel_angular_speed_rad_s = maxf(
			max_abs_wheel_angular_speed_rad_s,
			absf(float(wheel_sample.get("wheel_angular_speed_rad_s", 0.0)))
		)

func summary(scenario: String, profile_id: StringName, realism: float, start_speed_mps: float = 0.0, end_speed_mps: float = 0.0) -> Dictionary:
	var mean_speed := _speed_sum_mps / float(sample_count) if sample_count > 0 else 0.0
	var mean_abs_slip := _abs_wheel_slip_angle_sum_deg / float(_grounded_wheel_samples) if _grounded_wheel_samples > 0 else 0.0
	var mean_abs_longitudinal_slip := _abs_longitudinal_slip_sum / float(_grounded_wheel_samples) if _grounded_wheel_samples > 0 else 0.0
	var grounded_ratio := float(_grounded_wheel_samples) / float(_wheel_samples) if _wheel_samples > 0 else 0.0
	return {
		"scenario": scenario,
		"profile_id": str(profile_id),
		"realism": realism,
		"sample_count": sample_count,
		"elapsed_seconds": elapsed_seconds,
		"distance_m": distance_m,
		"start_speed_mps": start_speed_mps,
		"end_speed_mps": end_speed_mps,
		"mean_speed_mps": mean_speed,
		"max_speed_mps": max_speed_mps,
		"max_abs_lateral_speed_mps": max_abs_lateral_speed_mps,
		"max_abs_yaw_rate_rad_s": max_abs_yaw_rate_rad_s,
		"mean_abs_wheel_slip_angle_deg": mean_abs_slip,
		"max_abs_wheel_slip_angle_deg": max_abs_wheel_slip_angle_deg,
		"mean_abs_longitudinal_slip_ratio": mean_abs_longitudinal_slip,
		"max_abs_longitudinal_slip_ratio": max_abs_longitudinal_slip_ratio,
		"max_abs_wheel_angular_speed_rad_s": max_abs_wheel_angular_speed_rad_s,
		"grounded_wheel_sample_ratio": grounded_ratio,
	}
