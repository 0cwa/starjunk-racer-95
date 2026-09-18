class_name CommunityRaceBundle
extends RefCounted

var _identity := CommunityPackageIdentity.new()
var _car_importer := CommunityCarImporter.new()
var _track_importer := CommunityTrackImporter.new()

func import_bundle(car_package_root: String, track_package_root: String) -> Dictionary:
	var car_descriptor := _identity.build_descriptor(car_package_root)
	if not bool(car_descriptor.get("ok", false)):
		return _error("car package identity: %s" % str(car_descriptor.get("error", "failed")))
	if str(car_descriptor.get("package_format", "")) != StarjunkPackageLoader.CAR_FORMAT:
		return _error("car package root does not contain a car package")

	var track_descriptor := _identity.build_descriptor(track_package_root)
	if not bool(track_descriptor.get("ok", false)):
		return _error("track package identity: %s" % str(track_descriptor.get("error", "failed")))
	if str(track_descriptor.get("package_format", "")) != StarjunkPackageLoader.TRACK_FORMAT:
		return _error("track package root does not contain a track package")

	var car_result := _car_importer.import_visual(
		car_package_root,
		car_descriptor["manifest"]
	)
	if not bool(car_result.get("ok", false)):
		return _error("car import: %s" % str(car_result.get("error", "failed")))

	var car_visual: Node = car_result["node"]
	var track_result := _track_importer.import_track(
		track_package_root,
		track_descriptor["manifest"]
	)
	if not bool(track_result.get("ok", false)):
		car_visual.free()
		return _error("track import: %s" % str(track_result.get("error", "failed")))

	return {
		"ok": true,
		"car_content_id": str(car_descriptor["content_id"]),
		"track_content_id": str(track_descriptor["content_id"]),
		"car_manifest": car_descriptor["manifest"].duplicate(true),
		"track_manifest": track_descriptor["manifest"].duplicate(true),
		"car_visual": car_visual,
		"performance_profile": car_result["performance_profile"],
		"track_visual": track_result["visual"],
		"track_collision": track_result["collision"],
		"track_collision_mesh_count": track_result["collision_mesh_count"],
		"track_collision_triangle_count": track_result["collision_triangle_count"],
		"checkpoints": track_result["checkpoints"].duplicate(true),
		"spawn_points": track_result["spawn_points"].duplicate(),
	}

static func release(bundle: Dictionary) -> void:
	for key in ["car_visual", "track_visual", "track_collision"]:
		var value = bundle.get(key)
		if value is Node and is_instance_valid(value):
			value.free()
	bundle.clear()

func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
