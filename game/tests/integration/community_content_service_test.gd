extends Node

const ROOT := "user://starjunk-community-content-service-test"
const FIXTURES := ROOT + "/fixtures"
const LIBRARY := ROOT + "/library"
const STAGING := ROOT + "/staging"
const CAR_ZIP := FIXTURES + "/car.zip"
const TRACK_ZIP := FIXTURES + "/track.zip"

var _failures := PackedStringArray()
var _race: PrototypeRace

func _ready() -> void:
	_cleanup()
	var make_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FIXTURES))
	_check(make_error == OK or make_error == ERR_ALREADY_EXISTS, "fixture directory should be created")
	_check(_write_car_zip(), "car ZIP fixture should be created")
	_check(_write_track_zip(), "track ZIP fixture should be created")

	var service := CommunityContentService.new(LIBRARY, STAGING)
	var car_install := service.install_zip(CAR_ZIP)
	_check(bool(car_install.get("ok", false)), "car ZIP should install: %s" % str(car_install.get("error", "")))
	var track_install := service.install_zip(TRACK_ZIP)
	_check(bool(track_install.get("ok", false)), "track ZIP should install: %s" % str(track_install.get("error", "")))
	if not bool(car_install.get("ok", false)) or not bool(track_install.get("ok", false)):
		_cleanup()
		_finish()
		return

	var car_id := str(car_install["content_id"])
	var track_id := str(track_install["content_id"])
	_check(car_id.begins_with("sha256:"), "car install should return immutable content id")
	_check(track_id.begins_with("sha256:"), "track install should return immutable content id")
	_check(car_id != track_id, "car and track should have different content identities")
	_check(_directory_empty(STAGING), "service should leave no transient staged package data")

	var duplicate := service.install_zip(CAR_ZIP)
	_check(bool(duplicate.get("ok", false)), "duplicate ZIP install should succeed")
	_check(not bool(duplicate.get("installed", true)), "duplicate content should deduplicate")
	_check(str(duplicate.get("content_id", "")) == car_id, "duplicate install should return same immutable id")

	var catalog := service.catalog()
	_check(bool(catalog.get("ok", false)), "community catalog should list installed content")
	_check(catalog["entries"].size() == 2, "catalog should contain installed car and track")
	_check(catalog["corrupt"].is_empty(), "fresh service catalog should have no corrupt content")
	var saw_car := false
	var saw_track := false
	for entry in catalog["entries"]:
		_check(not entry.has("root"), "selection catalog must not expose mutable package roots")
		if str(entry["content_id"]) == car_id:
			saw_car = str(entry["package_format"]) == StarjunkPackageLoader.CAR_FORMAT
		if str(entry["content_id"]) == track_id:
			saw_track = str(entry["package_format"]) == StarjunkPackageLoader.TRACK_FORMAT
	_check(saw_car and saw_track, "catalog should preserve package kinds by content id")

	var bundle := service.build_race_bundle(car_id, track_id)
	_check(bool(bundle.get("ok", false)), "installed ids should build a safe race bundle: %s" % str(bundle.get("error", "")))
	if bool(bundle.get("ok", false)):
		_check(str(bundle["car_content_id"]) == car_id, "bundle car id should match requested immutable id")
		_check(str(bundle["track_content_id"]) == track_id, "bundle track id should match requested immutable id")
		var packed: PackedScene = load("res://src/race/prototype_race.tscn")
		_race = packed.instantiate()
		_race.input_enabled = false
		add_child(_race)
		await get_tree().process_frame
		var mount_error := _race.mount_community_bundle(bundle)
		_check(mount_error.is_empty(), "service bundle should mount into playable race: %s" % mount_error)
		_check(bundle.is_empty(), "successful race mount should consume bundle runtime ownership")
		_check(_race.active_car_content_id == car_id, "playable race should retain service car id")
		_check(_race.active_track_content_id == track_id, "playable race should retain service track id")
		_check(_race.checkpoint_count() == 2, "service track checkpoints should become active race checkpoints")
		await _physics_frames(120)
		_check(_race.vehicle.grounded_wheel_count() >= 3, "trusted car should settle on service-imported track collision")

	var reversed := service.build_race_bundle(track_id, car_id)
	_check(not bool(reversed.get("ok", true)), "track id must not be accepted in car slot")

	var removed_car := service.uninstall(car_id)
	_check(bool(removed_car.get("ok", false)) and bool(removed_car.get("removed", false)), "installed car should uninstall by immutable id")
	_check(not bool(service.build_race_bundle(car_id, track_id).get("ok", true)), "uninstalled car must not remain resolvable")

	_cleanup()
	_finish()

