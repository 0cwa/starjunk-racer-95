class_name CommunityContentService
extends RefCounted

const DEFAULT_STAGING_ROOT := "user://starjunk95/staging"

var _staging_root: String
var _archive := CommunityPackageArchive.new()
var _library: CommunityContentLibrary
var _bundle_builder := CommunityRaceBundle.new()

func _init(
		library_root: String = CommunityContentLibrary.DEFAULT_ROOT,
		staging_root: String = DEFAULT_STAGING_ROOT
) -> void:
	_library = CommunityContentLibrary.new(library_root)
	_staging_root = staging_root.trim_suffix("/")

func install_zip(zip_path: String) -> Dictionary:
	var staging_error := _validate_staging_root()
	if not staging_error.is_empty():
		return _error(staging_error)
	if zip_path.is_empty():
		return _error("ZIP path must not be empty")

	var stage_root := _staging_root.path_join("package-%d" % Time.get_ticks_usec())
	var stage_absolute := ProjectSettings.globalize_path(stage_root)
	if DirAccess.dir_exists_absolute(stage_absolute):
		_remove_tree(stage_absolute)

	var staged := _archive.stage_zip(zip_path, stage_root)
	if not bool(staged.get("ok", false)):
		_remove_tree(stage_absolute)
		return _error("archive staging failed: %s" % str(staged.get("error", "unknown error")))

	var installed := _library.install_staged(stage_root)
	_remove_tree(stage_absolute)
	if not bool(installed.get("ok", false)):
		return _error("library install failed: %s" % str(installed.get("error", "unknown error")))

	return {
		"ok": true,
		"installed": bool(installed.get("installed", false)),
		"content_id": str(installed["content_id"]),
		"package_format": str(installed["package_format"]),
		"manifest": installed["manifest"].duplicate(true),
	}

func catalog() -> Dictionary:
	var listing := _library.list_installed()
	if not bool(listing.get("ok", false)):
		return _error(str(listing.get("error", "unable to list community library")))

	var entries: Array[Dictionary] = []
	for package in listing["packages"]:
		var manifest: Dictionary = package["manifest"]
		entries.append({
			"content_id": str(package["content_id"]),
			"package_format": str(package["package_format"]),
			"name": str(manifest.get("name", "")),
			"manifest": manifest.duplicate(true),
		})
	entries.sort_custom(_catalog_before)

	var corrupt: Array[Dictionary] = []
	for value in listing["corrupt"]:
		corrupt.append(value.duplicate(true))
	return {
		"ok": true,
		"entries": entries,
		"corrupt": corrupt,
	}

func verify_content(content_id: String, expected_format: String = "") -> Dictionary:
	var resolved := _library.resolve(content_id)
	if not bool(resolved.get("ok", false)):
		return _error(str(resolved.get("error", "unable to resolve content")))
	var package_format := str(resolved.get("package_format", ""))
	if not expected_format.is_empty() and package_format != expected_format:
		return _error("content id does not identify expected package format")
	var manifest: Dictionary = resolved["manifest"]
	return {
		"ok": true,
		"content_id": str(resolved["content_id"]),
		"package_format": package_format,
		"name": str(manifest.get("name", "")),
		"manifest": manifest.duplicate(true),
	}

func build_race_bundle(car_content_id: String, track_content_id: String) -> Dictionary:
	var car := _library.resolve(car_content_id)
	if not bool(car.get("ok", false)):
		return _error("car content: %s" % str(car.get("error", "unable to resolve")))
	if str(car.get("package_format", "")) != StarjunkPackageLoader.CAR_FORMAT:
		return _error("requested car content id does not identify a car package")

	var track := _library.resolve(track_content_id)
	if not bool(track.get("ok", false)):
		return _error("track content: %s" % str(track.get("error", "unable to resolve")))
	if str(track.get("package_format", "")) != StarjunkPackageLoader.TRACK_FORMAT:
		return _error("requested track content id does not identify a track package")

	var expected_car_id := str(car["content_id"])
	var expected_track_id := str(track["content_id"])
	var bundle := _bundle_builder.import_bundle(str(car["root"]), str(track["root"]))
	if not bool(bundle.get("ok", false)):
		return bundle

	if str(bundle.get("car_content_id", "")).to_lower() != expected_car_id:
		CommunityRaceBundle.release(bundle)
		return _error("car content changed while constructing race bundle")
	if str(bundle.get("track_content_id", "")).to_lower() != expected_track_id:
		CommunityRaceBundle.release(bundle)
		return _error("track content changed while constructing race bundle")
	return bundle

func uninstall(content_id: String) -> Dictionary:
	return _library.uninstall(content_id)

func _validate_staging_root() -> String:
	if not _staging_root.begins_with("user://"):
		return "community staging root must be inside user://"
	if _staging_root == "user://" or _staging_root.is_empty():
		return "community staging root must name a child directory"
	return ""

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
		if directory.current_is_dir() and not directory.is_link(name):
			_remove_tree(child)
		else:
			DirAccess.remove_absolute(child)
	directory.list_dir_end()
	DirAccess.remove_absolute(absolute_path)

static func _catalog_before(a: Dictionary, b: Dictionary) -> bool:
	var format_a := str(a.get("package_format", ""))
	var format_b := str(b.get("package_format", ""))
	if format_a == format_b:
		var name_a := str(a.get("name", ""))
		var name_b := str(b.get("name", ""))
		if name_a == name_b:
			return str(a.get("content_id", "")) < str(b.get("content_id", ""))
		return name_a < name_b
	return format_a < format_b

func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
