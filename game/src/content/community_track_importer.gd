class_name CommunityTrackImporter
extends RefCounted

const MAX_ENVIRONMENT_GLB_BYTES := 192 * 1024 * 1024
const MAX_COLLISION_GLB_BYTES := 128 * 1024 * 1024
const MAX_COLLISION_SHAPES := 512

var _package_loader := StarjunkPackageLoader.new()

func import_track(package_root: String, manifest: Dictionary) -> Dictionary:
	var validation := _package_loader.validate_manifest(manifest)
	if not bool(validation.get("ok", false)):
		return _error(str(validation.get("error", "invalid manifest")))
	if str(manifest.get("format", "")) != StarjunkPackageLoader.TRACK_FORMAT:
		return _error("manifest is not a track package")

	var environment_path := _package_loader.resolve_package_asset_path(package_root, manifest["environment"])
	if not bool(environment_path.get("ok", false)):
		return _error(str(environment_path.get("error", "invalid environment path")))
	var collision_path := _package_loader.resolve_package_asset_path(package_root, manifest["collision"])
	if not bool(collision_path.get("ok", false)):
		return _error(str(collision_path.get("error", "invalid collision path")))

	var environment_import := CommunityGLTFLoader.load_embedded_scene(
		str(environment_path["path"]),
		MAX_ENVIRONMENT_GLB_BYTES,
		"track environment"
	)
	if not bool(environment_import.get("ok", false)):
		return _error(str(environment_import.get("error", "environment import failed")))
	var visual: Node = environment_import["node"]
	CommunityGLTFLoader.sanitize_visual_tree(visual)
	if not CommunityGLTFLoader.contains_mesh(visual):
		visual.free()
		return _error("track environment GLB contains no renderable mesh")

	var collision_import := CommunityGLTFLoader.load_embedded_scene(
		str(collision_path["path"]),
		MAX_COLLISION_GLB_BYTES,
		"track collision"
	)
	if not bool(collision_import.get("ok", false)):
		visual.free()
		return _error(str(collision_import.get("error", "collision import failed")))
	var collision_source: Node = collision_import["node"]

	var collision_body := StaticBody3D.new()
	collision_body.name = "Collision"
	var collision_shape_count := _append_collision_shapes(
		collision_source,
		Transform3D.IDENTITY,
		collision_body
	)
	collision_source.free()
	if collision_shape_count <= 0:
		visual.free()
		collision_body.free()
		return _error("track collision GLB contains no triangle collision meshes")
	if collision_shape_count > MAX_COLLISION_SHAPES:
		visual.free()
		collision_body.free()
		return _error("track collision GLB exceeds %d collision shapes" % MAX_COLLISION_SHAPES)

	var root := Node3D.new()
	root.name = "CommunityTrack"
	visual.name = "Visuals"
	root.add_child(visual)
	root.add_child(collision_body)

	var checkpoints_root := Node3D.new()
	checkpoints_root.name = "Checkpoints"
	root.add_child(checkpoints_root)
	var checkpoints: Array[Area3D] = []
	for index in range(manifest["checkpoints"].size()):
		var checkpoint: Dictionary = manifest["checkpoints"][index]
		var area := Area3D.new()
		area.name = "Checkpoint_%02d" % index
		area.position = _vec3(checkpoint["position"])
		if checkpoint.has("rotation_degrees"):
			area.rotation_degrees = _vec3(checkpoint["rotation_degrees"])
		area.set_meta("checkpoint_id", str(checkpoint["id"]))
		area.set_meta("checkpoint_index", index)
		var shape_node := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = _vec3(checkpoint["size"])
		shape_node.shape = shape
		area.add_child(shape_node)
		checkpoints_root.add_child(area)
		checkpoints.append(area)

	var spawns_root := Node3D.new()
	spawns_root.name = "Spawns"
	root.add_child(spawns_root)
	var spawn_points: Array[Node3D] = []
	for index in range(manifest["spawn_points"].size()):
		var spawn: Dictionary = manifest["spawn_points"][index]
		var marker := Node3D.new()
		marker.name = "Spawn_%02d" % index
		marker.position = _vec3(spawn["position"])
		marker.rotation_degrees = _vec3(spawn["rotation_degrees"])
		marker.set_meta("spawn_index", index)
		spawns_root.add_child(marker)
		spawn_points.append(marker)

	return {
		"ok": true,
		"node": root,
		"visual": visual,
		"collision_body": collision_body,
		"collision_shape_count": collision_shape_count,
		"checkpoints": checkpoints,
		"spawn_points": spawn_points,
		"manifest": manifest.duplicate(true),
	}

func _append_collision_shapes(node: Node, parent_transform: Transform3D, body: StaticBody3D) -> int:
	var accumulated := parent_transform
	if node is Node3D:
		accumulated = parent_transform * node.transform

	var count := 0
	if node is MeshInstance3D and node.mesh != null:
		var shape := node.mesh.create_trimesh_shape()
		if shape != null:
			var collision := CollisionShape3D.new()
			collision.name = "MeshCollision_%03d" % body.get_child_count()
			collision.transform = accumulated
			collision.shape = shape
			body.add_child(collision)
			count += 1

	for child in node.get_children():
		count += _append_collision_shapes(child, accumulated, body)
	return count

func _vec3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
