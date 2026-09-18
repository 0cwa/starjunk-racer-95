extends Node

const ROOT := "user://starjunk-package-identity-test"
const PACKAGE_A := ROOT + "/a"
const PACKAGE_B := ROOT + "/b"

var _failures := PackedStringArray()

func _ready() -> void:
	_cleanup()
	_check(_make_package(PACKAGE_A, false), "package A should be created")
	_check(_make_package(PACKAGE_B, true), "package B should be created")

	var identity := CommunityPackageIdentity.new()
	var a := identity.build_descriptor(PACKAGE_A)
	var b := identity.build_descriptor(PACKAGE_B)
	_check(bool(a.get("ok", false)), "package A identity should build: %s" % str(a.get("error", "")))
	_check(bool(b.get("ok", false)), "package B identity should build: %s" % str(b.get("error", "")))

	if bool(a.get("ok", false)) and bool(b.get("ok", false)):
		_check(str(a["content_id"]) == str(b["content_id"]), "directory creation order must not affect content ID")
		_check(str(a["content_id"]).begins_with("sha256:"), "content ID should identify SHA-256")
		_check(int(a["file_count"]) == 3, "descriptor should cover every package file")
		var files: Array = a["files"]
		_check(str(files[0]["path"]) < str(files[1]["path"]), "descriptor paths should be sorted")

	var changed := FileAccess.open(PACKAGE_B.path_join("model.glb"), FileAccess.WRITE)
	_check(changed != null, "changed model should open")
	if changed != null:
		changed.store_buffer(PackedByteArray([0x67, 0x6C, 0x54, 0x46, 0x95]))
	var b_changed := identity.build_descriptor(PACKAGE_B)
	_check(bool(b_changed.get("ok", false)), "changed package identity should build")
	if bool(a.get("ok", false)) and bool(b_changed.get("ok", false)):
		_check(str(a["content_id"]) != str(b_changed["content_id"]), "changing package bytes must change content ID")

	_cleanup()
	_finish()

func _make_package(root: String, reverse_order: bool) -> bool:
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root.path_join("extras"))) != OK:
		return false
	var manifest := {
		"format": "starjunk95/car/1",
		"name": "Identity Test Car",
		"model": "model.glb",
		"performance_profile": "prototype_balanced_01",
	}
	var entries := [
		["manifest.json", JSON.stringify(manifest).to_utf8_buffer()],
		["model.glb", PackedByteArray([0x67, 0x6C, 0x54, 0x46])],
		["extras/readme.txt", "same bytes".to_utf8_buffer()],
	]
	if reverse_order:
		entries.reverse()
	for entry in entries:
		var file := FileAccess.open(root.path_join(str(entry[0])), FileAccess.WRITE)
		if file == null:
			return false
		file.store_buffer(entry[1])
	return true

func _cleanup() -> void:
	_remove_tree(ProjectSettings.globalize_path(ROOT))

func _remove_tree(absolute_path: String) -> void:
	if not DirAccess.dir_exists_absolute(absolute_path):
		return
	var directory := DirAccess.open(absolute_path)
	if directory == null:
		return
	directory.list_dir_begin()
	while true:
		var name := directory.get_next()
		if name.is_empty():
			break
		if name == "." or name == "..":
			continue
		var child := absolute_path.path_join(name)
		if directory.current_is_dir():
			_remove_tree(child)
		else:
			DirAccess.remove_absolute(child)
	directory.list_dir_end()
	DirAccess.remove_absolute(absolute_path)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("Community package identity tests passed")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("TEST FAILURE: " + failure)
	get_tree().quit(1)
