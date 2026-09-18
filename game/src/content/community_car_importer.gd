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
	var model_path := str(resolved["path"])

	var file := FileAccess.open(model_path, FileAccess.READ)
	if file == null:
		return _error("unable to open car GLB: %s" % model_path)
	var byte_count := file.get_length()
	if byte_count <= 0:
		return _error("car GLB is empty")
	if byte_count > MAX_CAR_GLB_BYTES:
		return _error("car GLB exceeds %d bytes" % MAX_CAR_GLB_BYTES)
	var bytes := file.get_buffer(byte_count)
	if bytes.size() != byte_count:
		return _error("unable to read complete car GLB")

	var safety_error := GLBSafetyInspector.validate_embedded_only(bytes)
	if not safety_error.is_empty():
		return _error(safety_error)

	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var append_error := document.append_from_buffer(bytes, "", state)
	if append_error != OK:
		return _error("Godot GLB import failed with error %d" % append_error)

	var scene := document.generate_scene(state)
	if scene == null:
		return _error("Godot GLB import produced no scene")
	_sanitize_visual_tree(scene)
	if not _contains_mesh(scene):
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

func _sanitize_visual_tree(node: Node) -> void:
	for child in node.get_children():
		if _is_forbidden_visual_node(child):
			node.remove_child(child)
			child.free()
		else:
			_sanitize_visual_tree(child)

func _is_forbidden_visual_node(node: Node) -> bool:
	if node.get_script() != null:
		return true
	if node is CollisionObject3D or node is CollisionShape3D:
		return true
	if node is RayCast3D or node is ShapeCast3D:
		return true
	if node is Camera3D or node is Light3D:
		return true
	if node is AudioStreamPlayer3D:
		return true
	if node is AnimationPlayer:
		return true
	return not (node is Node3D)

func _contains_mesh(node: Node) -> bool:
	if node is MeshInstance3D and node.mesh != null:
		return true
	for child in node.get_children():
		if _contains_mesh(child):
			return true
	return false

func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
