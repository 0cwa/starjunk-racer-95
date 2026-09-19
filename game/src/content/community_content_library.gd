class_name CommunityContentLibrary
extends RefCounted

const DEFAULT_ROOT := "user://starjunk95/library"
const COPY_CHUNK_BYTES := 1024 * 1024

var _library_root: String
var _identity := CommunityPackageIdentity.new()

func _init(library_root: String = DEFAULT_ROOT) -> void:
	_library_root = library_root.trim_suffix("/")

func library_root() -> String:
	return _library_root

func install_staged(staged_root: String) -> Dictionary:
	var root_error := _validate_library_root()
	if not root_error.is_empty():
		return _error(root_error)

	var descriptor := _identity.build_descriptor(staged_root)
	if not bool(descriptor.get("ok", false)):
		return _error("staged package identity: %s" % str(descriptor.get("error", "failed")))

	var content_id := str(descriptor["content_id"]).to_lower()
	var digest := _digest_from_content_id(content_id)
	if digest.is_empty():
		return _error("identity builder returned an invalid content id")

	var ensure_error := _ensure_library_root()
	if not ensure_error.is_empty():
		return _error(ensure_error)

	var target_root := _library_root.path_join(digest)
	var target_absolute := ProjectSettings.globalize_path(target_root)
	if DirAccess.dir_exists_absolute(target_absolute):
		var existing := resolve(content_id)
		if not bool(existing.get("ok", false)):
			return _error("existing library entry failed integrity verification: %s" % str(existing.get("error", "failed")))
		existing["installed"] = false
		return existing

	var temp_name := ".installing-%s-%d" % [digest, Time.get_ticks_usec()]
	var temp_root := _library_root.path_join(temp_name)
	var temp_absolute := ProjectSettings.globalize_path(temp_root)
	if DirAccess.dir_exists_absolute(temp_absolute):
		_remove_tree(temp_absolute)

	var make_error := DirAccess.make_dir_recursive_absolute(temp_absolute)
	if make_error != OK:
		return _error("unable to create temporary library directory")

	var copy_error := _copy_tree(
		ProjectSettings.globalize_path(staged_root),
		temp_absolute,
		""
	)
	if not copy_error.is_empty():
		_remove_tree(temp_absolute)
		return _error("copy failed: %s" % copy_error)

	var copied_descriptor := _identity.build_descriptor(temp_root)
	if not bool(copied_descriptor.get("ok", false)):
		_remove_tree(temp_absolute)
		return _error("copied package identity: %s" % str(copied_descriptor.get("error", "failed")))
	if str(copied_descriptor["content_id"]).to_lower() != content_id:
		_remove_tree(temp_absolute)
		return _error("copied package content id changed during install")

	# A concurrent installer may have won the digest path between our first
	# existence check and the rename. Prefer the verified existing copy.
	if DirAccess.dir_exists_absolute(target_absolute):
		_remove_tree(temp_absolute)
		var concurrent := resolve(content_id)
		if not bool(concurrent.get("ok", false)):
			return _error("concurrent library entry failed integrity verification")
		concurrent["installed"] = false
		return concurrent

	var rename_error := DirAccess.rename_absolute(temp_absolute, target_absolute)
	if rename_error != OK:
		_remove_tree(temp_absolute)
		return _error("unable to atomically install content")

	var installed := resolve(content_id)
	if not bool(installed.get("ok", false)):
		_remove_tree(target_absolute)
		return _error("installed package failed post-rename integrity verification")
	installed["installed"] = true
	return installed

func resolve(content_id: String) -> Dictionary:
	var root_error := _validate_library_root()
	if not root_error.is_empty():
		return _error(root_error)

	var normalized := content_id.to_lower()
	var digest := _digest_from_content_id(normalized)
	if digest.is_empty():
		return _error("invalid SHA-256 content id")

	var package_root := _library_root.path_join(digest)
	var absolute_root := ProjectSettings.globalize_path(package_root)
	if not DirAccess.dir_exists_absolute(absolute_root):
		return _error("content is not installed")

	var descriptor := _identity.build_descriptor(package_root)
	if not bool(descriptor.get("ok", false)):
		return _error("installed package integrity check failed: %s" % str(descriptor.get("error", "failed")))
	if str(descriptor["content_id"]).to_lower() != normalized:
		return _error("installed package bytes do not match requested content id")

	return {
		"ok": true,
		"installed": true,
		"root": package_root,
		"content_id": normalized,
		"package_format": descriptor["package_format"],
		"manifest": descriptor["manifest"].duplicate(true),
		"descriptor": descriptor,
	}

func list_installed() -> Dictionary:
	var root_error := _validate_library_root()
	if not root_error.is_empty():
		return _error(root_error)

	var root_absolute := ProjectSettings.globalize_path(_library_root)
	if not DirAccess.dir_exists_absolute(root_absolute):
		return {"ok": true, "packages": [], "corrupt": []}

	var directory := DirAccess.open(root_absolute)
	if directory == null:
		return _error("unable to open community library")

	var packages: Array[Dictionary] = []
	var corrupt: Array[Dictionary] = []
	directory.list_dir_begin()
	while true:
		var name := directory.get_next()
		if name.is_empty():
			break
		if name == "." or name == ".." or name.begins_with(".installing-"):
			continue
		if not directory.current_is_dir():
			continue
		if directory.is_link(name):
			corrupt.append({"directory": name, "error": "library entry is a link"})
			continue
		var digest := _normalize_digest(name)
		if digest.is_empty():
			corrupt.append({"directory": name, "error": "library directory is not a SHA-256 digest"})
			continue
		var content_id := "sha256:" + digest
		var resolved := resolve(content_id)
		if bool(resolved.get("ok", false)):
			packages.append(resolved)
		else:
			corrupt.append({
				"directory": name,
				"content_id": content_id,
				"error": str(resolved.get("error", "integrity failure")),
			})
	directory.list_dir_end()

	packages.sort_custom(_package_before)
	corrupt.sort_custom(_corrupt_before)
	return {"ok": true, "packages": packages, "corrupt": corrupt}

