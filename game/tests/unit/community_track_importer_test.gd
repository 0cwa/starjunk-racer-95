extends Node

const TEMP_ROOT := "user://starjunk-community-track-import-test"
const ENV_PATH := TEMP_ROOT + "/environment.glb"
const COLLISION_PATH := TEMP_ROOT + "/collision.glb"

var _failures := PackedStringArray()

func _ready() -> void:
	print("TRACK_IMPORT_TEST_PHASE:start")
	var make_dir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEMP_ROOT))
	_check(make_dir_error == OK or make_dir_error == ERR_ALREADY_EXISTS, "test package directory should exist")
	_check(_write_environment_glb(), "environment GLB should export")
	print("TRACK_IMPORT_TEST_PHASE:environment_written")
	_check(_write_collision_glb(), "collision GLB should export")
	print("TRACK_IMPORT_TEST_PHASE:collision_written")

	var manifest := {
		"format": "starjunk95/track/1",
		"name": "Community Prism Loop",
		"environment": "environment.glb",
		"collision": "collision.glb",
		"checkpoints": [
			{"id": "start", "position": [0.0, 1.0, 0.0], "size": [4.0, 2.0, 1.0]},
			{"id": "cp-1", "position": [0.0, 1.0, -20.0], "size": [4.0, 2.0, 1.0]},
		],
		"spawn_points": [
			{"position": [0.0, 0.5, 2.0], "rotation_degrees": [0.0, 180.0, 0.0]},
		],
	}
	var importer := CommunityTrackImporter.new()
	print("TRACK_IMPORT_TEST_PHASE:before_import")
	var result := importer.import_track(TEMP_ROOT, manifest)
	print("TRACK_IMPORT_TEST_PHASE:after_import")
	_check(bool(result.get("ok", false)), "embedded GLB track should import: %s" % str(result.get("error", "")))
	if bool(result.get("ok", false)):
		var visual: Node = result["visual"]
		var collision: Node = result["collision"]
		_check(_count_type(visual, "MeshInstance3D") >= 1, "track visual should retain meshes")
		_check(_count_type(visual, "Camera3D") == 0, "track visual should strip cameras")
		_check(_count_collision_shapes(collision) >= 1, "track collision should be game-owned collision shapes")
		_check(int(result["collision_mesh_count"]) >= 1, "collision mesh count should be reported")
		_check(int(result["collision_triangle_count"]) > 0, "collision triangle count should be reported")
		_check(result["checkpoints"].size() == 2, "validated checkpoints should be returned")
		var spawns: Array[Transform3D] = result["spawn_points"]
		_check(spawns.size() == 1, "spawn transforms should be returned")
		_check(is_equal_approx(spawns[0].origin.z, 2.0), "spawn position should be parsed")
		visual.free()
		collision.free()

	var duplicate_checkpoint := manifest.duplicate(true)
	duplicate_checkpoint["checkpoints"][1]["id"] = "start"
	_check(
		not bool(StarjunkPackageLoader.new().validate_manifest(duplicate_checkpoint).get("ok", true)),
		"duplicate checkpoint ids must fail"
	)

	var invalid_size := manifest.duplicate(true)
	invalid_size["checkpoints"][0]["size"] = [4.0, 0.0, 1.0]
	_check(
		not bool(StarjunkPackageLoader.new().validate_manifest(invalid_size).get("ok", true)),
		"non-positive checkpoint extent must fail"
	)

	_cleanup()
	_finish()

func _write_environment_glb() -> bool:
	var source := Node3D.new()
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	source.add_child(mesh)
	var camera := Camera3D.new()
	source.add_child(camera)
	return _write_glb(source, ENV_PATH)

func _write_collision_glb() -> bool:
	var source := Node3D.new()
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(12.0, 0.5, 24.0)
	mesh.mesh = box
	mesh.position = Vector3(0.0, -0.25, -8.0)
	source.add_child(mesh)
	return _write_glb(source, COLLISION_PATH)

func _write_glb(source: Node, path: String) -> bool:
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

func _count_collision_shapes(node: Node) -> int:
	var count := 1 if node is CollisionShape3D else 0
	for child in node.get_children():
		count += _count_collision_shapes(child)
	return count

func _cleanup() -> void:
	for path in [ENV_PATH, COLLISION_PATH]:
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
