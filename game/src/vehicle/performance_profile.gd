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
	if base_grip_coefficient <= 0.0:
		problems.append("base_grip_coefficient must be positive")
	if base_cornering_stiffness <= 0.0:
		problems.append("base_cornering_stiffness must be positive")
	if base_peak_slip_angle_deg <= 0.0:
		problems.append("base_peak_slip_angle_deg must be positive")
	return problems
