class_name CommunityGLTFLoader
extends RefCounted

static func load_embedded_scene(path: String, max_bytes: int, label: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _error("unable to open %s GLB: %s" % [label, path])
	var byte_count := file.get_length()
	if byte_count <= 0:
		return _error("%s GLB is empty" % label)
	if byte_count > max_bytes:
		return _error("%s GLB exceeds %d bytes" % [label, max_bytes])
	var bytes := file.get_buffer(byte_count)
	if bytes.size() != byte_count:
		return _error("unable to read complete %s GLB" % label)

	var safety_error := GLBSafetyInspector.validate_embedded_only(bytes)
	if not safety_error.is_empty():
		return _error("%s GLB: %s" % [label, safety_error])

	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var append_error := document.append_from_buffer(bytes, "", state)
	if append_error != OK:
		return _error("Godot %s GLB import failed with error %d" % [label, append_error])

	var scene := document.generate_scene(state)
	if scene == null:
		return _error("Godot %s GLB import produced no scene" % label)
	return {"ok": true, "node": scene}

static func sanitize_visual_tree(node: Node) -> void:
	for child in node.get_children():
		if _is_forbidden_visual_node(child):
			node.remove_child(child)
			child.free()
		else:
			sanitize_visual_tree(child)

static func contains_mesh(node: Node) -> bool:
	if node is MeshInstance3D and node.mesh != null:
		return true
	for child in node.get_children():
		if contains_mesh(child):
			return true
	return false

static func _is_forbidden_visual_node(node: Node) -> bool:
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

static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
