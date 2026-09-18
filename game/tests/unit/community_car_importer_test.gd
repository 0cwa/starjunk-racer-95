extends Node

const TEMP_ROOT := "user://starjunk-community-car-import-test"
const MODEL_PATH := TEMP_ROOT + "/model.glb"

var _failures := PackedStringArray()

func _ready() -> void:
	var make_dir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEMP_ROOT))
	_check(make_dir_error == OK or make_dir_error == ERR_ALREADY_EXISTS, "test package directory should exist")
	_check(_write_test_glb(), "test GLB should export")

	var manifest := {
		"format": "starjunk95/car/1",
		"name": "Community Box",
		"model": "model.glb",
		"performance_profile": "prototype_balanced_01",
	}
	var importer := CommunityCarImporter.new()
	var result := importer.import_visual(TEMP_ROOT, manifest)
	_check(bool(result.get("ok", false)), "embedded GLB car should import: %s" % str(result.get("error", "")))
	if bool(result.get("ok", false)):
		var visual: Node = result["node"]
		_check(_count_type(visual, "MeshInstance3D") >= 1, "imported car should retain meshes")
		_check(_count_type(visual, "Camera3D") == 0, "imported car should strip cameras")
		_check(_count_collision_nodes(visual) == 0, "imported car visual should contain no collision authority")
		var profile: VehiclePerformanceProfile = result["performance_profile"]
		_check(profile != null and profile.profile_id == &"prototype_balanced_01", "imported visual should bind trusted game profile")
		visual.free()

	var bytes := _make_json_only_glb('{"asset":{"version":"2.0"},"buffers":[{"uri":"outside.bin","byteLength":4}]}')
	_check(not GLBSafetyInspector.validate_embedded_only(bytes).is_empty(), "external GLB uri must be rejected")

	var data_uri_bytes := _make_json_only_glb('{"asset":{"version":"2.0"},"images":[{"uri":"data:image/png;base64,AA=="}]}')
	_check(GLBSafetyInspector.validate_embedded_only(data_uri_bytes).is_empty(), "embedded data uri should be accepted by structural safety check")

	_cleanup()
	_finish()

func _write_test_glb() -> bool:
	var source := Node3D.new()
	source.name = "CommunityVisual"
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Body"
	mesh_instance.mesh = BoxMesh.new()
	source.add_child(mesh_instance)
	var camera := Camera3D.new()
	camera.name = "UntrustedCamera"
	source.add_child(camera)

	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var append_error := document.append_from_scene(source, state)
	if append_error != OK:
		source.free()
		return false
	var write_error := document.write_to_filesystem(state, MODEL_PATH)
	source.free()
	return write_error == OK and FileAccess.file_exists(MODEL_PATH)

func _make_json_only_glb(json_text: String) -> PackedByteArray:
	var json_bytes := json_text.to_utf8_buffer()
	while json_bytes.size() % 4 != 0:
		json_bytes.append(0x20)
	var result := PackedByteArray()
	result.resize(20 + json_bytes.size())
	result.encode_u32(0, GLBSafetyInspector.GLB_MAGIC)
	result.encode_u32(4, GLBSafetyInspector.GLB_VERSION)
	result.encode_u32(8, result.size())
	result.encode_u32(12, json_bytes.size())
	result.encode_u32(16, GLBSafetyInspector.GLB_JSON_CHUNK)
	for index in range(json_bytes.size()):
		result[20 + index] = json_bytes[index]
	return result

func _count_type(node: Node, type_name: String) -> int:
	var count := 1 if node.get_class() == type_name else 0
	for child in node.get_children():
		count += _count_type(child, type_name)
	return count

func _count_collision_nodes(node: Node) -> int:
	var count := 1 if node is CollisionObject3D or node is CollisionShape3D else 0
	for child in node.get_children():
		count += _count_collision_nodes(child)
	return count

func _cleanup() -> void:
	var absolute_model := ProjectSettings.globalize_path(MODEL_PATH)
	if FileAccess.file_exists(MODEL_PATH):
		DirAccess.remove_absolute(absolute_model)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_ROOT))

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("Community car runtime importer tests passed")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("TEST FAILURE: " + failure)
	get_tree().quit(1)
