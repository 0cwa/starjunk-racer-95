extends Node

var _failures := PackedStringArray()

func _ready() -> void:
	_check(RoadSurfaceRegistry.has_profile(&"asphalt"), "asphalt profile should exist")
	_check(RoadSurfaceRegistry.has_profile(&"wet"), "wet profile should exist")
	_check(RoadSurfaceRegistry.has_profile(&"gravel"), "gravel profile should exist")
	_check(not RoadSurfaceRegistry.has_profile(&"modded_ice"), "unknown community surface should not exist")

	var asphalt := RoadSurfaceRegistry.resolve(&"asphalt")
	var wet := RoadSurfaceRegistry.resolve(&"wet")
	var gravel := RoadSurfaceRegistry.resolve(&"gravel")
	_check(float(wet["grip_multiplier"]) < float(asphalt["grip_multiplier"]), "wet should reduce peak grip")
	_check(float(gravel["grip_multiplier"]) < float(wet["grip_multiplier"]), "gravel should reduce peak grip further")
	_check(float(gravel["peak_slip_angle_multiplier"]) > float(asphalt["peak_slip_angle_multiplier"]), "gravel should widen lateral slip envelope")
	_check(float(gravel["peak_longitudinal_slip_multiplier"]) > float(asphalt["peak_longitudinal_slip_multiplier"]), "gravel should widen longitudinal slip envelope")

	var fallback := RoadSurfaceRegistry.resolve(&"invented")
	_check(is_equal_approx(float(fallback["grip_multiplier"]), float(asphalt["grip_multiplier"])), "unknown resolution should fail safe to asphalt")

	var body := StaticBody3D.new()
	body.set_meta(RoadSurfaceRegistry.METADATA_KEY, "wet")
	_check(RoadSurfaceRegistry.profile_id_for_collider(body) == &"wet", "collider metadata should select trusted wet profile")
	body.set_meta(RoadSurfaceRegistry.METADATA_KEY, "invented")
	_check(RoadSurfaceRegistry.profile_id_for_collider(body) == RoadSurfaceRegistry.DEFAULT_ID, "unknown collider metadata should fall back to asphalt")
	body.free()
	_finish()

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("Road surface registry tests passed")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("TEST FAILURE: " + failure)
	get_tree().quit(1)
