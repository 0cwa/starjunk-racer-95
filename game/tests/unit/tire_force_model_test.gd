extends Node

var _failures := PackedStringArray()

const LOAD_N := 3000.0
const MU := 1.1
const STIFFNESS := 20000.0
const PEAK_DEG := 8.0

func _ready() -> void:
	_check(is_zero_approx(TireForceModel.lateral_force_n(0.0, LOAD_N, MU, STIFFNESS, PEAK_DEG)), "zero slip must produce zero lateral force")

	var small_angle := deg_to_rad(0.25)
	var small_force := TireForceModel.lateral_force_n(small_angle, LOAD_N, MU, STIFFNESS, PEAK_DEG)
	var expected_linear := -STIFFNESS * small_angle
	_check(is_equal_approx(small_force, expected_linear) or absf((small_force - expected_linear) / expected_linear) < 0.04, "small-slip force should follow cornering stiffness")

	var positive := TireForceModel.lateral_force_n(deg_to_rad(4.0), LOAD_N, MU, STIFFNESS, PEAK_DEG)
	var negative := TireForceModel.lateral_force_n(deg_to_rad(-4.0), LOAD_N, MU, STIFFNESS, PEAK_DEG)
	_check(positive < 0.0, "positive slip must generate opposing lateral force")
	_check(negative > 0.0, "negative slip must generate opposing lateral force")
	_check(absf(absf(positive) - absf(negative)) < 0.001, "tyre curve should be symmetric")

	var peak := absf(TireForceModel.lateral_force_n(deg_to_rad(PEAK_DEG), LOAD_N, MU, STIFFNESS, PEAK_DEG))
	_check(absf(peak - LOAD_N * MU) < 0.01, "force at peak slip should equal mu * normal load")

	var post_peak := absf(TireForceModel.lateral_force_n(deg_to_rad(PEAK_DEG * 3.0), LOAD_N, MU, STIFFNESS, PEAK_DEG))
	_check(post_peak < peak, "post-peak force should fall below peak force")
	_check(post_peak > peak * 0.75, "post-peak force should retain controllable sliding grip")

	var untouched := TireForceModel.clamp_combined_forces(500.0, -800.0, LOAD_N, MU)
	_check(untouched.is_equal_approx(Vector2(500.0, -800.0)), "forces inside traction envelope should be unchanged")

	var clamped := TireForceModel.clamp_combined_forces(3000.0, -3000.0, LOAD_N, MU)
	var utilization := TireForceModel.combined_utilization(clamped, LOAD_N, MU)
	_check(utilization <= 1.00001, "combined force must stay inside friction ellipse")
	_check(utilization > 0.999, "over-limit request should land on friction ellipse")

	var biased := TireForceModel.clamp_combined_forces(3600.0, -1800.0, LOAD_N, MU, 1.2)
	_check(TireForceModel.combined_utilization(biased, LOAD_N, MU, 1.2) <= 1.00001, "biased longitudinal grip must still respect normalized envelope")

	_check(TireForceModel.clamp_combined_forces(100.0, 100.0, 0.0, MU) == Vector2.ZERO, "unloaded tyre must produce no combined force")
	_check(is_zero_approx(TireForceModel.lateral_force_n(0.1, 0.0, MU, STIFFNESS, PEAK_DEG)), "unloaded tyre must produce no lateral force")

	_finish()

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("Tire force model tests passed")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("TEST FAILURE: " + failure)
	get_tree().quit(1)
