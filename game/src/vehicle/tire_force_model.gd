class_name TireForceModel
extends RefCounted

const MIN_PEAK_SLIP_RAD := 0.001
const DEFAULT_SLIDE_GRIP_RATIO := 0.78
const POST_PEAK_FALLOFF := 1.35

# Returns lateral tyre force in newtons. Positive slip angle produces force in
# the opposite lateral direction. The pre-peak cubic is constrained to:
#   f(0)=0, f'(0)=cornering stiffness, f(peak)=mu*N, f'(peak)=0.
# Beyond the peak, force falls smoothly toward slide_grip_ratio * mu*N.
static func lateral_force_n(
		slip_angle_rad: float,
		normal_load_n: float,
		grip_coefficient: float,
		cornering_stiffness_n_per_rad: float,
		peak_slip_angle_deg: float,
		slide_grip_ratio: float = DEFAULT_SLIDE_GRIP_RATIO
) -> float:
	if is_zero_approx(slip_angle_rad):
		return 0.0
	if normal_load_n <= 0.0 or grip_coefficient <= 0.0 or cornering_stiffness_n_per_rad <= 0.0:
		return 0.0

	var peak_force_n := normal_load_n * grip_coefficient
	var peak_slip_rad := maxf(deg_to_rad(peak_slip_angle_deg), MIN_PEAK_SLIP_RAD)
	var normalized_angle := absf(slip_angle_rad) / peak_slip_rad
	var magnitude_shape: float

	if normalized_angle <= 1.0:
		# Normalized slope implied by the physical cornering stiffness.
		# Values above 3 can make the constrained cubic non-monotonic, so cap
		# only the curve construction while keeping the profile data explicit.
		var slope := clampf(
			cornering_stiffness_n_per_rad * peak_slip_rad / peak_force_n,
			0.0,
			3.0
		)
		var x := normalized_angle
		magnitude_shape = (
			(slope - 2.0) * x * x * x
			+ (3.0 - 2.0 * slope) * x * x
			+ slope * x
		)
		magnitude_shape = clampf(magnitude_shape, 0.0, 1.0)
	else:
		var slide_ratio := clampf(slide_grip_ratio, 0.0, 1.0)
		var excess := normalized_angle - 1.0
		magnitude_shape = slide_ratio + (1.0 - slide_ratio) * exp(-POST_PEAK_FALLOFF * excess)

	var opposing_sign := -1.0 if slip_angle_rad > 0.0 else 1.0
	return opposing_sign * peak_force_n * magnitude_shape


static func longitudinal_force_n(
		slip_ratio: float,
		normal_load_n: float,
		grip_coefficient: float,
		longitudinal_stiffness_n_per_slip: float,
		peak_slip_ratio: float,
		slide_grip_ratio: float = DEFAULT_SLIDE_GRIP_RATIO
) -> float:
	if is_zero_approx(slip_ratio):
		return 0.0
	if normal_load_n <= 0.0 or grip_coefficient <= 0.0 or longitudinal_stiffness_n_per_slip <= 0.0:
		return 0.0

	var peak_force_n := normal_load_n * grip_coefficient
	var peak_ratio := maxf(peak_slip_ratio, 0.001)
	var normalized_slip := absf(slip_ratio) / peak_ratio
	var magnitude_shape: float

	if normalized_slip <= 1.0:
		var slope := clampf(
			longitudinal_stiffness_n_per_slip * peak_ratio / peak_force_n,
			0.0,
			3.0
		)
		var x := normalized_slip
		magnitude_shape = (
			(slope - 2.0) * x * x * x
			+ (3.0 - 2.0 * slope) * x * x
			+ slope * x
		)
		magnitude_shape = clampf(magnitude_shape, 0.0, 1.0)
	else:
		var slide_ratio := clampf(slide_grip_ratio, 0.0, 1.0)
		var excess := normalized_slip - 1.0
		magnitude_shape = slide_ratio + (1.0 - slide_ratio) * exp(-POST_PEAK_FALLOFF * excess)

	return signf(slip_ratio) * peak_force_n * magnitude_shape

# Applies a normalized friction ellipse. The x component is longitudinal force
# and y is lateral force. longitudinal_grip_bias allows a trusted profile to
# express braking/drive-vs-cornering character without exceeding the combined
# tyre envelope.
static func clamp_combined_forces(
		longitudinal_force_n: float,
		lateral_force_n_value: float,
		normal_load_n: float,
		grip_coefficient: float,
		longitudinal_grip_bias: float = 1.0
) -> Vector2:
	if normal_load_n <= 0.0 or grip_coefficient <= 0.0 or longitudinal_grip_bias <= 0.0:
		return Vector2.ZERO

	var lateral_limit := normal_load_n * grip_coefficient
	var longitudinal_limit := lateral_limit * longitudinal_grip_bias
	var normalized_longitudinal := longitudinal_force_n / longitudinal_limit
	var normalized_lateral := lateral_force_n_value / lateral_limit
	var normalized_length := sqrt(
		normalized_longitudinal * normalized_longitudinal
		+ normalized_lateral * normalized_lateral
	)

	if normalized_length <= 1.0:
		return Vector2(longitudinal_force_n, lateral_force_n_value)

	var scale := 1.0 / normalized_length
	return Vector2(longitudinal_force_n * scale, lateral_force_n_value * scale)

static func combined_utilization(
		forces_n: Vector2,
		normal_load_n: float,
		grip_coefficient: float,
		longitudinal_grip_bias: float = 1.0
) -> float:
	if normal_load_n <= 0.0 or grip_coefficient <= 0.0 or longitudinal_grip_bias <= 0.0:
		return 0.0
	var lateral_limit := normal_load_n * grip_coefficient
	var longitudinal_limit := lateral_limit * longitudinal_grip_bias
	return Vector2(
		forces_n.x / longitudinal_limit,
		forces_n.y / lateral_limit
	).length()
