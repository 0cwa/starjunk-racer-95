extends Node3D

var _failures := PackedStringArray()
var _vehicle: RaycastVehicleController

func _ready() -> void:
	_build_floor()
	_build_vehicle()
	await _physics_frames(150)

	_check(_vehicle.grounded_wheel_count() >= 3, "vehicle should settle with at least three grounded wheels")
	_check(_vehicle.position.y > 0.35 and _vehicle.position.y < 0.85, "settled chassis height should remain inside the suspension envelope")
	_check(_vehicle.linear_velocity.length() < 2.0, "settled vehicle should not be numerically unstable")

	var start_position := _vehicle.position
	_vehicle.set_controls(0.45, 0.0, 0.0)
	await _physics_frames(120)
	_vehicle.set_controls(0.0, 0.0, 0.0)

	_check(_vehicle.position.z < start_position.z - 0.25, "positive throttle should move the Godot-forward vehicle along -Z")
	_check(_vehicle.grounded_wheel_count() >= 2, "vehicle should retain road contact while accelerating")
	_check(_finite_vec3(_vehicle.position), "vehicle position must remain finite")
	_check(_finite_vec3(_vehicle.linear_velocity), "vehicle velocity must remain finite")
	_finish()

func _build_floor() -> void:
	var floor := StaticBody3D.new()
	floor.position = Vector3(0.0, -0.5, 0.0)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(80.0, 1.0, 80.0)
	collision.shape = shape
	floor.add_child(collision)
	add_child(floor)

func _build_vehicle() -> void:
	var profile: VehiclePerformanceProfile = load("res://src/vehicle/profiles/prototype_balanced_01.tres")
	_vehicle = RaycastVehicleController.new()
	_vehicle.performance_profile = profile
	_vehicle.realism = 0.5
	_vehicle.position = Vector3(0.0, 0.78, 0.0)
	_vehicle.can_sleep = false

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.45, 0.42, 2.75)
	collision.shape = shape
	_vehicle.add_child(collision)

	var half_track := profile.track_width_m * 0.5
	var half_wheelbase := profile.wheelbase_m * 0.5
	_add_wheel(_vehicle, Vector3(-half_track, 0.0, -half_wheelbase), true, false)
	_add_wheel(_vehicle, Vector3(half_track, 0.0, -half_wheelbase), true, false)
	_add_wheel(_vehicle, Vector3(-half_track, 0.0, half_wheelbase), false, true)
	_add_wheel(_vehicle, Vector3(half_track, 0.0, half_wheelbase), false, true)
	add_child(_vehicle)

func _add_wheel(body: RaycastVehicleController, local_position: Vector3, steerable: bool, driven: bool) -> void:
	var wheel := RaycastWheel3D.new()
	wheel.position = local_position
	wheel.steerable = steerable
	wheel.driven = driven
	body.add_child(wheel)

func _physics_frames(count: int) -> void:
	for _index in range(count):
		await get_tree().physics_frame

func _finite_vec3(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("Raycast vehicle integration test passed")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("TEST FAILURE: " + failure)
	get_tree().quit(1)
