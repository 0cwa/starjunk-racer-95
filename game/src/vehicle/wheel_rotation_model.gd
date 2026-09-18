class_name WheelRotationModel
extends RefCounted

static func integrate_angular_speed(
		angular_speed_rad_s: float,
		rolling_angular_speed_rad_s: float,
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
	var externally_driven_speed := (
		angular_speed_rad_s
		+ (drive_torque_nm + damping_torque) / inertia_kg_m2 * delta_seconds
	)

	# Tyre reaction should move wheel speed toward the road's rolling speed. An
	# explicit 60 Hz step can otherwise overshoot that equilibrium and make an
	# undriven wheel alternate between large positive/negative slip every frame.
	var reaction_delta := tyre_reaction_torque_nm / inertia_kg_m2 * delta_seconds
	var reacted_speed := externally_driven_speed + reaction_delta
	if tyre_reaction_torque_nm > 0.0 and externally_driven_speed < rolling_angular_speed_rad_s:
		reacted_speed = minf(reacted_speed, rolling_angular_speed_rad_s)
	elif tyre_reaction_torque_nm < 0.0 and externally_driven_speed > rolling_angular_speed_rad_s:
		reacted_speed = maxf(reacted_speed, rolling_angular_speed_rad_s)

	# Brakes act after road reaction so sufficient brake torque can hold a locked
	# wheel against the tyre torque. Never let braking itself reverse the wheel.
	var brake_delta := maxf(brake_torque_nm, 0.0) / inertia_kg_m2 * delta_seconds
	var braked_speed := reacted_speed
	if brake_delta > 0.0:
		if absf(reacted_speed) <= brake_delta:
			braked_speed = 0.0
		else:
			braked_speed = reacted_speed - signf(reacted_speed) * brake_delta

	var speed_limit := maxf(max_angular_speed_rad_s, 0.0)
	if speed_limit <= 0.0:
		return 0.0
	return clampf(braked_speed, -speed_limit, speed_limit)
