extends Node

const ROOT := "user://starjunk-community-race-bundle-test"
const CAR_ROOT := ROOT + "/car"
const TRACK_ROOT := ROOT + "/track"

var _failures := PackedStringArray()

func _ready() -> void:
	_cleanup()
	_check(_make_dirs(), "test package directories should be created")
	_check(_write_car_package(), "car package should be written")
	_check(_write_track_package(), "track package should be written")

	var assembler := CommunityRaceBundle.new()
	var bundle := assembler.import_bundle(CAR_ROOT, TRACK_ROOT)
	_check(bool(bundle.get("ok", false)), "community race bundle should import: %s" % str(bundle.get("error", "")))
	if bool(bundle.get("ok", false)):
		_check(str(bundle["car_content_id"]).begins_with("sha256:"), "car content id should be canonical SHA-256")
		_check(str(bundle["track_content_id"]).begins_with("sha256:"), "track content id should be canonical SHA-256")
		_check(str(bundle["car_content_id"]) != str(bundle["track_content_id"]), "different packages should have different content ids")
		var profile: VehiclePerformanceProfile = bundle["performance_profile"]
		_check(profile != null and profile.profile_id == &"prototype_balanced_01", "bundle should carry trusted performance profile")
		_check(bundle["car_visual"] is Node3D, "bundle should contain sanitized car visual")
		_check(bundle["track_visual"] is Node3D, "bundle should contain sanitized track visual")
		_check(bundle["track_collision"] is Node3D, "bundle should contain game-owned track collision")
		_check(bundle["checkpoints"].size() == 2, "bundle should carry validated checkpoints")
		_check(bundle["spawn_points"].size() == 1, "bundle should carry validated spawn transforms")
		_check(int(bundle["track_collision_triangle_count"]) > 0, "bundle should report collision complexity")
		CommunityRaceBundle.release(bundle)
		_check(bundle.is_empty(), "release should clear bundle dictionary")

	var wrong_kind := assembler.import_bundle(TRACK_ROOT, TRACK_ROOT)
	_check(not bool(wrong_kind.get("ok", true)), "track package must not be accepted as car package")

	_cleanup()
	_finish()

func _make_dirs() -> bool:
	for path in [CAR_ROOT, TRACK_ROOT]:
		var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
		if error != OK and error != ERR_ALREADY_EXISTS:
			return false
	return true

func _write_car_package() -> bool:
	var source := Node3D.new()
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	source.add_child(mesh)
	var ok := _write_glb(source, CAR_ROOT + "/model.glb")
	if not ok:
		return false
	return _write_json(CAR_ROOT + "/manifest.json", {
		"format": "starjunk95/car/1",
		"name": "Bundle Box",
		"model": "model.glb",
		"performance_profile": "prototype_balanced_01",
	})

func _write_track_package() -> bool:
	var environment := Node3D.new()
	var environment_mesh := MeshInstance3D.new()
	var environment_box := BoxMesh.new()
	environment_box.size = Vector3(12.0, 0.4, 24.0)
	environment_mesh.mesh = environment_box
	environment.add_child(environment_mesh)
	if not _write_glb(environment, TRACK_ROOT + "/environment.glb"):
		return false

	var collision := Node3D.new()
	var collision_mesh := MeshInstance3D.new()
	var collision_box := BoxMesh.new()
	collision_box.size = Vector3(12.0, 0.4, 24.0)
	collision_mesh.mesh = collision_box
	collision.add_child(collision_mesh)
	if not _write_glb(collision, TRACK_ROOT + "/collision.glb"):
		return false

	return _write_json(TRACK_ROOT + "/manifest.json", {
		"format": "starjunk95/track/1",
		"name": "Bundle Loop",
		"environment": "environment.glb",
		"collision": "collision.glb",
		"checkpoints": [
			{"id": "start", "position": [0.0, 1.0, 0.0], "size": [4.0, 2.0, 1.0]},
			{"id": "cp-1", "position": [0.0, 1.0, -10.0], "size": [4.0, 2.0, 1.0]},
		],
		"spawn_points": [
			{"position": [0.0, 0.8, 2.0], "rotation_degrees": [0.0, 180.0, 0.0]},
		],
	})

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

func _write_json(path: String, value: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value) + "\n")
	return true

func _cleanup() -> void:
	_remove_tree(ProjectSettings.globalize_path(ROOT))

func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty():
			break
		if name == "." or name == "..":
			continue
		var child := path.path_join(name)
		if dir.current_is_dir():
			_remove_tree(child)
		else:
			DirAccess.remove_absolute(child)
	dir.list_dir_end()
	DirAccess.remove_absolute(path)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("Community race bundle integration test passed")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("TEST FAILURE: " + failure)
	get_tree().quit(1)
