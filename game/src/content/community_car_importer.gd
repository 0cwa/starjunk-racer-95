class_name CommunityCarImporter
extends RefCounted

const MAX_CAR_GLB_BYTES := 64 * 1024 * 1024

var _package_loader := StarjunkPackageLoader.new()

func import_visual(package_root: String, manifest: Dictionary) -> Dictionary:
	var validation := _package_loader.validate_manifest(manifest)
	if not bool(validation.get("ok", false)):
		return _error(str(validation.get("error", "invalid manifest")))
	if str(manifest.get("format", "")) != StarjunkPackageLoader.CAR_FORMAT:
		return _error("manifest is not a car package")

	var resolved := _package_loader.resolve_package_asset_path(package_root, manifest["model"])
	if not bool(resolved.get("ok", false)):
		return _error(str(resolved.get("error", "invalid model path")))

	var imported := CommunityGLTFLoader.load_embedded_scene(
		str(resolved["path"]),
		MAX_CAR_GLB_BYTES,
		"car"
	)
	if not bool(imported.get("ok", false)):
		return _error(str(imported.get("error", "car GLB import failed")))

	var scene: Node = imported["node"]
	CommunityGLTFLoader.sanitize_visual_tree(scene)
	if not CommunityGLTFLoader.contains_mesh(scene):
		scene.free()
		return _error("car GLB contains no renderable mesh")

	var profile := _package_loader.resolve_car_performance_profile(manifest)
	if profile == null:
		scene.free()
		return _error("trusted performance profile could not be resolved")

	return {
		"ok": true,
		"node": scene,
		"performance_profile": profile,
		"manifest": manifest.duplicate(true),
	}

func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