func _write_car_zip() -> bool:
	var temp_root := FIXTURES + "/car-source"
	if not _make_dir(temp_root):
		return false
	var source := Node3D.new()
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.6, 0.5, 3.0)
	mesh.mesh = box
	source.add_child(mesh)
	if not _write_glb(source, temp_root + "/model.glb"):
		_remove_tree(ProjectSettings.globalize_path(temp_root))
		return false
	var manifest := {
		"format": "starjunk95/car/1",
		"name": "Service Test Car",
		"model": "model.glb",
		"performance_profile": "prototype_balanced_01",
	}
	if not _write_json(temp_root + "/manifest.json", manifest):
		_remove_tree(ProjectSettings.globalize_path(temp_root))
		return false
	var ok := _zip_directory(temp_root, CAR_ZIP, ["manifest.json", "model.glb"])
	_remove_tree(ProjectSettings.globalize_path(temp_root))
	return ok

func _write_track_zip() -> bool:
	var temp_root := FIXTURES + "/track-source"
	if not _make_dir(temp_root):
		return false

	var environment := Node3D.new()
	var environment_mesh := MeshInstance3D.new()
	var road := BoxMesh.new()
	road.size = Vector3(30.0, 0.2, 30.0)
	environment_mesh.mesh = road
	environment.add_child(environment_mesh)
	if not _write_glb(environment, temp_root + "/environment.glb"):
		_remove_tree(ProjectSettings.globalize_path(temp_root))
		return false

	var collision := Node3D.new()
	var collision_mesh := MeshInstance3D.new()
	var collision_box := BoxMesh.new()
	collision_box.size = Vector3(40.0, 1.0, 40.0)
	collision_mesh.mesh = collision_box
	collision_mesh.position = Vector3(0.0, -0.5, 0.0)
	collision.add_child(collision_mesh)
	if not _write_glb(collision, temp_root + "/collision.glb"):
		_remove_tree(ProjectSettings.globalize_path(temp_root))
		return false

	var manifest := {
		"format": "starjunk95/track/1",
		"name": "Service Test Track",
		"environment": "environment.glb",
		"collision": "collision.glb",
		"checkpoints": [
			{"id": "start", "position": [0.0, 1.0, 0.0], "size": [5.0, 2.0, 1.0]},
			{"id": "cp-1", "position": [0.0, 1.0, -10.0], "size": [5.0, 2.0, 1.0]},
		],
		"spawn_points": [
			{"position": [0.0, 0.78, 0.0], "rotation_degrees": [0.0, 0.0, 0.0]},
		],
	}
	if not _write_json(temp_root + "/manifest.json", manifest):
		_remove_tree(ProjectSettings.globalize_path(temp_root))
		return false
	var ok := _zip_directory(temp_root, TRACK_ZIP, ["manifest.json", "environment.glb", "collision.glb"])
	_remove_tree(ProjectSettings.globalize_path(temp_root))
	return ok

func _zip_directory(root: String, zip_path: String, relative_paths: Array[String]) -> bool:
	var packer := ZIPPacker.new()
	packer.compression_level = ZIPPacker.COMPRESSION_NONE
	if packer.open(zip_path) != OK:
		return false
	for relative_path in relative_paths:
		var file := FileAccess.open(root.path_join(relative_path), FileAccess.READ)
		if file == null:
			packer.close()
			return false
		var bytes := file.get_buffer(file.get_length())
		if packer.start_file(relative_path) != OK:
			packer.close()
			return false
		if packer.write_file(bytes) != OK:
			packer.close_file()
			packer.close()
			return false
		if packer.close_file() != OK:
			packer.close()
			return false
	return packer.close() == OK

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

func _make_dir(path: String) -> bool:
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
	return error == OK or error == ERR_ALREADY_EXISTS

func _physics_frames(count: int) -> void:
	for _index in range(count):
		await get_tree().physics_frame

func _directory_empty(path: String) -> bool:
	var directory := DirAccess.open(path)
	if directory == null:
		return true
	directory.list_dir_begin()
	while true:
		var name := directory.get_next()
		if name.is_empty():
			break
		if name != "." and name != "..":
			directory.list_dir_end()
			return false
	directory.list_dir_end()
	return true

func _cleanup() -> void:
	_remove_tree(ProjectSettings.globalize_path(ROOT))

func _remove_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	while true:
		var name := directory.get_next()
		if name.is_empty():
			break
		if name == "." or name == "..":
			continue
		var child := path.path_join(name)
		if directory.current_is_dir() and not directory.is_link(name):
			_remove_tree(child)
		else:
			DirAccess.remove_absolute(child)
	directory.list_dir_end()
	DirAccess.remove_absolute(path)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("Community content service end-to-end test passed")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("TEST FAILURE: " + failure)
	get_tree().quit(1)
