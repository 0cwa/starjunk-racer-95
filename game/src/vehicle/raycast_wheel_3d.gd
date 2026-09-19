class_name RaycastWheel3D
extends RayCast3D

@export var steerable: bool = false
@export var driven: bool = false

var wheel_angular_speed_rad_s: float = 0.0
var _previous_compression_m: float = 0.0
var _wheel_radius_m: float = 0.31
var last_sample: Dictionary = {}

func configure(profile: VehiclePerformanceProfile) -> void:
	_wheel_radius_m = profile.wheel_radius_m
	target_position = Vector3.DOWN * (profile.suspension_rest_length_m + profile.wheel_radius_m)
	enabled = true
	exclude_parent = true

func reset_rotation_state(longitudinal_speed_mps: float = 0.0) -> void:
	wheel_angular_speed_rad_s = WheelSlipKinematics.wheel_angular_speed_for_rolling(
		longitudinal_speed_mps,
		_wheel_radius_m
	)
	_previous_compression_m = 0.0
	last_sample = {}

func sample_and_apply(
		body: RigidBody3D,
		delta_seconds: float,
		handling: Dictionary,
		steer_angle_rad: float,
		drive_force_request_n: float,
		brake_force_request_n: float
) -> Dictionary:
	var wheel_radius := float(handling["wheel_radius_m"])
	var drive_torque_nm := drive_force_request_n * wheel_radius
	var brake_torque_nm := brake_force_request_n * wheel_radius

	force_raycast_update()
	if not is_colliding():
		_previous_compression_m = 0.0
		wheel_angular_speed_rad_s = WheelRotationModel.integrate_angular_speed(
			wheel_angular_speed_rad_s,
			wheel_angular_speed_rad_s,
			drive_torque_nm,
			brake_torque_nm,
			0.0,
			float(handling["wheel_angular_damping_n_m_s"]),
			float(handling["wheel_inertia_kg_m2"]),
			delta_seconds,
			float(handling["max_wheel_angular_speed_rad_s"])
		)
		last_sample = {
			"grounded": false,
			"driven": driven,
			"wheel_angular_speed_rad_s": wheel_angular_speed_rad_s,
			"longitudinal_slip_ratio": 0.0,
		}
		return last_sample

	var contact_point := get_collision_point()
	var surface_profile_id := RoadSurfaceRegistry.profile_id_for_collider(get_collider())
	var surface_profile := RoadSurfaceRegistry.resolve(surface_profile_id)
	var surface_grip_multiplier := float(surface_profile["grip_multiplier"])
	var surface_normal := get_collision_normal().normalized()
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

	wheel_forward = wheel_forward.slide(surface_normal).normalized()
	if wheel_forward.length_squared() < 0.000001:
		var force_offset_fallback := contact_point - body.global_position
		body.apply_force(body_up * normal_force, force_offset_fallback)
		wheel_angular_speed_rad_s = WheelRotationModel.integrate_angular_speed(
			wheel_angular_speed_rad_s,
			wheel_angular_speed_rad_s,
			drive_torque_nm,
			brake_torque_nm,
			0.0,
			float(handling["wheel_angular_damping_n_m_s"]),
			float(handling["wheel_inertia_kg_m2"]),
			delta_seconds,
			float(handling["max_wheel_angular_speed_rad_s"])
		)
		last_sample = {
			"grounded": true,
			"driven": driven,
			"normal_force_n": normal_force,
			"surface_profile_id": str(surface_profile_id),
			"surface_grip_multiplier": surface_grip_multiplier,
			"wheel_angular_speed_rad_s": wheel_angular_speed_rad_s,
			"longitudinal_slip_ratio": 0.0,
		}
		return last_sample
	var wheel_right := wheel_forward.cross(surface_normal).normalized()

	var force_offset := contact_point - body.global_position
	var point_velocity := body.linear_velocity + body.angular_velocity.cross(force_offset)
	var longitudinal_speed := point_velocity.dot(wheel_forward)
	var lateral_speed := point_velocity.dot(wheel_right)
	var slip_angle := WheelSlipKinematics.slip_angle_rad(longitudinal_speed, lateral_speed)
	var longitudinal_slip_ratio := WheelSlipKinematics.longitudinal_slip_ratio(
		longitudinal_speed,
		wheel_angular_speed_rad_s,
		wheel_radius
	)

	var slide_grip_ratio := HandlingAssistModel.slide_grip_ratio(
		TireForceModel.DEFAULT_SLIDE_GRIP_RATIO,
		float(handling["grip_recovery_assist"])
	)
	var surface_grip := float(handling["base_grip_coefficient"]) * surface_grip_multiplier
	var lateral_force := TireForceModel.lateral_force_n(
		slip_angle,
		normal_force,
		surface_grip,
		float(handling["cornering_stiffness"]) * float(surface_profile["lateral_stiffness_multiplier"]),
		float(handling["peak_slip_angle_deg"]) * float(surface_profile["peak_slip_angle_multiplier"]),
		slide_grip_ratio
	)
	var longitudinal_force := TireForceModel.longitudinal_force_n(
		longitudinal_slip_ratio,
		normal_force,
		surface_grip * float(handling["longitudinal_grip_bias"]),
		float(handling["base_longitudinal_stiffness_n_per_slip"]) * float(surface_profile["longitudinal_stiffness_multiplier"]),
		float(handling["base_peak_longitudinal_slip_ratio"]) * float(surface_profile["peak_longitudinal_slip_multiplier"]),
		slide_grip_ratio
	)

	var combined := TireForceModel.clamp_combined_forces(
		longitudinal_force,
		lateral_force,
		normal_force,
		surface_grip,
		float(handling["longitudinal_grip_bias"])
	)

	var suspension_force := body_up * normal_force
	var tyre_force := wheel_forward * combined.x + wheel_right * combined.y
	body.apply_force(suspension_force + tyre_force, force_offset)

	var tyre_reaction_torque_nm := -combined.x * wheel_radius
	wheel_angular_speed_rad_s = WheelRotationModel.integrate_angular_speed(
		wheel_angular_speed_rad_s,
		WheelSlipKinematics.wheel_angular_speed_for_rolling(longitudinal_speed, wheel_radius),
		drive_torque_nm,
		brake_torque_nm,
		tyre_reaction_torque_nm,
		float(handling["wheel_angular_damping_n_m_s"]),
		float(handling["wheel_inertia_kg_m2"]),
		delta_seconds,
		float(handling["max_wheel_angular_speed_rad_s"])
	)

	last_sample = {
		"grounded": true,
		"driven": driven,
		"contact_point": contact_point,
		"compression_m": compression,
		"normal_force_n": normal_force,
		"surface_profile_id": str(surface_profile_id),
		"surface_grip_multiplier": surface_grip_multiplier,
		"longitudinal_speed_mps": longitudinal_speed,
		"lateral_speed_mps": lateral_speed,
		"slip_angle_rad": slip_angle,
		"longitudinal_slip_ratio": longitudinal_slip_ratio,
		"wheel_angular_speed_rad_s": wheel_angular_speed_rad_s,
		"slide_grip_ratio": slide_grip_ratio,
		"longitudinal_force_n": combined.x,
		"lateral_force_n": combined.y,
	}
	return last_sample