func uninstall(content_id: String) -> Dictionary:
	var digest := _digest_from_content_id(content_id.to_lower())
	if digest.is_empty():
		return _error("invalid SHA-256 content id")
	var target_absolute := ProjectSettings.globalize_path(_library_root.path_join(digest))
	if not DirAccess.dir_exists_absolute(target_absolute):
		return {"ok": true, "removed": false, "content_id": "sha256:" + digest}
	_remove_tree(target_absolute)
	if DirAccess.dir_exists_absolute(target_absolute):
		return _error("unable to remove installed content")
	return {"ok": true, "removed": true, "content_id": "sha256:" + digest}

func _validate_library_root() -> String:
	if not _library_root.begins_with("user://"):
		return "community library root must be inside user://"
	if _library_root == "user://" or _library_root.is_empty():
		return "community library root must name a child directory"
	return ""

func _ensure_library_root() -> String:
	var absolute_root := ProjectSettings.globalize_path(_library_root)
	var error := DirAccess.make_dir_recursive_absolute(absolute_root)
	if error != OK and error != ERR_ALREADY_EXISTS:
		return "unable to create community library root"
	return ""

func _copy_tree(source_absolute: String, destination_absolute: String, relative_dir: String) -> String:
	var source_dir_path := source_absolute if relative_dir.is_empty() else source_absolute.path_join(relative_dir)
	var source_dir := DirAccess.open(source_dir_path)
	if source_dir == null:
		return "unable to open source directory"

	source_dir.list_dir_begin()
	while true:
		var name := source_dir.get_next()
		if name.is_empty():
			break
		if name == "." or name == "..":
			continue
		if source_dir.is_link(name):
			source_dir.list_dir_end()
			return "source package contains link: %s" % name

		var relative_path := name if relative_dir.is_empty() else relative_dir.path_join(name)
		if not _portable_relative_path(relative_path):
			source_dir.list_dir_end()
			return "source package contains unsafe path: %s" % relative_path

		var source_path := source_absolute.path_join(relative_path)
		var destination_path := destination_absolute.path_join(relative_path)
		if source_dir.current_is_dir():
			var make_error := DirAccess.make_dir_recursive_absolute(destination_path)
			if make_error != OK and make_error != ERR_ALREADY_EXISTS:
				source_dir.list_dir_end()
				return "unable to create destination directory: %s" % relative_path
			var recurse_error := _copy_tree(source_absolute, destination_absolute, relative_path)
			if not recurse_error.is_empty():
				source_dir.list_dir_end()
				return recurse_error
		else:
			var parent_error := DirAccess.make_dir_recursive_absolute(destination_path.get_base_dir())
			if parent_error != OK and parent_error != ERR_ALREADY_EXISTS:
				source_dir.list_dir_end()
				return "unable to create destination parent: %s" % relative_path
			var file_error := _copy_file(source_path, destination_path)
			if not file_error.is_empty():
				source_dir.list_dir_end()
				return file_error
	source_dir.list_dir_end()
	return ""

func _copy_file(source_path: String, destination_path: String) -> String:
	var source := FileAccess.open(source_path, FileAccess.READ)
	if source == null:
		return "unable to open source file"
	var destination := FileAccess.open(destination_path, FileAccess.WRITE)
	if destination == null:
		return "unable to open destination file"
	var total := source.get_length()
	while source.get_position() < total:
		var remaining := total - source.get_position()
		var count := mini(remaining, COPY_CHUNK_BYTES)
		var chunk := source.get_buffer(count)
		if chunk.size() != count:
			return "short read while copying file"
		destination.store_buffer(chunk)
	return ""

func _digest_from_content_id(content_id: String) -> String:
	if not content_id.begins_with("sha256:"):
		return ""
	if content_id.length() != 71:
		return ""
	return _normalize_digest(content_id.substr(7))

func _normalize_digest(value: String) -> String:
	if value.length() != 64:
		return ""
	var lowered := value.to_lower()
	for index in range(lowered.length()):
		var code := lowered.unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 97 and code <= 102)):
			return ""
	return lowered

func _portable_relative_path(path: String) -> bool:
	var bytes := path.to_utf8_buffer()
	if bytes.is_empty() or bytes.size() > CommunityPackageArchive.MAX_PATH_BYTES:
		return false
	for value in bytes:
		if value < 0x20 or value > 0x7E:
			return false
	if path.begins_with("/") or path.begins_with("~") or path.contains(":") or path.contains("\\"):
		return false
	if path.contains("//"):
		return false
	for component in path.split("/", true):
		if component.is_empty() or component == "." or component == "..":
			return false
	return true

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

static func _package_before(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("content_id", "")) < str(b.get("content_id", ""))

static func _corrupt_before(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("directory", "")) < str(b.get("directory", ""))

func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
