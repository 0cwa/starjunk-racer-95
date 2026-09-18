class_name SuspensionModel
extends RefCounted

static func compression_m(
		rest_length_m: float,
		contact_distance_m: float,
		travel_m: float
) -> float:
	if rest_length_m <= 0.0 or travel_m <= 0.0:
		return 0.0
	return clampf(rest_length_m - contact_distance_m, 0.0, travel_m)

# Positive velocity means compression (bump); negative means extension (rebound).
static func compression_velocity_mps(
		previous_compression_m: float,
		current_compression_m: float,
		delta_seconds: float
) -> float:
	if delta_seconds <= 0.0:
		return 0.0
	return (current_compression_m - previous_compression_m) / delta_seconds

static func normal_force_n(
		compression_m_value: float,
		compression_velocity_mps_value: float,
		spring_rate_n_per_m: float,
		bump_damping_n_s_per_m: float,
		rebound_damping_n_s_per_m: float,
		max_force_n: float
) -> float:
	if spring_rate_n_per_m <= 0.0 or max_force_n <= 0.0 or compression_m_value < 0.0:
		return 0.0

	var spring_force := spring_rate_n_per_m * compression_m_value
	var damping_rate := (
		maxf(bump_damping_n_s_per_m, 0.0)
		if compression_velocity_mps_value >= 0.0
		else maxf(rebound_damping_n_s_per_m, 0.0)
	)
	var damping_force := damping_rate * compression_velocity_mps_value

	# A ray suspension may push the chassis away from the road, never pull it down.
	return clampf(spring_force + damping_force, 0.0, max_force_n)
