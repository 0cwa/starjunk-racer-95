extends Node

const ROOT := "user://starjunk-community-library-test"
const STAGED := ROOT + "/staged"
const LIBRARY := ROOT + "/library"

var _failures := PackedStringArray()

func _ready() -> void:
	_cleanup()
	_check(_write_staged_car(), "staged car package should be written")

	var library := CommunityContentLibrary.new(LIBRARY)
	var first := library.install_staged(STAGED)
	_check(bool(first.get("ok", false)), "first install should succeed: %s" % str(first.get("error", "")))
	if not bool(first.get("ok", false)):
		_cleanup()
		_finish()
		return

	var content_id := str(first["content_id"])
	_check(bool(first["installed"]), "first install should report new content")
	_check(content_id.begins_with("sha256:") and content_id.length() == 71, "installed content should have canonical SHA-256 id")
	var digest := content_id.substr(7)
	_check(str(first["root"]).ends_with("/" + digest), "installed root should be named by digest")

	var second := library.install_staged(STAGED)
	_check(bool(second.get("ok", false)), "repeat install should succeed")
	_check(not bool(second.get("installed", true)), "repeat install should deduplicate")
	_check(str(second.get("content_id", "")) == content_id, "deduplicated install should resolve same content")

	var resolved := library.resolve(content_id.to_upper())
	_check(bool(resolved.get("ok", false)), "content id lookup should be case-normalized")
	_check(str(resolved.get("content_id", "")) == content_id, "resolved id should be normalized")
	_check(str(resolved.get("package_format", "")) == StarjunkPackageLoader.CAR_FORMAT, "resolved package format should be preserved")

	var listing := library.list_installed()
	_check(bool(listing.get("ok", false)), "library listing should succeed")
	_check(listing["packages"].size() == 1, "library should contain one verified package")
	_check(listing["corrupt"].is_empty(), "fresh library should contain no corrupt entries")

	var model_path := str(resolved["root"]).path_join("model.glb")
	var tamper := FileAccess.open(model_path, FileAccess.WRITE)
	_check(tamper != null, "installed file should be available for integrity test")
	if tamper != null:
		tamper.store_buffer(PackedByteArray([9, 9, 9, 9, 9]))
	var tampered := library.resolve(content_id)
	_check(not bool(tampered.get("ok", true)), "tampered installed bytes must fail resolution")

	listing = library.list_installed()
	_check(listing["packages"].is_empty(), "tampered package must not appear as verified")
	_check(listing["corrupt"].size() == 1, "tampered package should be reported as corrupt")

	var invalid := library.resolve("sha256:../../outside")
	_check(not bool(invalid.get("ok", true)), "invalid content id must not resolve into a path")

	var removed := library.uninstall(content_id)
	_check(bool(removed.get("ok", false)) and bool(removed.get("removed", false)), "strict digest uninstall should remove corrupt content safely")
	_check(library.list_installed()["packages"].is_empty(), "library should be empty after uninstall")

	_cleanup()
	_finish()

func _write_staged_car() -> bool:
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(STAGED))
	if error != OK and error != ERR_ALREADY_EXISTS:
		return false
	var manifest := {
		"format": "starjunk95/car/1",
		"name": "Library Test Car",
		"model": "model.glb",
		"performance_profile": "prototype_balanced_01",
	}
	var manifest_file := FileAccess.open(STAGED + "/manifest.json", FileAccess.WRITE)
	if manifest_file == null:
		return false
	manifest_file.store_string(JSON.stringify(manifest) + "\n")
	var model_file := FileAccess.open(STAGED + "/model.glb", FileAccess.WRITE)
	if model_file == null:
		return false
	model_file.store_buffer(PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8]))
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
		print("Community content library tests passed")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("TEST FAILURE: " + failure)
	get_tree().quit(1)
