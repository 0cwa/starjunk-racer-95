class_name WheelSlipKinematics
extends RefCounted

const DEFAULT_LOW_SPEED_REFERENCE_MPS := 0.75

# Convention:
# - longitudinal_speed_mps > 0 means the vehicle/contact patch is moving
#   forward in the wheel's steered frame.
# - lateral_speed_mps > 0 means the contact patch velocity points to the right.
# - positive slip angle therefore asks TireForceModel for a leftward force.
#
# At low forward speed, the longitudinal denominator is floored so the angle
# approaches smoothly instead of snapping toward +/-90 degrees from tiny noise.
static func slip_angle_rad(
		longitudinal_speed_mps: float,
		lateral_speed_mps: float,
		low_speed_reference_mps: float = DEFAULT_LOW_SPEED_REFERENCE_MPS
) -> float:
	if is_zero_approx(longitudinal_speed_mps) and is_zero_approx(lateral_speed_mps):
		return 0.0
	var reference_speed := maxf(absf(longitudinal_speed_mps), maxf(low_speed_reference_mps, 0.001))
	return atan2(lateral_speed_mps, reference_speed)

# Positive ratio means driven-wheel overspeed (acceleration slip).
# Negative ratio means wheel underspeed (braking slip); a locked wheel at
# forward vehicle speed is -1.0. The symmetric denominator remains finite near
# rest and avoids dividing by whichever side happens to be almost zero.
static func longitudinal_slip_ratio(
		longitudinal_speed_mps: float,
		wheel_angular_speed_rad_s: float,
		wheel_radius_m: float,
		low_speed_reference_mps: float = DEFAULT_LOW_SPEED_REFERENCE_MPS
) -> float:
	if wheel_radius_m <= 0.0:
		return 0.0
	var wheel_surface_speed := wheel_angular_speed_rad_s * wheel_radius_m
	var denominator := maxf(
		maxf(absf(longitudinal_speed_mps), absf(wheel_surface_speed)),
		maxf(low_speed_reference_mps, 0.001)
	)
	return (wheel_surface_speed - longitudinal_speed_mps) / denominator

static func wheel_angular_speed_for_rolling(longitudinal_speed_mps: float, wheel_radius_m: float) -> float:
	if wheel_radius_m <= 0.0:
		return 0.0
	return longitudinal_speed_mps / wheel_radius_m
