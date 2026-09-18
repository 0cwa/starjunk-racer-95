extends Node

var _failures := PackedStringArray()

const LOAD_N := 3000.0
const MU := 1.1
const STIFFNESS := 22000.0
const PEAK_RATIO := 0.12

func _ready() -> void:
	_check(is_zero_approx(TireForceModel.longitudinal_force_n(0.0, LOAD_N, MU, STIFFNESS, PEAK_RATIO)), "zero longitudinal slip must produce zero force")

	var positive := TireForceModel.longitudinal_force_n(0.06, LOAD_N, MU, STIFFNESS, PEAK_RATIO)
	var negative := TireForceModel.longitudinal_force_n(-0.06, LOAD_N, MU, STIFFNESS, PEAK_RATIO)
	_check(positive > 0.0, "positive wheel overspeed should produce forward force")
	_check(negative < 0.0, "negative slip should produce braking force")
	_check(absf(absf(positive) - absf(negative)) < 0.001, "longitudinal tyre curve should be symmetric")

	var peak := TireForceModel.longitudinal_force_n(PEAK_RATIO, LOAD_N, MU, STIFFNESS, PEAK_RATIO)
	_check(absf(peak - LOAD_N * MU) < 0.01, "longitudinal peak should equal mu * normal load")

	var post_peak := TireForceModel.longitudinal_force_n(PEAK_RATIO * 3.0, LOAD_N, MU, STIFFNESS, PEAK_RATIO)
	_check(post_peak < peak, "wheelspin force should fall below peak")
	_check(post_peak > peak * 0.75, "wheelspin should retain controllable sliding traction")

	_check(is_zero_approx(TireForceModel.longitudinal_force_n(0.2, 0.0, MU, STIFFNESS, PEAK_RATIO)), "unloaded tyre should produce no longitudinal force")
	_finish()

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("Longitudinal tyre force tests passed")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("TEST FAILURE: " + failure)
	get_tree().quit(1)
