class_name CommunityPackageArchive
extends RefCounted

const MAX_ARCHIVE_BYTES := 384 * 1024 * 1024
const MAX_ENTRY_COUNT := 2048
const MAX_ENTRY_UNCOMPRESSED_BYTES := 256 * 1024 * 1024
const MAX_TOTAL_UNCOMPRESSED_BYTES := 512 * 1024 * 1024
const MAX_COMPRESSION_RATIO := 100.0
const MAX_PATH_BYTES := 240
const EOCD_MIN_BYTES := 22
const EOCD_MAX_SEARCH_BYTES := 65557

const EOCD_SIGNATURE := 0x06054B50
const CENTRAL_FILE_SIGNATURE := 0x02014B50
const ZIP_HOST_UNIX := 3
const UNIX_FILE_TYPE_MASK := 0xF000
const UNIX_SYMLINK_TYPE := 0xA000

var _package_loader := StarjunkPackageLoader.new()

func stage_zip(zip_path: String, staging_root: String) -> Dictionary:
	if not staging_root.begins_with("user://"):
		return _error("staging_root must be inside user://")

	var staging_absolute := ProjectSettings.globalize_path(staging_root)
	if DirAccess.dir_exists_absolute(staging_absolute) or FileAccess.file_exists(staging_root):
		return _error("staging_root must not already exist")

	var preflight := preflight_zip(zip_path)
	if not bool(preflight.get("ok", false)):
		return preflight

	var make_root_error := DirAccess.make_dir_recursive_absolute(staging_absolute)
	if make_root_error != OK:
		return _error("unable to create staging directory")

	var reader := ZIPReader.new()
	var open_error := reader.open(zip_path)
	if open_error != OK:
		_remove_tree(staging_absolute)
		return _error("unable to open ZIP archive with ZIPReader")

	for entry in preflight["entries"]:
		var relative_path := str(entry["path"])
		var destination := staging_root.path_join(relative_path)
		var destination_absolute := ProjectSettings.globalize_path(destination)

		if bool(entry["directory"]):
			var dir_error := DirAccess.make_dir_recursive_absolute(destination_absolute)
			if dir_error != OK:
				reader.close()
				_remove_tree(staging_absolute)
				return _error("unable to create staged directory: %s" % relative_path)
			continue

		var parent_error := DirAccess.make_dir_recursive_absolute(destination_absolute.get_base_dir())
		if parent_error != OK:
			reader.close()
			_remove_tree(staging_absolute)
			return _error("unable to create staged file parent: %s" % relative_path)

		var data: PackedByteArray = reader.read_file(relative_path)
		if data.size() != int(entry["uncompressed_size"]):
			reader.close()
			_remove_tree(staging_absolute)
			return _error("ZIP entry size changed during extraction: %s" % relative_path)

		var output := FileAccess.open(destination, FileAccess.WRITE)
		if output == null:
			reader.close()
			_remove_tree(staging_absolute)
			return _error("unable to write staged file: %s" % relative_path)
		output.store_buffer(data)

	reader.close()

	var manifest_path := staging_root.path_join("manifest.json")
	var manifest_result := _package_loader.load_manifest(manifest_path)
	if not bool(manifest_result.get("ok", false)):
		_remove_tree(staging_absolute)
		return _error("staged manifest is invalid: %s" % str(manifest_result.get("error", "unknown error")))

	return {
		"ok": true,
		"package_root": staging_root,
		"manifest": manifest_result["manifest"],
		"entry_count": preflight["entry_count"],
		"total_uncompressed_bytes": preflight["total_uncompressed_bytes"],
	}

