class_name HandlingAssistModel
extends RefCounted

const HIGH_SPEED_REFERENCE_MPS := 36.0
const MAX_HIGH_SPEED_STEER_REDUCTION := 0.45
const COUNTERSTEER_FULL_SLIP_DEG := 28.0
const COUNTERSTEER_AUTHORITY := 0.72
const YAW_STABILITY_FULL_SLIP_DEG := 18.0
const YAW_STABILITY_RATE := 0.82
const MAX_RECOVERY_SLIDE_GRIP_RATIO := 0.93

static func assisted_steer_input(
		driver_input: float,
		forward_speed_mps: float,
		lateral_speed_mps: float,
		steering_speed_assist: float,
		countersteer_assist: float
) -> float:
	var clamped_driver := clampf(driver_input, -1.0, 1.0)
	var speed_assist := clampf(steering_speed_assist, 0.0, 1.0)
	var counter_assist := clampf(countersteer_assist, 0.0, 1.0)

	var speed_blend := clampf(absf(forward_speed_mps) / HIGH_SPEED_REFERENCE_MPS, 0.0, 1.0)
	var steer_scale := 1.0 - MAX_HIGH_SPEED_STEER_REDUCTION * speed_assist * speed_blend
	var assisted := clamped_driver * steer_scale

	var slip_angle := _chassis_slip_angle_rad(forward_speed_mps, lateral_speed_mps)
	var normalized_slip := clampf(
		absf(slip_angle) / deg_to_rad(COUNTERSTEER_FULL_SLIP_DEG),
		0.0,
		1.0
	)
	if normalized_slip > 0.0 and counter_assist > 0.0:
		# Positive chassis lateral speed is +local X. In Godot, positive yaw
		# steering turns -Z toward -X, so countersteer has the opposite sign.
		assisted += -signf(slip_angle) * normalized_slip * counter_assist * COUNTERSTEER_AUTHORITY

	return clampf(assisted, -1.0, 1.0)

static func yaw_stability_torque_nm(
		yaw_rate_rad_s: float,
		forward_speed_mps: float,
		lateral_speed_mps: float,
		mass_kg: float,
		wheelbase_m: float,
		yaw_stability_assist: float
) -> float:
	var assist := clampf(yaw_stability_assist, 0.0, 1.0)
	if assist <= 0.0 or mass_kg <= 0.0 or wheelbase_m <= 0.0:
		return 0.0

	var slip_angle := _chassis_slip_angle_rad(forward_speed_mps, lateral_speed_mps)
	var slide_blend := clampf(
		absf(slip_angle) / deg_to_rad(YAW_STABILITY_FULL_SLIP_DEG),
		0.0,
		1.0
	)
	if slide_blend <= 0.0:
		return 0.0

	var yaw_inertia_scale := mass_kg * wheelbase_m * wheelbase_m
	return -yaw_rate_rad_s * yaw_inertia_scale * YAW_STABILITY_RATE * assist * slide_blend

static func slide_grip_ratio(base_slide_grip_ratio: float, grip_recovery_assist: float) -> float:
	var base_ratio := clampf(base_slide_grip_ratio, 0.0, 1.0)
	var assist := clampf(grip_recovery_assist, 0.0, 1.0)
	return lerpf(base_ratio, maxf(base_ratio, MAX_RECOVERY_SLIDE_GRIP_RATIO), assist)

static func _chassis_slip_angle_rad(forward_speed_mps: float, lateral_speed_mps: float) -> float:
	var reference_forward := maxf(absf(forward_speed_mps), WheelSlipKinematics.DEFAULT_LOW_SPEED_REFERENCE_MPS)
	return atan2(lateral_speed_mps, reference_forward)
