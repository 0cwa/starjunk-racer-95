class_name CommunityPackageIdentity
extends RefCounted

const DESCRIPTOR_FORMAT := "starjunk95/content/1"
const HASH_CHUNK_BYTES := 1024 * 1024

var _package_loader := StarjunkPackageLoader.new()

func build_descriptor(package_root: String) -> Dictionary:
	var manifest_result := _package_loader.load_manifest(package_root.path_join("manifest.json"))
	if not bool(manifest_result.get("ok", false)):
		return _error("invalid package manifest: %s" % str(manifest_result.get("error", "unknown error")))

	var paths: Array[String] = []
	var collect_error := _collect_files(package_root, "", paths)
	if not collect_error.is_empty():
		return _error(collect_error)
	if paths.is_empty():
		return _error("package contains no files")
	if paths.size() > CommunityPackageArchive.MAX_ENTRY_COUNT:
		return _error("package contains too many files")

	paths.sort()

	var package_hash := HashingContext.new()
	var start_error := package_hash.start(HashingContext.HASH_SHA256)
	if start_error != OK:
		return _error("unable to initialize package SHA-256")
	package_hash.update((DESCRIPTOR_FORMAT + "\n").to_utf8_buffer())

	var files: Array[Dictionary] = []
	var total_bytes := 0
	for relative_path in paths:
		var file_result := _hash_file(package_root.path_join(relative_path))
		if not bool(file_result.get("ok", false)):
			return _error("%s: %s" % [relative_path, str(file_result.get("error", "hash failed"))])
		var file_size := int(file_result["size"])
		if file_size > CommunityPackageArchive.MAX_ENTRY_UNCOMPRESSED_BYTES:
			return _error("%s exceeds per-file package limit" % relative_path)
		total_bytes += file_size
		if total_bytes > CommunityPackageArchive.MAX_TOTAL_UNCOMPRESSED_BYTES:
			return _error("package exceeds total byte limit")

		var digest_bytes: PackedByteArray = file_result["digest"]
		var digest_hex := digest_bytes.hex_encode()
		files.append({
			"path": relative_path,
			"size": file_size,
			"sha256": "sha256:" + digest_hex,
		})

		# Safe package paths are printable ASCII and cannot contain tabs/newlines,
		# so this line-oriented encoding is canonical and unambiguous.
		var canonical_line := "%s\t%d\t%s\n" % [relative_path, file_size, digest_hex]
		package_hash.update(canonical_line.to_utf8_buffer())

	var content_id := "sha256:" + package_hash.finish().hex_encode()
	return {
		"ok": true,
		"format": DESCRIPTOR_FORMAT,
		"content_id": content_id,
		"package_format": str(manifest_result["manifest"]["format"]),
		"file_count": files.size(),
		"total_bytes": total_bytes,
		"files": files,
		"manifest": manifest_result["manifest"],
	}

func _collect_files(package_root: String, relative_dir: String, output: Array[String]) -> String:
	var directory_path := package_root if relative_dir.is_empty() else package_root.path_join(relative_dir)
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return "unable to open package directory: %s" % relative_dir

	directory.list_dir_begin()
	while true:
		var name := directory.get_next()
		if name.is_empty():
			break
		if name == "." or name == "..":
			continue
		if directory.is_link(name):
			directory.list_dir_end()
			return "package contains symlink or reparse point: %s" % name

		var relative_path := name if relative_dir.is_empty() else relative_dir.path_join(name)
		var path_error := _validate_identity_path(relative_path)
		if not path_error.is_empty():
			directory.list_dir_end()
			return path_error

		if directory.current_is_dir():
			var recurse_error := _collect_files(package_root, relative_path, output)
			if not recurse_error.is_empty():
				directory.list_dir_end()
				return recurse_error
		else:
			output.append(relative_path)
			if output.size() > CommunityPackageArchive.MAX_ENTRY_COUNT:
				directory.list_dir_end()
				return "package contains too many files"
	directory.list_dir_end()
	return ""

func _hash_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _error("unable to open file")
	var size := file.get_length()
	if size < 0:
		return _error("invalid file size")

	var context := HashingContext.new()
	var start_error := context.start(HashingContext.HASH_SHA256)
	if start_error != OK:
		return _error("unable to initialize file SHA-256")

	while file.get_position() < size:
		var remaining := size - file.get_position()
		var chunk_size := mini(remaining, HASH_CHUNK_BYTES)
		var chunk := file.get_buffer(chunk_size)
		if chunk.size() != chunk_size:
			return _error("short read while hashing file")
		context.update(chunk)

	return {
		"ok": true,
		"size": size,
		"digest": context.finish(),
	}

func _validate_identity_path(path: String) -> String:
	var bytes := path.to_utf8_buffer()
	if bytes.is_empty() or bytes.size() > CommunityPackageArchive.MAX_PATH_BYTES:
		return "package path has invalid length"
	for value in bytes:
		if value < 0x20 or value > 0x7E:
			return "package paths must use printable ASCII"
	if path.begins_with("/") or path.begins_with("~") or path.contains(":") or path.contains("\\"):
		return "package path must be relative and portable"
	if path.contains("//"):
		return "package path contains empty component"
	for component in path.split("/", true):
		if component.is_empty() or component == "." or component == "..":
			return "package path contains unsafe traversal component"
	return ""

func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
