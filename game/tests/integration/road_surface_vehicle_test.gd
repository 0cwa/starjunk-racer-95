extends Node3D

var _failures := PackedStringArray()
var _asphalt: RaycastVehicleController
var _wet: RaycastVehicleController

func _ready() -> void:
	_build_floor(Vector3(-10.0, -0.5, 0.0), &"asphalt")
	_build_floor(Vector3(10.0, -0.5, 0.0), &"wet")
	_asphalt = _build_vehicle(Vector3(-10.0, 0.78, 0.0))
	_wet = _build_vehicle(Vector3(10.0, 0.78, 0.0))
	await _physics_frames(150)

	_check(_asphalt.grounded_wheel_count() >= 3, "asphalt car should settle")
	_check(_wet.grounded_wheel_count() >= 3, "wet car should settle")
	_check(_surface_id(_asphalt) == "asphalt", "asphalt wheel telemetry should identify asphalt")
	_check(_surface_id(_wet) == "wet", "wet wheel telemetry should identify wet surface")

	var asphalt_start := _asphalt.global_position.z
	var wet_start := _wet.global_position.z
	_asphalt.set_controls(1.0, 0.0, 0.0)
	_wet.set_controls(1.0, 0.0, 0.0)
	await _physics_frames(180)
	_asphalt.set_controls(0.0, 0.0, 0.0)
	_wet.set_controls(0.0, 0.0, 0.0)

	var asphalt_distance := asphalt_start - _asphalt.global_position.z
	var wet_distance := wet_start - _wet.global_position.z
	_check(asphalt_distance > 1.0, "asphalt car should accelerate")
	_check(wet_distance > 0.5, "wet car should still accelerate")
	_check(asphalt_distance > wet_distance + 0.5, "same car/input should travel farther on asphalt than wet")
	_check(_mean_grounded_grip_multiplier(_asphalt) > _mean_grounded_grip_multiplier(_wet) + 0.2, "wheel telemetry should expose lower wet grip multiplier")
	_finish()

func _build_floor(position: Vector3, surface_id: StringName) -> void:
	var floor := StaticBody3D.new()
	floor.position = position
	floor.set_meta(RoadSurfaceRegistry.METADATA_KEY, str(surface_id))
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(14.0, 1.0, 120.0)
	collision.shape = shape
	floor.add_child(collision)
	add_child(floor)

func _build_vehicle(position: Vector3) -> RaycastVehicleController:
	var profile: VehiclePerformanceProfile = load("res://src/vehicle/profiles/prototype_balanced_01.tres")
	var vehicle := RaycastVehicleController.new()
	vehicle.performance_profile = profile
	vehicle.realism = 1.0
	vehicle.position = position
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
	return vehicle

func _add_wheel(body: RaycastVehicleController, local_position: Vector3, steerable: bool, driven: bool) -> void:
	var wheel := RaycastWheel3D.new()
	wheel.position = local_position
	wheel.steerable = steerable
	wheel.driven = driven
	body.add_child(wheel)

func _surface_id(vehicle: RaycastVehicleController) -> String:
	for sample in vehicle.last_wheel_samples:
		if bool(sample.get("grounded", false)):
			return str(sample.get("surface_profile_id", ""))
	return ""

func _mean_grounded_grip_multiplier(vehicle: RaycastVehicleController) -> float:
	var total := 0.0
	var count := 0
	for sample in vehicle.last_wheel_samples:
		if bool(sample.get("grounded", false)):
			total += float(sample.get("surface_grip_multiplier", 0.0))
			count += 1
	return total / float(count) if count > 0 else 0.0

func _physics_frames(count: int) -> void:
	for _index in range(count):
		await get_tree().physics_frame

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("Road surface vehicle integration test passed")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("TEST FAILURE: " + failure)
	get_tree().quit(1)
