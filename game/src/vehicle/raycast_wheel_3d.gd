class_name RaycastWheel3D
extends RayCast3D

@export var steerable: bool = false
@export var driven: bool = false

var _previous_compression_m: float = 0.0
var last_sample: Dictionary = {}

func configure(profile: VehiclePerformanceProfile) -> void:
	target_position = Vector3.DOWN * (profile.suspension_rest_length_m + profile.wheel_radius_m)
	enabled = true
	exclude_parent = true

func sample_and_apply(
		body: RigidBody3D,
		delta_seconds: float,
		handling: Dictionary,
		steer_angle_rad: float,
		drive_force_request_n: float,
		brake_force_request_n: float
) -> Dictionary:
	force_raycast_update()
	if not is_colliding():
		_previous_compression_m = 0.0
		last_sample = {"grounded": false}
		return last_sample

	var contact_point := get_collision_point()
	var surface_normal := get_collision_normal().normalized()
	var wheel_radius := float(handling["wheel_radius_m"])
	var contact_distance := maxf(global_position.distance_to(contact_point) - wheel_radius, 0.0)
	var compression := SuspensionModel.compression_m(
		float(handling["suspension_rest_length_m"]),
		contact_distance,
		float(handling["suspension_travel_m"])
	)
	var compression_velocity := SuspensionModel.compression_velocity_mps(
		_previous_compression_m,
		compression,
		delta_seconds
	)
	_previous_compression_m = compression

	var normal_force := SuspensionModel.normal_force_n(
		compression,
		compression_velocity,
		float(handling["suspension_spring_rate_n_per_m"]),
		float(handling["suspension_bump_damping_n_s_per_m"]),
		float(handling["suspension_rebound_damping_n_s_per_m"]),
		float(handling["max_suspension_force_n"])
	)

	var body_basis := body.global_transform.basis
	var body_up := body_basis.y.normalized()
	var wheel_forward := (-body_basis.z).normalized()
	if steerable:
		wheel_forward = Basis(body_up, steer_angle_rad) * wheel_forward

	# Tyre forces belong in the road tangent plane even when the track is banked.
	wheel_forward = wheel_forward.slide(surface_normal).normalized()
	if wheel_forward.length_squared() < 0.000001:
		last_sample = {"grounded": true, "normal_force_n": normal_force}
		body.apply_force(body_up * normal_force, contact_point - body.global_position)
		return last_sample
	var wheel_right := wheel_forward.cross(surface_normal).normalized()

	var force_offset := contact_point - body.global_position
	var point_velocity := body.linear_velocity + body.angular_velocity.cross(force_offset)
	var longitudinal_speed := point_velocity.dot(wheel_forward)
	var lateral_speed := point_velocity.dot(wheel_right)
	var slip_angle := WheelSlipKinematics.slip_angle_rad(longitudinal_speed, lateral_speed)

	var lateral_force := TireForceModel.lateral_force_n(
		slip_angle,
		normal_force,
		float(handling["base_grip_coefficient"]),
		float(handling["cornering_stiffness"]),
		float(handling["peak_slip_angle_deg"])
	)

	var longitudinal_force := drive_force_request_n
	if brake_force_request_n > 0.0 and absf(longitudinal_speed) > 0.05:
		longitudinal_force -= signf(longitudinal_speed) * brake_force_request_n

	var combined := TireForceModel.clamp_combined_forces(
		longitudinal_force,
		lateral_force,
		normal_force,
		float(handling["base_grip_coefficient"]),
		float(handling["longitudinal_grip_bias"])
	)

	var suspension_force := body_up * normal_force
	var tyre_force := wheel_forward * combined.x + wheel_right * combined.y
	body.apply_force(suspension_force + tyre_force, force_offset)

	last_sample = {
		"grounded": true,
		"contact_point": contact_point,
		"compression_m": compression,
		"normal_force_n": normal_force,
		"longitudinal_speed_mps": longitudinal_speed,
		"lateral_speed_mps": lateral_speed,
		"slip_angle_rad": slip_angle,
		"longitudinal_force_n": combined.x,
		"lateral_force_n": combined.y,
	}
	return last_sample
