class_name CommunityTrackImporter
extends RefCounted

const MAX_ENVIRONMENT_GLB_BYTES := 256 * 1024 * 1024
const MAX_COLLISION_GLB_BYTES := 64 * 1024 * 1024
const MAX_CUE_SET_BYTES := 2 * 1024 * 1024
const MAX_VISUAL_NODES := 5000
const MAX_VISUAL_LIGHTS := 64
const MAX_COLLISION_MESHES := 256
const MAX_COLLISION_TRIANGLES := 250000

var _package_loader := StarjunkPackageLoader.new()

func import_track(package_root: String, manifest: Dictionary) -> Dictionary:
	var validation := _package_loader.validate_manifest(manifest)
	if not bool(validation.get("ok", false)):
		return _error(str(validation.get("error", "invalid manifest")))
	if str(manifest.get("format", "")) != StarjunkPackageLoader.TRACK_FORMAT:
		return _error("manifest is not a track package")

	var song_cue_set: Dictionary = {}
	if manifest.has("song_cue_set"):
		var cue_result := _load_song_cue_set(package_root, manifest["song_cue_set"])
		if not bool(cue_result.get("ok", false)):
			return _error("song cue set: %s" % str(cue_result.get("error", "invalid cue set")))
		song_cue_set = cue_result["cue_set"]

	var environment_result := _load_embedded_glb(package_root, manifest["environment"], MAX_ENVIRONMENT_GLB_BYTES)
	if not bool(environment_result.get("ok", false)):
		return _error("environment: %s" % str(environment_result.get("error", "import failed")))
	var environment: Node = environment_result["node"]

	var visual_error := _validate_and_sanitize_visual(environment)
	if not visual_error.is_empty():
		environment.free()
		return _error("environment: %s" % visual_error)
	if not _contains_mesh(environment):
		environment.free()
		return _error("environment GLB contains no renderable mesh")

	var collision_result := _load_embedded_glb(package_root, manifest["collision"], MAX_COLLISION_GLB_BYTES)
	if not bool(collision_result.get("ok", false)):
		environment.free()
		return _error("collision: %s" % str(collision_result.get("error", "import failed")))
	var collision_scene: Node = collision_result["node"]
	var surface_profile_id := StringName(str(manifest.get("surface_profile", RoadSurfaceRegistry.DEFAULT_ID)))

	var built_collision := _build_collision(collision_scene, surface_profile_id)
	collision_scene.free()
	if not bool(built_collision.get("ok", false)):
		environment.free()
		return built_collision

	return {
		"ok": true,
		"visual": environment,
		"collision": built_collision["node"],
		"collision_mesh_count": built_collision["mesh_count"],
		"collision_triangle_count": built_collision["triangle_count"],
		"surface_profile": str(surface_profile_id),
		"song_cue_set": song_cue_set.duplicate(true),
		"checkpoints": _copy_checkpoints(manifest["checkpoints"]),
		"spawn_points": _make_spawn_transforms(manifest["spawn_points"]),
		"manifest": manifest.duplicate(true),
	}

func _load_song_cue_set(package_root: String, relative_path: Variant) -> Dictionary:
	var resolved := _package_loader.resolve_package_asset_path(package_root, relative_path)
	if not bool(resolved.get("ok", false)):
		return _error(str(resolved.get("error", "invalid cue-set path")))
	var path := str(resolved["path"])
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _error("unable to open cue set: %s" % path)
	var byte_count := file.get_length()
	if byte_count <= 0:
		return _error("cue set is empty")
	if byte_count > MAX_CUE_SET_BYTES:
		return _error("cue set exceeds %d bytes" % MAX_CUE_SET_BYTES)
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return _error("cue set root must be an object")
	var cue_set: Dictionary = parsed
	var cue_error := SongCueTimeline.validate(cue_set)
	if not cue_error.is_empty():
		return _error(cue_error)
	return {"ok": true, "cue_set": cue_set.duplicate(true)}

func _load_embedded_glb(package_root: String, relative_path: Variant, max_bytes: int) -> Dictionary:
	var resolved := _package_loader.resolve_package_asset_path(package_root, relative_path)
	if not bool(resolved.get("ok", false)):
		return _error(str(resolved.get("error", "invalid GLB path")))
	var path := str(resolved["path"])
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _error("unable to open GLB: %s" % path)
	var byte_count := file.get_length()
	if byte_count <= 0:
		return _error("GLB is empty")
	if byte_count > max_bytes:
		return _error("GLB exceeds %d bytes" % max_bytes)
	var bytes := file.get_buffer(byte_count)
	if bytes.size() != byte_count:
		return _error("unable to read complete GLB")
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
	return {"ok": true, "node": scene}

