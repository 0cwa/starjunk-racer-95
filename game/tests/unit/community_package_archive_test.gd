extends Node

const TEMP_ROOT := "user://starjunk-package-archive-test"
const VALID_ZIP := TEMP_ROOT + "/valid.zip"
const TRAVERSAL_ZIP := TEMP_ROOT + "/traversal.zip"
const COLLISION_ZIP := TEMP_ROOT + "/case-collision.zip"
const VALID_STAGE := TEMP_ROOT + "/stage-valid"
const BAD_STAGE := TEMP_ROOT + "/stage-bad"
const ESCAPE_PATH := TEMP_ROOT + "/escape.txt"

var _failures := PackedStringArray()

func _ready() -> void:
	_cleanup()
	var root_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEMP_ROOT))
	_check(root_error == OK or root_error == ERR_ALREADY_EXISTS, "test root should exist")

	var manifest := {
		"format": "starjunk95/car/1",
		"name": "Archive Test Car",
		"model": "model.glb",
		"performance_profile": "prototype_balanced_01",
	}
	var valid_entries := {
		"manifest.json": JSON.stringify(manifest).to_utf8_buffer(),
		"model.glb": PackedByteArray([0x67, 0x6C, 0x54, 0x46]),
	}
	_check(_write_zip(VALID_ZIP, valid_entries), "valid ZIP fixture should be created")

	var archive := CommunityPackageArchive.new()
	var preflight := archive.preflight_zip(VALID_ZIP)
	_check(bool(preflight.get("ok", false)), "valid ZIP should pass preflight: %s" % str(preflight.get("error", "")))
	var staged := archive.stage_zip(VALID_ZIP, VALID_STAGE)
	_check(bool(staged.get("ok", false)), "valid ZIP should stage: %s" % str(staged.get("error", "")))
	if bool(staged.get("ok", false)):
		_check(str(staged["manifest"]["name"]) == "Archive Test Car", "staged manifest should be parsed")
		_check(FileAccess.file_exists(VALID_STAGE.path_join("model.glb")), "staged model should exist")

	var traversal_entries := {
		"manifest.json": JSON.stringify(manifest).to_utf8_buffer(),
		"../escape.txt": "escape".to_utf8_buffer(),
	}
	_check(_write_zip(TRAVERSAL_ZIP, traversal_entries), "traversal ZIP fixture should be created")
	var traversal := archive.stage_zip(TRAVERSAL_ZIP, BAD_STAGE)
	_check(not bool(traversal.get("ok", true)), "traversal ZIP must fail closed")
	_check(not FileAccess.file_exists(ESCAPE_PATH), "traversal ZIP must not write outside staging root")
	_check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(BAD_STAGE)), "failed staging directory should not remain")

	var collision_entries := {
		"manifest.json": JSON.stringify(manifest).to_utf8_buffer(),
		"Model.glb": PackedByteArray([1]),
		"model.glb": PackedByteArray([2]),
	}
	_check(_write_zip(COLLISION_ZIP, collision_entries), "case-collision ZIP fixture should be created")
	var collision_preflight := archive.preflight_zip(COLLISION_ZIP)
	_check(not bool(collision_preflight.get("ok", true)), "case-colliding archive paths must fail")

	_cleanup()
	_finish()

func _write_zip(path: String, entries: Dictionary) -> bool:
	var packer := ZIPPacker.new()
	packer.compression_level = ZIPPacker.COMPRESSION_NONE
	if packer.open(path) != OK:
		return false
	for name in entries.keys():
		if packer.start_file(str(name)) != OK:
			packer.close()
			return false
		if packer.write_file(entries[name]) != OK:
			packer.close_file()
			packer.close()
			return false
		if packer.close_file() != OK:
			packer.close()
			return false
	return packer.close() == OK

func _cleanup() -> void:
	_remove_tree(ProjectSettings.globalize_path(TEMP_ROOT))
	if FileAccess.file_exists(ESCAPE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ESCAPE_PATH))

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
		print("Community package archive tests passed")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("TEST FAILURE: " + failure)
	get_tree().quit(1)