func preflight_zip(zip_path: String) -> Dictionary:
	var file := FileAccess.open(zip_path, FileAccess.READ)
	if file == null:
		return _error("unable to open ZIP archive")

	var archive_size := file.get_length()
	if archive_size < EOCD_MIN_BYTES:
		return _error("ZIP archive is too small")
	if archive_size > MAX_ARCHIVE_BYTES:
		return _error("ZIP archive exceeds %d bytes" % MAX_ARCHIVE_BYTES)

	var tail_size := mini(archive_size, EOCD_MAX_SEARCH_BYTES)
	file.seek(archive_size - tail_size)
	var tail := file.get_buffer(tail_size)
	var eocd_index := _find_eocd(tail)
	if eocd_index < 0:
		return _error("ZIP end-of-central-directory record not found")

	var disk_number := _u16(tail, eocd_index + 4)
	var central_disk := _u16(tail, eocd_index + 6)
	var entries_on_disk := _u16(tail, eocd_index + 8)
	var entry_count := _u16(tail, eocd_index + 10)
	var central_size := _u32(tail, eocd_index + 12)
	var central_offset := _u32(tail, eocd_index + 16)
	var comment_length := _u16(tail, eocd_index + 20)
	var eocd_absolute := archive_size - tail_size + eocd_index

	if disk_number != 0 or central_disk != 0 or entries_on_disk != entry_count:
		return _error("multi-disk ZIP archives are not supported")
	if entry_count == 0xFFFF or central_size == 0xFFFFFFFF or central_offset == 0xFFFFFFFF:
		return _error("ZIP64 archives are not supported")
	if entry_count <= 0 or entry_count > MAX_ENTRY_COUNT:
		return _error("ZIP entry count is outside 1..%d" % MAX_ENTRY_COUNT)
	if eocd_absolute + EOCD_MIN_BYTES + comment_length != archive_size:
		return _error("ZIP has trailing data or an invalid comment length")
	if central_offset + central_size > eocd_absolute:
		return _error("ZIP central directory is outside archive bounds")

	file.seek(central_offset)
	var entries: Array[Dictionary] = []
	var seen_paths := {}
	var total_uncompressed := 0
	var found_manifest := false

	for _index in range(entry_count):
		if file.get_position() + 46 > archive_size:
			return _error("truncated ZIP central-directory entry")
		if file.get_32() != CENTRAL_FILE_SIGNATURE:
			return _error("invalid ZIP central-directory signature")

		var version_made_by := file.get_16()
		var version_needed := file.get_16()
		var flags := file.get_16()
		var compression_method := file.get_16()
		file.get_16() # modified time
		file.get_16() # modified date
		file.get_32() # crc32
		var compressed_size := file.get_32()
		var uncompressed_size := file.get_32()
		var name_length := file.get_16()
		var extra_length := file.get_16()
		var entry_comment_length := file.get_16()
		var disk_start := file.get_16()
		file.get_16() # internal attributes
		var external_attributes := file.get_32()
		var local_header_offset := file.get_32()

		if version_needed >= 45 or compressed_size == 0xFFFFFFFF or uncompressed_size == 0xFFFFFFFF or local_header_offset == 0xFFFFFFFF:
			return _error("ZIP64 entry metadata is not supported")
		if disk_start != 0:
			return _error("multi-disk ZIP entry is not supported")
		if (flags & 0x1) != 0:
			return _error("encrypted ZIP entries are not supported")
		if compression_method != 0 and compression_method != 8:
			return _error("unsupported ZIP compression method %d" % compression_method)
		if name_length <= 0 or name_length > MAX_PATH_BYTES:
			return _error("ZIP entry path length is invalid")
		if file.get_position() + name_length + extra_length + entry_comment_length > archive_size:
			return _error("truncated ZIP central-directory variable data")

		var name_bytes := file.get_buffer(name_length)
		if not _safe_ascii_name_bytes(name_bytes):
			return _error("ZIP entry paths must use printable ASCII")
		var path := name_bytes.get_string_from_utf8()
		var path_error := _validate_entry_path(path)
		if not path_error.is_empty():
			return _error(path_error)

		if extra_length > 0:
			file.seek(file.get_position() + extra_length)
		if entry_comment_length > 0:
			file.seek(file.get_position() + entry_comment_length)

		var canonical_path := path.to_lower()
		if seen_paths.has(canonical_path):
			return _error("ZIP contains duplicate or case-colliding path: %s" % path)
		seen_paths[canonical_path] = true

		var host_system := (version_made_by >> 8) & 0xFF
		var unix_mode := (external_attributes >> 16) & 0xFFFF
		if host_system == ZIP_HOST_UNIX and (unix_mode & UNIX_FILE_TYPE_MASK) == UNIX_SYMLINK_TYPE:
			return _error("ZIP symlink entries are not supported")

		var is_directory := path.ends_with("/")
		if is_directory:
			if uncompressed_size != 0:
				return _error("ZIP directory entry has file data")
		else:
			if uncompressed_size > MAX_ENTRY_UNCOMPRESSED_BYTES:
				return _error("ZIP entry exceeds %d uncompressed bytes" % MAX_ENTRY_UNCOMPRESSED_BYTES)
			if uncompressed_size > 0:
				if compressed_size <= 0:
					return _error("non-empty ZIP entry has zero compressed size")
				var ratio := float(uncompressed_size) / float(compressed_size)
				if ratio > MAX_COMPRESSION_RATIO:
					return _error("ZIP entry exceeds %.1f:1 compression ratio" % MAX_COMPRESSION_RATIO)
			total_uncompressed += uncompressed_size
			if total_uncompressed > MAX_TOTAL_UNCOMPRESSED_BYTES:
				return _error("ZIP exceeds %d total uncompressed bytes" % MAX_TOTAL_UNCOMPRESSED_BYTES)

		if path == "manifest.json":
			if is_directory:
				return _error("manifest.json must be a file")
			found_manifest = true

		entries.append({
			"path": path,
			"directory": is_directory,
			"compressed_size": compressed_size,
			"uncompressed_size": uncompressed_size,
			"compression_method": compression_method,
			"local_header_offset": local_header_offset,
		})

	var central_end := central_offset + central_size
	if file.get_position() != central_end:
		return _error("ZIP central-directory size does not match parsed entries")
	if not found_manifest:
		return _error("ZIP package requires manifest.json at archive root")

	return {
		"ok": true,
		"entries": entries,
		"entry_count": entry_count,
		"total_uncompressed_bytes": total_uncompressed,
		"archive_bytes": archive_size,
	}