func _validate_and_sanitize_visual(root: Node) -> String:
	var stats := {"nodes": 0, "lights": 0}
	var inspect_error := _inspect_visual(root, stats)
	if not inspect_error.is_empty():
		return inspect_error
	_sanitize_visual_tree(root)
	return ""

func _inspect_visual(node: Node, stats: Dictionary) -> String:
	stats["nodes"] = int(stats["nodes"]) + 1
	if int(stats["nodes"]) > MAX_VISUAL_NODES:
		return "visual scene exceeds %d nodes" % MAX_VISUAL_NODES
	if node is Light3D:
		stats["lights"] = int(stats["lights"]) + 1
		if int(stats["lights"]) > MAX_VISUAL_LIGHTS:
			return "visual scene exceeds %d lights" % MAX_VISUAL_LIGHTS
	for child in node.get_children():
		var error := _inspect_visual(child, stats)
		if not error.is_empty():
			return error
	return ""

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
	if node is Camera3D:
		return true
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
		return true
	if node is AnimationPlayer:
		return true
	return not (node is Node3D)

func _build_collision(source_root: Node, surface_profile_id: StringName) -> Dictionary:
	var collision_root := Node3D.new()
	collision_root.name = "CommunityTrackCollision"
	var stats := {"meshes": 0, "triangles": 0}
	var error := _collect_collision_meshes(
		source_root,
		Transform3D.IDENTITY,
		collision_root,
		stats,
		surface_profile_id
	)
	if not error.is_empty():
		collision_root.free()
		return _error("collision: %s" % error)
	if int(stats["meshes"]) == 0:
		collision_root.free()
		return _error("collision: GLB contains no mesh")
	return {
		"ok": true,
		"node": collision_root,
		"mesh_count": stats["meshes"],
		"triangle_count": stats["triangles"],
	}

func _collect_collision_meshes(
		node: Node,
		parent_transform: Transform3D,
		output: Node3D,
		stats: Dictionary,
		surface_profile_id: StringName
) -> String:
	var current_transform := parent_transform
	if node is Node3D:
		current_transform = parent_transform * node.transform

	if node is MeshInstance3D and node.mesh != null:
		var mesh_instance := node as MeshInstance3D
		var mesh: Mesh = mesh_instance.mesh
		stats["meshes"] = int(stats["meshes"]) + 1
		if int(stats["meshes"]) > MAX_COLLISION_MESHES:
			return "mesh count exceeds %d" % MAX_COLLISION_MESHES
		var faces: PackedVector3Array = mesh.get_faces()
		if faces.size() % 3 != 0:
			return "mesh face list is not triangulated"
		stats["triangles"] = int(stats["triangles"]) + int(faces.size() / 3)
		if int(stats["triangles"]) > MAX_COLLISION_TRIANGLES:
			return "triangle count exceeds %d" % MAX_COLLISION_TRIANGLES
		var shape: ConcavePolygonShape3D = mesh.create_trimesh_shape()
		if shape == null:
			return "unable to create trimesh collision shape"
		var body := StaticBody3D.new()
		body.name = "TrackCollisionMesh%d" % int(stats["meshes"])
		body.set_meta(RoadSurfaceRegistry.METADATA_KEY, str(surface_profile_id))
		body.transform = current_transform
		var collision_shape := CollisionShape3D.new()
		collision_shape.shape = shape
		body.add_child(collision_shape)
		output.add_child(body)

	for child in node.get_children():
		var error := _collect_collision_meshes(
			child,
			current_transform,
			output,
			stats,
			surface_profile_id
		)
		if not error.is_empty():
			return error
	return ""

func _contains_mesh(node: Node) -> bool:
	if node is MeshInstance3D and node.mesh != null:
		return true
	for child in node.get_children():
		if _contains_mesh(child):
			return true
	return false

func _copy_checkpoints(values: Array) -> Array[Dictionary]:
	var checkpoints: Array[Dictionary] = []
	for value in values:
		checkpoints.append(value.duplicate(true))
	return checkpoints

func _make_spawn_transforms(values: Array) -> Array[Transform3D]:
	var transforms: Array[Transform3D] = []
	for value in values:
		var position := _array_to_vec3(value["position"])
		var rotation_degrees := _array_to_vec3(value["rotation_degrees"])
		var basis := Basis.from_euler(Vector3(
			deg_to_rad(rotation_degrees.x),
			deg_to_rad(rotation_degrees.y),
			deg_to_rad(rotation_degrees.z)
		))
		transforms.append(Transform3D(basis, position))
	return transforms

func _array_to_vec3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
