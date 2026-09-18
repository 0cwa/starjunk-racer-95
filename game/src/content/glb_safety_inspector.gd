class_name GLBSafetyInspector
extends RefCounted

const GLB_MAGIC := 0x46546C67
const GLB_VERSION := 2
const GLB_JSON_CHUNK := 0x4E4F534A

static func validate_embedded_only(bytes: PackedByteArray) -> String:
	if bytes.size() < 20:
		return "GLB is too small"
	if bytes.decode_u32(0) != GLB_MAGIC:
		return "invalid GLB magic"
	if bytes.decode_u32(4) != GLB_VERSION:
		return "unsupported GLB version"
	var declared_length := bytes.decode_u32(8)
	if declared_length != bytes.size():
		return "GLB length header does not match file size"
	var json_length := bytes.decode_u32(12)
	if bytes.decode_u32(16) != GLB_JSON_CHUNK:
		return "GLB first chunk must be JSON"
	if json_length <= 0 or 20 + json_length > bytes.size():
		return "invalid GLB JSON chunk length"

	var json_bytes := bytes.slice(20, 20 + json_length)
	var parsed = JSON.parse_string(json_bytes.get_string_from_utf8().strip_edges())
	if not parsed is Dictionary:
		return "invalid GLB JSON document"
	return _find_external_uri(parsed)

static func _find_external_uri(value: Variant) -> String:
	if value is Dictionary:
		for key in value.keys():
			var child = value[key]
			if str(key) == "uri":
				if not child is String:
					return "GLB uri must be a string"
				var uri := str(child)
				if not uri.begins_with("data:"):
					return "GLB contains external uri dependency"
			var nested := _find_external_uri(child)
			if not nested.is_empty():
				return nested
	elif value is Array:
		for child in value:
			var nested := _find_external_uri(child)
			if not nested.is_empty():
				return nested
	return ""
