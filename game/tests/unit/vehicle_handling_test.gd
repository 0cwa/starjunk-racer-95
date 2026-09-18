extends Node

var _failures := PackedStringArray()

func _ready() -> void:
	var profile: VehiclePerformanceProfile = load("res://src/vehicle/profiles/prototype_balanced_01.tres")
	_check(profile != null, "prototype profile must load")
	if profile == null:
		_finish()
		return

	_check(profile.validate().is_empty(), "prototype profile must validate")

	var arcade := HandlingResolver.resolve(profile, 0.0)
	var middle := HandlingResolver.resolve(profile, 0.5)
	var simulation := HandlingResolver.resolve(profile, 1.0)
	var below_range := HandlingResolver.resolve(profile, -4.0)
	var above_range := HandlingResolver.resolve(profile, 7.0)

	_check(is_equal_approx(float(below_range.realism), 0.0), "realism must clamp low")
	_check(is_equal_approx(float(above_range.realism), 1.0), "realism must clamp high")

	for key in [
		"mass_kg",
		"wheelbase_m",
		"track_width_m",
		"wheel_radius_m",
		"max_drive_force_n",
		"max_brake_force_n",
		"wheel_inertia_kg_m2",
		"wheel_angular_damping_n_m_s",
		"base_longitudinal_stiffness_n_per_slip",
		"base_peak_longitudinal_slip_ratio",
		"max_wheel_angular_speed_rad_s",
		"suspension_rest_length_m",
		"suspension_travel_m",
		"suspension_spring_rate_n_per_m",
		"suspension_bump_damping_n_s_per_m",
		"suspension_rebound_damping_n_s_per_m",
		"max_suspension_force_n",
		"base_grip_coefficient",
		"longitudinal_grip_bias",
	]:
		_check(is_equal_approx(float(arcade[key]), float(simulation[key])), "%s must not change with realism" % key)

	for key in [
		"countersteer_assist",
		"yaw_stability_assist",
		"drift_entry_assist",
		"grip_recovery_assist",
		"steering_speed_assist",
	]:
		_check(float(arcade[key]) > float(middle[key]), "%s should decrease toward simulation" % key)
		_check(float(middle[key]) > float(simulation[key]), "%s should remain monotonic" % key)
		_check(is_equal_approx(float(simulation[key]), 0.0), "%s should be disabled at full simulation" % key)

	_check(
		is_equal_approx(float(simulation.cornering_stiffness), profile.base_cornering_stiffness),
		"simulation cornering stiffness must equal the profile baseline"
	)
	_check(
		is_equal_approx(float(simulation.peak_slip_angle_deg), profile.base_peak_slip_angle_deg),
		"simulation peak slip angle must equal the profile baseline"
	)
	_check(float(arcade.peak_slip_angle_deg) > float(simulation.peak_slip_angle_deg), "arcade mode should widen the slip envelope")

	_finish()

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("Vehicle handling foundation tests passed")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("TEST FAILURE: " + failure)
	get_tree().quit(1)
