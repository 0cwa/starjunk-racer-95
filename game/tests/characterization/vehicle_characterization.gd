extends Node3D

const FIXED_DT := 1.0 / 60.0
const SETTLE_FRAMES := 150
const PROFILE_PATH := "res://src/vehicle/profiles/prototype_balanced_01.tres"
const BALANCE_REALISM := 1.0

var _failures := PackedStringArray()
var _output_path := ""

func _ready() -> void:
	_output_path = _parse_output_path()
	_build_floor()
	var profile: VehiclePerformanceProfile = load(PROFILE_PATH)
	_check(profile != null, "characterization profile must load")
	if profile == null:
		_finish({})
		return
	var results: Array[Dictionary] = []
	results.append(await _run_launch(profile))
	results.append(await _run_braking(profile))
	results.append(await _run_corner(profile))
	var payload := {
		"schema_version": 1,
		"physics_ticks_per_second": Engine.physics_ticks_per_second,
		"profile_id": str(profile.profile_id),
		"realism": BALANCE_REALISM,
		"scenarios": results,
	}
	for scenario in results:
		_check(_dictionary_is_finite(scenario), "%s metrics must remain finite" % str(scenario.get("scenario", "unknown")))
		_check(int(scenario.get("sample_count", 0)) > 0, "%s must produce telemetry samples" % str(scenario.get("scenario", "unknown")))
		_check(float(scenario.get("grounded_wheel_sample_ratio", 0.0)) > 0.5, "%s should retain useful road contact" % str(scenario.get("scenario", "unknown")))
	_finish(payload)

func _run_launch(profile: VehiclePerformanceProfile) -> Dictionary:
	var vehicle := await _fresh_vehicle(profile)
	var telemetry := VehicleTelemetryAccumulator.new()
	telemetry.begin(vehicle.global_position)
	vehicle.set_controls(0.65, 0.0, 0.0)
	await _sample_frames(vehicle, telemetry, 180)
	vehicle.set_controls(0.0, 0.0, 0.0)
	var result := telemetry.summary("straight_launch", profile.profile_id, BALANCE_REALISM, 0.0, vehicle.linear_velocity.length())
	_check(float(result.distance_m) > 0.5, "launch scenario should move the vehicle")
	vehicle.queue_free()
	await get_tree().physics_frame
	return result

func _run_braking(profile: VehiclePerformanceProfile) -> Dictionary:
	var vehicle := await _fresh_vehicle(profile)
	vehicle.set_controls(0.72, 0.0, 0.0)
	await _physics_frames(180)
	var start_speed := vehicle.linear_velocity.length()
	_check(start_speed > 1.0, "braking scenario needs a meaningful entry speed")
	var telemetry := VehicleTelemetryAccumulator.new()
	telemetry.begin(vehicle.global_position)
	vehicle.set_controls(0.0, 1.0, 0.0)
	await _sample_frames(vehicle, telemetry, 120)
	vehicle.set_controls(0.0, 0.0, 0.0)
	var end_speed := vehicle.linear_velocity.length()
	var result := telemetry.summary("hard_brake", profile.profile_id, BALANCE_REALISM, start_speed, end_speed)
	_check(end_speed < start_speed, "hard braking should reduce speed")
	vehicle.queue_free()
	await get_tree().physics_frame
	return result

func _run_corner(profile: VehiclePerformanceProfile) -> Dictionary:
	var vehicle := await _fresh_vehicle(profile)
	var telemetry := VehicleTelemetryAccumulator.new()
	telemetry.begin(vehicle.global_position)
	vehicle.set_controls(0.42, 0.0, 0.46)
	await _sample_frames(vehicle, telemetry, 240)
	vehicle.set_controls(0.0, 0.0, 0.0)
	var result := telemetry.summary("steady_corner", profile.profile_id, BALANCE_REALISM, 0.0, vehicle.linear_velocity.length())
	_check(float(result.max_abs_yaw_rate_rad_s) > 0.01, "corner scenario should create measurable yaw")
	vehicle.queue_free()
	await get_tree().physics_frame
	return result

func _fresh_vehicle(profile: VehiclePerformanceProfile) -> RaycastVehicleController:
	var vehicle := RaycastVehicleController.new()
	vehicle.performance_profile = profile
	vehicle.realism = BALANCE_REALISM
	vehicle.position = Vector3(0.0, 0.78, 0.0)
	vehicle.can_sleep = false
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.45, 0.42, 2.75)
	collision.shape = shape
	vehicle.add_child(collision)
	var half_track := profile.track_width_m * 0.5
	var half_wheelbase := profile.wheelbase_m * 0.5
	_add_wheel(vehicle, Vector3(-half_track, 0.0, -half_wheelbase), true, false)
	_add_wheel(vehicle, Vector3(half_track, 0.0, -half_wheelbase), true, false)
	_add_wheel(vehicle, Vector3(-half_track, 0.0, half_wheelbase), false, true)
	_add_wheel(vehicle, Vector3(half_track, 0.0, half_wheelbase), false, true)
	add_child(vehicle)
	await _physics_frames(SETTLE_FRAMES)
	_check(vehicle.grounded_wheel_count() >= 3, "fresh vehicle should settle on at least three wheels")
	return vehicle

func _add_wheel(body: RaycastVehicleController, local_position: Vector3, steerable: bool, driven: bool) -> void:
	var wheel := RaycastWheel3D.new()
	wheel.position = local_position
	wheel.steerable = steerable
	wheel.driven = driven
	body.add_child(wheel)

func _sample_frames(vehicle: RaycastVehicleController, telemetry: VehicleTelemetryAccumulator, count: int) -> void:
	for _index in range(count):
		await get_tree().physics_frame
		telemetry.sample(FIXED_DT, vehicle, vehicle.last_wheel_samples)

func _physics_frames(count: int) -> void:
	for _index in range(count):
		await get_tree().physics_frame

func _build_floor() -> void:
	var floor := StaticBody3D.new()
	floor.position = Vector3(0.0, -0.5, 0.0)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(120.0, 1.0, 120.0)
	collision.shape = shape
	floor.add_child(collision)
	add_child(floor)

func _parse_output_path() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			return arg.trim_prefix("--output=")
	return ""

func _dictionary_is_finite(values: Dictionary) -> bool:
	for value in values.values():
		if value is float and not is_finite(value):
			return false
	return true

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish(payload: Dictionary) -> void:
	var encoded := JSON.stringify(payload)
	if not payload.is_empty():
		print("STARJUNK_VEHICLE_CHARACTERIZATION_JSON:" + encoded)
		if not _output_path.is_empty():
			var file := FileAccess.open(_output_path, FileAccess.WRITE)
			if file == null:
				_failures.append("unable to write characterization output: %s" % _output_path)
			else:
				file.store_string(encoded + "\n")
	if _failures.is_empty():
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("CHARACTERIZATION FAILURE: " + failure)
	get_tree().quit(1)
