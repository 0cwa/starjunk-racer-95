extends Node

const TEMP_ROOT := "user://starjunk-community-track-import-test"
const ENVIRONMENT_PATH := TEMP_ROOT + "/environment.glb"
const COLLISION_PATH := TEMP_ROOT + "/collision.glb"

var _failures := PackedStringArray()

func _ready() -> void:
	var make_dir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEMP_ROOT))
	_check(make_dir_error == OK or make_dir_error == ERR_ALREADY_EXISTS, "test track package directory should exist")
	_check(_write_environment_glb(), "test environment GLB should export")
	_check(_write_collision_glb(), "test collision GLB should export")

	var manifest := {
		"format": "starjunk95/track/1",
		"name": "Test Prism Loop",
		"environment": "environment.glb",
		"collision": "collision.glb",
		"checkpoints": [
			{
				"id": "start",
				"position": [0.0, 1.5, 0.0],
				"size": [8.0, 3.0, 1.0],
				"rotation_degrees": [0.0, 5.0, 0.0],
			},
			{
				"id": "mid",
				"position": [0.0, 1.5, -20.0],
				"size": [8.0, 3.0, 1.0],
			},
		],
		"spawn_points": [
			{
				"position": [1.0, 0.6, 2.0],
				"rotation_degrees": [0.0, 180.0, 0.0],
			},
		],
	}

	var importer := CommunityTrackImporter.new()
	var result := importer.import_track(TEMP_ROOT, manifest)
	_check(bool(result.get("ok", false)), "community track should import: %s" % str(result.get("error", "")))
	if bool(result.get("ok", false)):
		var root: Node3D = result["node"]
		_check(_count_type(root, "MeshInstance3D") >= 1, "track should retain visual meshes")
		_check(_count_type(root, "Camera3D") == 0, "track visuals should strip cameras")
		_check(int(result["collision_shape_count"]) >= 1, "collision GLB should become collision shapes")
		var collision_body: StaticBody3D = result["collision_body"]
		_check(collision_body.get_child_count() >= 1, "collision body should own generated shapes")
		if collision_body.get_child_count() > 0:
			var collision_shape := collision_body.get_child(0) as CollisionShape3D
			_check(collision_shape != null and collision_shape.shape is ConcavePolygonShape3D, "track collision should use trimesh shapes")
		var checkpoints: Array = result["checkpoints"]
		_check(checkpoints.size() == 2, "manifest should create two checkpoints")
		if checkpoints.size() == 2:
			_check(str(checkpoints[0].get_meta("checkpoint_id")) == "start", "checkpoint id should be preserved")
			_check(is_equal_approx(checkpoints[0].rotation_degrees.y, 5.0), "optional checkpoint rotation should apply")
		var spawns: Array = result["spawn_points"]
		_check(spawns.size() == 1, "manifest should create one spawn")
		if spawns.size() == 1:
			_check(spawns[0].position.is_equal_approx(Vector3(1.0, 0.6, 2.0)), "spawn position should be preserved")
		root.free()

	_cleanup()
	_finish()

func _write_environment_glb() -> bool:
	var source := Node3D.new()
	source.name = "TrackVisual"
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "RoadVisual"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(12.0, 0.2, 30.0)
	mesh_instance.mesh = mesh
	source.add_child(mesh_instance)
	var camera := Camera3D.new()
	camera.name = "UntrustedTrackCamera"
	source.add_child(camera)
	return _write_scene_glb(source, ENVIRONMENT_PATH)

func _write_collision_glb() -> bool:
	var source := Node3D.new()
	source.name = "TrackCollisionSource"
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "RoadCollisionMesh"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(12.0, 0.2, 30.0)
	mesh_instance.mesh = mesh
	mesh_instance.position = Vector3(0.0, -0.1, -10.0)
	source.add_child(mesh_instance)
	return _write_scene_glb(source, COLLISION_PATH)

func _write_scene_glb(source: Node3D, path: String) -> bool:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var append_error := document.append_from_scene(source, state)
	if append_error != OK:
		source.free()
		return false
	var write_error := document.write_to_filesystem(state, path)
	source.free()
	return write_error == OK and FileAccess.file_exists(path)

func _count_type(node: Node, type_name: String) -> int:
	var count := 1 if node.get_class() == type_name else 0
	for child in node.get_children():
		count += _count_type(child, type_name)
	return count

func _cleanup() -> void:
	for path in [ENVIRONMENT_PATH, COLLISION_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_ROOT))

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("Community track runtime importer tests passed")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("TEST FAILURE: " + failure)
	get_tree().quit(1)
