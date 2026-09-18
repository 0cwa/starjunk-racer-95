class_name WheelRotationModel
extends RefCounted

static func integrate_angular_speed(
		angular_speed_rad_s: float,
		drive_torque_nm: float,
		brake_torque_nm: float,
		tyre_reaction_torque_nm: float,
		angular_damping_n_m_s: float,
		inertia_kg_m2: float,
		delta_seconds: float,
		max_angular_speed_rad_s: float
) -> float:
	if inertia_kg_m2 <= 0.0 or delta_seconds <= 0.0:
		return angular_speed_rad_s

	var damping_torque := -angular_speed_rad_s * maxf(angular_damping_n_m_s, 0.0)
	var free_torque := drive_torque_nm + tyre_reaction_torque_nm + damping_torque
	var free_speed := angular_speed_rad_s + free_torque / inertia_kg_m2 * delta_seconds

	var brake_delta := maxf(brake_torque_nm, 0.0) / inertia_kg_m2 * delta_seconds
	var braked_speed := free_speed
	if brake_delta > 0.0:
		if absf(free_speed) <= brake_delta:
			braked_speed = 0.0
		else:
			braked_speed = free_speed - signf(free_speed) * brake_delta

	var speed_limit := maxf(max_angular_speed_rad_s, 0.0)
	if speed_limit <= 0.0:
		return 0.0
	return clampf(braked_speed, -speed_limit, speed_limit)
