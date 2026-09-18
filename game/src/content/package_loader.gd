class_name StarjunkPackageLoader
extends RefCounted

const CAR_FORMAT := "starjunk95/car/1"
const TRACK_FORMAT := "starjunk95/track/1"

func load_manifest(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "Unable to open manifest: %s" % path}
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Manifest root must be an object"}
	return validate_manifest(parsed)

func validate_manifest(manifest: Dictionary) -> Dictionary:
	var format_value: String = str(manifest.get("format", ""))
	match format_value:
		CAR_FORMAT:
			for key in ["name", "model", "performance_profile"]:
				if not manifest.has(key):
					return {"ok": false, "error": "Car manifest missing %s" % key}
		TRACK_FORMAT:
			for key in ["name", "environment", "collision", "checkpoints", "spawn_points"]:
				if not manifest.has(key):
					return {"ok": false, "error": "Track manifest missing %s" % key}
		_:
			return {"ok": false, "error": "Unsupported package format: %s" % format_value}
	return {"ok": true, "manifest": manifest}