func _find_eocd(data: PackedByteArray) -> int:
	if data.size() < EOCD_MIN_BYTES:
		return -1
	for index in range(data.size() - EOCD_MIN_BYTES, -1, -1):
		if _u32(data, index) == EOCD_SIGNATURE:
			return index
	return -1

func _u16(data: PackedByteArray, offset: int) -> int:
	if offset < 0 or offset + 2 > data.size():
		return -1
	return int(data[offset]) | (int(data[offset + 1]) << 8)

func _u32(data: PackedByteArray, offset: int) -> int:
	if offset < 0 or offset + 4 > data.size():
		return -1
	return (
		int(data[offset])
		| (int(data[offset + 1]) << 8)
		| (int(data[offset + 2]) << 16)
		| (int(data[offset + 3]) << 24)
	)

func _safe_ascii_name_bytes(data: PackedByteArray) -> bool:
	for value in data:
		if value < 0x20 or value > 0x7E:
			return false
	return true

func _validate_entry_path(path: String) -> String:
	if path.is_empty():
		return "ZIP entry path must not be empty"
	if path.begins_with("/") or path.begins_with("~") or path.contains(":") or path.contains("\\"):
		return "ZIP entry path must be package-relative"
	if path.contains("//"):
		return "ZIP entry path must not contain empty components"

	var clean_path := path.substr(0, path.length() - 1) if path.ends_with("/") else path
	if clean_path.is_empty():
		return "ZIP entry path must not name archive root"
	for component in clean_path.split("/", true):
		if component.is_empty() or component == "." or component == "..":
			return "ZIP entry path contains unsafe traversal component"
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
		if directory.current_is_dir():
			_remove_tree(child)
		else:
			DirAccess.remove_absolute(child)
	directory.list_dir_end()
	DirAccess.remove_absolute(absolute_path)

func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
