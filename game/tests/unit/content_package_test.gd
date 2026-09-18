extends Node

var _failures := PackedStringArray()

func _ready() -> void:
	var loader := StarjunkPackageLoader.new()

	var valid_car := {
		"format": "starjunk95/car/1",
		"name": "Chrome Mosquito",
		"model": "models/car.glb",
		"preview": "preview.webp",
		"performance_profile": "prototype_balanced_01",
	}
	_check(bool(loader.validate_manifest(valid_car).get("ok", false)), "valid car manifest should pass")
	_check(loader.resolve_car_performance_profile(valid_car) != null, "trusted car profile should resolve")

	var traversal_car := valid_car.duplicate(true)
	traversal_car["model"] = "../outside.glb"
	_check(not bool(loader.validate_manifest(traversal_car).get("ok", true)), "parent traversal must be rejected")

	var absolute_car := valid_car.duplicate(true)
	absolute_car["model"] = "/tmp/car.glb"
	_check(not bool(loader.validate_manifest(absolute_car).get("ok", true)), "absolute asset path must be rejected")

	var windows_car := valid_car.duplicate(true)
	windows_car["model"] = "C:\\cars\\car.glb"
	_check(not bool(loader.validate_manifest(windows_car).get("ok", true)), "Windows/drive path must be rejected")

	var unknown_profile := valid_car.duplicate(true)
	unknown_profile["performance_profile"] = "modded_supercar_999"
	_check(not bool(loader.validate_manifest(unknown_profile).get("ok", true)), "community car cannot invent a physics profile")

	var bad_extension := valid_car.duplicate(true)
	bad_extension["model"] = "models/car.tscn"
	_check(not bool(loader.validate_manifest(bad_extension).get("ok", true)), "Godot scene payloads must not be accepted as car models")

	var valid_track := {
		"format": "starjunk95/track/1",
		"name": "Prism Loop",
		"environment": "world/environment.glb",
		"collision": "world/collision.glb",
		"checkpoints": [
			{"id": "start", "position": [0.0, 1.0, 0.0], "size": [8.0, 3.0, 1.0]},
			{"id": "mid", "position": [0.0, 1.0, -20.0], "size": [8.0, 3.0, 1.0]},
		],
		"spawn_points": [
			{"position": [0.0, 0.5, 2.0], "rotation_degrees": [0.0, 180.0, 0.0]},
		],
	}
	_check(bool(loader.validate_manifest(valid_track).get("ok", false)), "valid track manifest should pass")

	var script_track := valid_track.duplicate(true)
	script_track["environment"] = "world/track.gd"
	_check(not bool(loader.validate_manifest(script_track).get("ok", true)), "script payload cannot masquerade as track geometry")

	var duplicate_checkpoints := valid_track.duplicate(true)
	duplicate_checkpoints["checkpoints"][1]["id"] = "start"
	_check(not bool(loader.validate_manifest(duplicate_checkpoints).get("ok", true)), "checkpoint ids must be unique")

	var invalid_checkpoint_size := valid_track.duplicate(true)
	invalid_checkpoint_size["checkpoints"][0]["size"] = [8.0, 0.0, 1.0]
	_check(not bool(loader.validate_manifest(invalid_checkpoint_size).get("ok", true)), "checkpoint size components must be positive")

	var invalid_spawn := valid_track.duplicate(true)
	invalid_spawn["spawn_points"][0].erase("rotation_degrees")
	_check(not bool(loader.validate_manifest(invalid_spawn).get("ok", true)), "spawn transform must include rotation")

	_finish()

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("Community package safety tests passed")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("TEST FAILURE: " + failure)
	get_tree().quit(1)
