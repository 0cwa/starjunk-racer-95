class_name StarjunkPackageLoader
extends RefCounted

const CAR_FORMAT := "starjunk95/car/1"
const TRACK_FORMAT := "starjunk95/track/1"

func load_manifest(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _error("Unable to open manifest: %s" % path)
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return _error("Manifest root must be an object")
	return validate_manifest(parsed)

func validate_manifest(manifest: Dictionary) -> Dictionary:
	var format_value := str(manifest.get("format", ""))
	match format_value:
		CAR_FORMAT:
			return _validate_car(manifest)
		TRACK_FORMAT:
			return _validate_track(manifest)
		_:
			return _error("Unsupported package format: %s" % format_value)

func resolve_car_performance_profile(manifest: Dictionary) -> VehiclePerformanceProfile:
	var validation := validate_manifest(manifest)
	if not bool(validation.get("ok", false)) or str(manifest.get("format", "")) != CAR_FORMAT:
		return null
	return PerformanceProfileRegistry.load_profile(StringName(str(manifest["performance_profile"])))

func resolve_package_asset_path(package_root: String, relative_path: Variant) -> Dictionary:
	var path_error := _validate_relative_asset_path("asset", relative_path)
	if not path_error.is_empty():
		return _error(path_error)
	if package_root.is_empty():
		return _error("package root must not be empty")

	var root := package_root.simplify_path().trim_suffix("/")
	var candidate := root.path_join(str(relative_path)).simplify_path()
	var required_prefix := root + "/"
	if not candidate.begins_with(required_prefix):
		return _error("asset path escaped package root")
	return {"ok": true, "path": candidate}

func _validate_car(manifest: Dictionary) -> Dictionary:
	for key in ["name", "model", "performance_profile"]:
		if not manifest.has(key):
			return _error("Car manifest missing %s" % key)

	var model_error := _validate_package_asset_path("model", manifest["model"], [".glb"])
	if not model_error.is_empty():
		return _error(model_error)

	if manifest.has("preview"):
		var preview_error := _validate_package_asset_path("preview", manifest["preview"], [".png", ".jpg", ".jpeg", ".webp"])
		if not preview_error.is_empty():
			return _error(preview_error)

	var profile_id := StringName(str(manifest["performance_profile"]))
	if not PerformanceProfileRegistry.has_profile(profile_id):
		return _error("Unknown performance_profile: %s" % profile_id)

	return {"ok": true, "kind": "car", "manifest": manifest.duplicate(true)}

func _validate_track(manifest: Dictionary) -> Dictionary:
	for key in ["name", "environment", "collision", "checkpoints", "spawn_points"]:
		if not manifest.has(key):
			return _error("Track manifest missing %s" % key)

	for key in ["environment", "collision"]:
		var asset_error := _validate_package_asset_path(key, manifest[key], [".glb"])
		if not asset_error.is_empty():
			return _error(asset_error)

	if manifest.has("preview"):
		var preview_error := _validate_package_asset_path("preview", manifest["preview"], [".png", ".jpg", ".jpeg", ".webp"])
		if not preview_error.is_empty():
			return _error(preview_error)

	if not manifest["checkpoints"] is Array or manifest["checkpoints"].size() < 2:
		return _error("Track requires at least two checkpoints")
	if not manifest["spawn_points"] is Array or manifest["spawn_points"].is_empty():
		return _error("Track requires at least one spawn point")

	return {"ok": true, "kind": "track", "manifest": manifest.duplicate(true)}

func _validate_package_asset_path(label: String, value: Variant, allowed_extensions: Array[String]) -> String:
	var path_error := _validate_relative_asset_path(label, value)
	if not path_error.is_empty():
		return path_error
	var lower_path := str(value).to_lower()
	for extension in allowed_extensions:
		if lower_path.ends_with(extension):
			return ""
	return "%s has an unsupported file extension" % label

func _validate_relative_asset_path(label: String, value: Variant) -> String:
	if not value is String:
		return "%s must be a string path" % label

	var path := str(value)
	if path.is_empty():
		return "%s must not be empty" % label
	if path.contains("\\"):
		return "%s must use forward slashes" % label
	if path.begins_with("/") or path.begins_with("~") or path.contains(":"):
		return "%s must be relative to the package root" % label

	var components := path.split("/", true)
	for component in components:
		if component == "." or component == ".." or component.is_empty():
			return "%s contains an unsafe path component" % label
	return ""

func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
