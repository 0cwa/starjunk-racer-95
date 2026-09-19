extends Node

const ROOT := "user://starjunk-race-content-agreement-test"
const LIBRARY := ROOT + "/library"
const STAGING := ROOT + "/staging"
const CAR_ROOT := ROOT + "/car"
const TRACK_ROOT := ROOT + "/track"

var _failures := PackedStringArray()

func _ready() -> void:
	_cleanup()
	_check(_write_packages(), "content agreement fixtures should be written")
	var library := CommunityContentLibrary.new(LIBRARY)
	var car_install := library.install_staged(CAR_ROOT)
	var track_install := library.install_staged(TRACK_ROOT)
	_check(bool(car_install.get("ok", false)), "car fixture should install")
	_check(bool(track_install.get("ok", false)), "track fixture should install")
	if not bool(car_install.get("ok", false)) or not bool(track_install.get("ok", false)):
		_cleanup()
		_finish()
		return

	var car_id := str(car_install["content_id"])
	var track_id := str(track_install["content_id"])
	var room := RaceProtocol.make_room_config(
		0.35,
		3,
		8,
		"ocapn://example.invalid/s/track-cap",
		track_id
	)
	var car_reference := RaceProtocol.make_event(
		RaceProtocol.EVENT_CONTENT_REFERENCE,
		1,
		"racer-95",
		{
			"kind": "car",
			"reference": "ocapn://example.invalid/s/car-cap",
			"content_id": car_id,
		}
	)

	var service := CommunityContentService.new(LIBRARY, STAGING)
	var gate := RaceContentAgreement.new(service)
	var verified := gate.verify(room, car_reference)
	_check(bool(verified.get("ok", false)), "installed car/track identities should satisfy readiness gate: %s" % str(verified.get("error", "")))
	if bool(verified.get("ok", false)):
		_check(str(verified["car_content_id"]) == car_id, "agreement should preserve exact car identity")
		_check(str(verified["track_content_id"]) == track_id, "agreement should preserve exact track identity")
		_check(not verified["car"].has("root") and not verified["track"].has("root"), "network agreement must not expose mutable package roots")
		var ready := gate.make_ready_event(verified, 2, "racer-95")
		_check(not ready.is_empty(), "verified agreement should manufacture a ready event")
		_check(RaceProtocol.validate_event(ready).is_empty(), "manufactured ready event should satisfy race-control/3")
		_check(str(ready["data"]["car_content_id"]) == car_id, "ready event should bind exact car identity")
		_check(str(ready["data"]["track_content_id"]) == track_id, "ready event should bind exact track identity")

	var wrong_slot := car_reference.duplicate(true)
	wrong_slot["data"]["content_id"] = track_id
	_check(not bool(gate.verify(room, wrong_slot).get("ok", true)), "track bytes must not satisfy the car content slot")

	var wrong_room := room.duplicate(true)
	wrong_room["track_content_id"] = car_id
	_check(not bool(gate.verify(wrong_room, car_reference).get("ok", true)), "car bytes must not satisfy the room track slot")

	var uninstalled_track := service.uninstall(track_id)
	_check(bool(uninstalled_track.get("ok", false)), "track fixture should uninstall")
	_check(not bool(gate.verify(room, car_reference).get("ok", true)), "readiness must fail when exact room track bytes are unavailable locally")

	_cleanup()
	_finish()

func _write_packages() -> bool:
	for path in [CAR_ROOT, TRACK_ROOT]:
		var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
		if error != OK and error != ERR_ALREADY_EXISTS:
			return false

	var car_manifest := {
		"format": "starjunk95/car/1",
		"name": "Agreement Car",
		"model": "model.glb",
		"performance_profile": "prototype_balanced_01",
	}
	if not _write_json(CAR_ROOT + "/manifest.json", car_manifest):
		return false
	if not _write_bytes(CAR_ROOT + "/model.glb", PackedByteArray([1, 2, 3, 4])):
		return false

	var track_manifest := {
		"format": "starjunk95/track/1",
		"name": "Agreement Track",
		"environment": "environment.glb",
		"collision": "collision.glb",
		"checkpoints": [
			{"id": "start", "position": [0.0, 1.0, 0.0], "size": [4.0, 2.0, 1.0]},
			{"id": "cp-1", "position": [0.0, 1.0, -20.0], "size": [4.0, 2.0, 1.0]},
		],
		"spawn_points": [
			{"position": [0.0, 0.8, 0.0], "rotation_degrees": [0.0, 0.0, 0.0]},
		],
	}
	if not _write_json(TRACK_ROOT + "/manifest.json", track_manifest):
		return false
	if not _write_bytes(TRACK_ROOT + "/environment.glb", PackedByteArray([5, 6, 7, 8])):
		return false
	return _write_bytes(TRACK_ROOT + "/collision.glb", PackedByteArray([9, 10, 11, 12]))

func _write_json(path: String, value: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value) + "\n")
	return true

func _write_bytes(path: String, bytes: PackedByteArray) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
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
		print("Race content agreement integration test passed")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("TEST FAILURE: " + failure)
	get_tree().quit(1)
