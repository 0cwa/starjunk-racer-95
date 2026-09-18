class_name VehiclePerformanceProfile
extends Resource

@export_group("Identity")
@export var profile_id: StringName = &"prototype_balanced_01"
@export var display_name: String = "Prototype Balanced"

@export_group("Physical envelope")
@export_range(250.0, 2500.0, 1.0) var mass_kg: float = 900.0
@export_range(1.2, 5.0, 0.01) var wheelbase_m: float = 2.45
@export_range(0.8, 3.0, 0.01) var track_width_m: float = 1.55
@export_range(0.15, 0.8, 0.001) var wheel_radius_m: float = 0.31
@export_range(1000.0, 30000.0, 10.0) var max_drive_force_n: float = 9200.0
@export_range(1000.0, 40000.0, 10.0) var max_brake_force_n: float = 14500.0

@export_group("Wheel rotation and longitudinal tyre")
@export_range(0.05, 10.0, 0.001) var wheel_inertia_kg_m2: float = 1.15
@export_range(0.0, 10.0, 0.001) var wheel_angular_damping_n_m_s: float = 0.18
@export_range(1000.0, 80000.0, 10.0) var base_longitudinal_stiffness_n_per_slip: float = 22000.0
@export_range(0.02, 0.5, 0.001) var base_peak_longitudinal_slip_ratio: float = 0.12
@export_range(20.0, 1200.0, 1.0) var max_wheel_angular_speed_rad_s: float = 420.0

@export_group("Suspension")
@export_range(0.05, 1.0, 0.001) var suspension_rest_length_m: float = 0.34
@export_range(0.02, 0.5, 0.001) var suspension_travel_m: float = 0.18
@export_range(1000.0, 100000.0, 10.0) var suspension_spring_rate_n_per_m: float = 26000.0
@export_range(0.0, 20000.0, 10.0) var suspension_bump_damping_n_s_per_m: float = 3200.0
@export_range(0.0, 20000.0, 10.0) var suspension_rebound_damping_n_s_per_m: float = 4300.0
@export_range(1000.0, 100000.0, 10.0) var max_suspension_force_n: float = 16000.0

@export_group("Tyre personality")
@export_range(0.1, 3.0, 0.001) var base_grip_coefficient: float = 1.08
@export_range(1000.0, 80000.0, 10.0) var base_cornering_stiffness: float = 28000.0
@export_range(3.0, 25.0, 0.1) var base_peak_slip_angle_deg: float = 8.5
@export_range(0.1, 2.0, 0.001) var longitudinal_grip_bias: float = 1.0

func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if profile_id.is_empty():
		problems.append("profile_id must not be empty")
	if mass_kg <= 0.0:
		problems.append("mass_kg must be positive")
	if wheelbase_m <= 0.0:
		problems.append("wheelbase_m must be positive")
	if track_width_m <= 0.0:
		problems.append("track_width_m must be positive")
	if wheel_radius_m <= 0.0:
		problems.append("wheel_radius_m must be positive")
	if max_drive_force_n <= 0.0:
		problems.append("max_drive_force_n must be positive")
	if max_brake_force_n <= 0.0:
		problems.append("max_brake_force_n must be positive")
	if wheel_inertia_kg_m2 <= 0.0:
		problems.append("wheel_inertia_kg_m2 must be positive")
	if wheel_angular_damping_n_m_s < 0.0:
		problems.append("wheel_angular_damping_n_m_s must not be negative")
	if base_longitudinal_stiffness_n_per_slip <= 0.0:
		problems.append("base_longitudinal_stiffness_n_per_slip must be positive")
	if base_peak_longitudinal_slip_ratio <= 0.0:
		problems.append("base_peak_longitudinal_slip_ratio must be positive")
	if max_wheel_angular_speed_rad_s <= 0.0:
		problems.append("max_wheel_angular_speed_rad_s must be positive")
	if suspension_rest_length_m <= 0.0:
		problems.append("suspension_rest_length_m must be positive")
	if suspension_travel_m <= 0.0:
		problems.append("suspension_travel_m must be positive")
	if suspension_spring_rate_n_per_m <= 0.0:
		problems.append("suspension_spring_rate_n_per_m must be positive")
	if suspension_bump_damping_n_s_per_m < 0.0:
		problems.append("suspension_bump_damping_n_s_per_m must not be negative")
	if suspension_rebound_damping_n_s_per_m < 0.0:
		problems.append("suspension_rebound_damping_n_s_per_m must not be negative")
	if max_suspension_force_n <= 0.0:
		problems.append("max_suspension_force_n must be positive")
	if base_grip_coefficient <= 0.0:
		problems.append("base_grip_coefficient must be positive")
	if base_cornering_stiffness <= 0.0:
		problems.append("base_cornering_stiffness must be positive")
	if base_peak_slip_angle_deg <= 0.0:
		problems.append("base_peak_slip_angle_deg must be positive")
	return problems
