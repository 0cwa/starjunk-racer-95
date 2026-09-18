class_name RaycastVehicleController
extends RigidBody3D

@export var performance_profile: VehiclePerformanceProfile
@export_range(0.0, 1.0, 0.01) var realism: float = 0.35
@export_range(5.0, 50.0, 0.1) var max_steer_angle_deg: float = 28.0

var throttle_input: float = 0.0
var brake_input: float = 0.0
var steer_input: float = 0.0
var last_wheel_samples: Array[Dictionary] = []
var last_assist_state: Dictionary = {}

var _wheels: Array[RaycastWheel3D] = []

func _ready() -> void:
	if performance_profile == null:
		performance_profile = load("res://src/vehicle/profiles/prototype_balanced_01.tres")
	_refresh_wheels()
	_apply_profile()

func set_controls(throttle: float, brake: float, steer: float) -> void:
	throttle_input = clampf(throttle, -1.0, 1.0)
	brake_input = clampf(brake, 0.0, 1.0)
	steer_input = clampf(steer, -1.0, 1.0)
	if not is_zero_approx(throttle_input) or brake_input > 0.0 or not is_zero_approx(steer_input):
		sleeping = false

func grounded_wheel_count() -> int:
	var count := 0
	for sample in last_wheel_samples:
		if bool(sample.get("grounded", false)):
			count += 1
	return count

func _physics_process(delta: float) -> void:
	if performance_profile == null or _wheels.is_empty():
		return

	var handling := HandlingResolver.resolve(performance_profile, realism)
	var driven_count := 0
	for wheel in _wheels:
		if wheel.driven:
			driven_count += 1

	var drive_force_per_wheel := 0.0
	if driven_count > 0:
		drive_force_per_wheel = (
			throttle_input
			* float(handling["max_drive_force_n"])
			/ float(driven_count)
		)
	var brake_force_per_wheel := (
		brake_input
		* float(handling["max_brake_force_n"])
		/ float(_wheels.size())
	)
	var body_basis := global_transform.basis.orthonormalized()
	var forward_speed_mps := linear_velocity.dot(-body_basis.z)
	var lateral_speed_mps := linear_velocity.dot(body_basis.x)
	var assisted_steer_input := HandlingAssistModel.assisted_steer_input(
		steer_input,
		forward_speed_mps,
		lateral_speed_mps,
		float(handling["steering_speed_assist"]),
		float(handling["countersteer_assist"])
	)
	var steer_angle := deg_to_rad(max_steer_angle_deg) * assisted_steer_input
	var yaw_stability_torque_nm := HandlingAssistModel.yaw_stability_torque_nm(
		angular_velocity.dot(body_basis.y),
		forward_speed_mps,
		lateral_speed_mps,
		mass,
		float(handling["wheelbase_m"]),
		float(handling["yaw_stability_assist"])
	)
	if not is_zero_approx(yaw_stability_torque_nm):
		apply_torque(body_basis.y * yaw_stability_torque_nm)

	last_assist_state = {
		"driver_steer_input": steer_input,
		"assisted_steer_input": assisted_steer_input,
		"forward_speed_mps": forward_speed_mps,
		"lateral_speed_mps": lateral_speed_mps,
		"yaw_stability_torque_nm": yaw_stability_torque_nm,
	}

	last_wheel_samples.clear()
	for wheel in _wheels:
		last_wheel_samples.append(wheel.sample_and_apply(
			self,
			delta,
			handling,
			steer_angle,
			drive_force_per_wheel if wheel.driven else 0.0,
			brake_force_per_wheel
		))

func _refresh_wheels() -> void:
	_wheels.clear()
	for child in get_children():
		if child is RaycastWheel3D:
			_wheels.append(child)
	for wheel in _wheels:
		wheel.configure(performance_profile)

func _apply_profile() -> void:
	if performance_profile == null:
		return
	var problems := performance_profile.validate()
	if not problems.is_empty():
		push_error("Invalid vehicle performance profile: %s" % "; ".join(problems))
		return
	mass = performance_profile.mass_kg
