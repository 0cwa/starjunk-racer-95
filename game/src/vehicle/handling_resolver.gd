class_name HandlingResolver
extends RefCounted

# Realism is deliberately separate from the car's performance profile.
# Competitive races should resolve one shared realism value for every racer.

const ARCADE_COUNTERSTEER_ASSIST := 0.82
const ARCADE_YAW_STABILITY_ASSIST := 0.58
const ARCADE_DRIFT_ENTRY_ASSIST := 0.48
const ARCADE_GRIP_RECOVERY_ASSIST := 0.72
const ARCADE_STEERING_SPEED_ASSIST := 0.64

static func resolve(profile: VehiclePerformanceProfile, realism: float) -> Dictionary:
	var clamped_realism := clampf(realism, 0.0, 1.0)
	# Smoothstep avoids a harsh-feeling response near either end of the slider.
	var blend := clamped_realism * clamped_realism * (3.0 - 2.0 * clamped_realism)

	return {
		"realism": clamped_realism,
		"blend": blend,

		# Competitive/car identity: these do not change when the realism slider moves.
		"mass_kg": profile.mass_kg,
		"wheelbase_m": profile.wheelbase_m,
		"track_width_m": profile.track_width_m,
		"wheel_radius_m": profile.wheel_radius_m,
		"max_drive_force_n": profile.max_drive_force_n,
		"max_brake_force_n": profile.max_brake_force_n,
		"wheel_inertia_kg_m2": profile.wheel_inertia_kg_m2,
		"wheel_angular_damping_n_m_s": profile.wheel_angular_damping_n_m_s,
		"base_longitudinal_stiffness_n_per_slip": profile.base_longitudinal_stiffness_n_per_slip,
		"base_peak_longitudinal_slip_ratio": profile.base_peak_longitudinal_slip_ratio,
		"max_wheel_angular_speed_rad_s": profile.max_wheel_angular_speed_rad_s,
		"suspension_rest_length_m": profile.suspension_rest_length_m,
		"suspension_travel_m": profile.suspension_travel_m,
		"suspension_spring_rate_n_per_m": profile.suspension_spring_rate_n_per_m,
		"suspension_bump_damping_n_s_per_m": profile.suspension_bump_damping_n_s_per_m,
		"suspension_rebound_damping_n_s_per_m": profile.suspension_rebound_damping_n_s_per_m,
		"max_suspension_force_n": profile.max_suspension_force_n,
		"base_grip_coefficient": profile.base_grip_coefficient,
		"longitudinal_grip_bias": profile.longitudinal_grip_bias,

		# Feel/assist layer: progressively removed toward simulation.
		"countersteer_assist": lerpf(ARCADE_COUNTERSTEER_ASSIST, 0.0, blend),
		"yaw_stability_assist": lerpf(ARCADE_YAW_STABILITY_ASSIST, 0.0, blend),
		"drift_entry_assist": lerpf(ARCADE_DRIFT_ENTRY_ASSIST, 0.0, blend),
		"grip_recovery_assist": lerpf(ARCADE_GRIP_RECOVERY_ASSIST, 0.0, blend),
		"steering_speed_assist": lerpf(ARCADE_STEERING_SPEED_ASSIST, 0.0, blend),

		# Arcade mode widens the recoverable slip envelope and softens tyre response.
		# At realism=1 these resolve exactly to the profile's physical baseline.
		"cornering_stiffness": profile.base_cornering_stiffness * lerpf(0.72, 1.0, blend),
		"peak_slip_angle_deg": profile.base_peak_slip_angle_deg * lerpf(1.55, 1.0, blend),
	}
