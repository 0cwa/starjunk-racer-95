extends Node

var _failures := PackedStringArray()
var _race: PrototypeRace

func _ready() -> void:
	var packed: PackedScene = load("res://src/race/prototype_race.tscn")
	_race = packed.instantiate()
	_race.input_enabled = false
	add_child(_race)
	await get_tree().process_frame

	var bundle := _make_bundle()
	var error := _race.mount_community_bundle(bundle)
	_check(error.is_empty(), "community bundle should mount: %s" % error)
	_check(bundle.is_empty(), "successful mount should consume bundle runtime ownership")
	_check(_race.active_car_content_id == "sha256:car-test", "race should retain exact car content id")
	_check(_race.active_track_content_id == "sha256:track-test", "race should retain exact track content id")
	_check(_race.checkpoint_count() == 2, "community checkpoints should replace generated checkpoints")
	_check(_race.find_child("Road", true, false) == null, "generated road should be removed after community mount")
	_check(_race.find_child("MountedTrackVisual", true, false) != null, "community track visual should be mounted")
	_check(_race.vehicle.find_child("CommunityCarVisual", true, false) != null, "community car visual should be mounted")
	_check(_race.vehicle.performance_profile.profile_id == &"prototype_balanced_01", "race should use trusted bundle performance profile")

	await _physics_frames(150)
	_check(_race.vehicle.grounded_wheel_count() >= 3, "community track collision should support the trusted vehicle")
	_race.reset_vehicle()
	_check(_race.vehicle.global_position.distance_to(Vector3(0.0, 0.78, 0.0)) < 0.01, "community spawn should drive reset position")

	_race.restore_generated_content()
	_check(_race.active_car_content_id.is_empty() and _race.active_track_content_id.is_empty(), "restoring generated content should clear community ids")
	_check(_race.checkpoint_count() == 8, "generated checkpoint set should be restored")
	_check(_race.find_child("Road", true, false) != null, "generated road should be restored")
	_finish()

func _make_bundle() -> Dictionary:
	var car_visual := Node3D.new()
	car_visual.name = "ImportedCarRoot"
	var car_mesh := MeshInstance3D.new()
	car_mesh.mesh = BoxMesh.new()
	car_visual.add_child(car_mesh)

	var track_visual := Node3D.new()
	track_visual.name = "MountedTrackVisual"
	var track_mesh := MeshInstance3D.new()
	var track_box := BoxMesh.new()
	track_box.size = Vector3(20.0, 0.2, 20.0)
	track_mesh.mesh = track_box
	track_visual.add_child(track_mesh)

	var collision_root := Node3D.new()
	collision_root.name = "MountedTrackCollision"
	var body := StaticBody3D.new()
	body.position = Vector3(0.0, -0.5, 0.0)
	var collision_shape := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(40.0, 1.0, 40.0)
	collision_shape.shape = shape
	body.add_child(collision_shape)
	collision_root.add_child(body)

	var profile: VehiclePerformanceProfile = load("res://src/vehicle/profiles/prototype_balanced_01.tres")
	return {
		"ok": true,
		"car_content_id": "sha256:car-test",
		"track_content_id": "sha256:track-test",
		"car_manifest": {
			"format": "starjunk95/car/1",
			"name": "Mounted Car",
			"model": "model.glb",
			"performance_profile": "prototype_balanced_01",
			"visual": {"scale": 1.0},
		},
		"track_manifest": {
			"format": "starjunk95/track/1",
			"name": "Mounted Track",
		},
		"car_visual": car_visual,
		"performance_profile": profile,
		"track_visual": track_visual,
		"track_collision": collision_root,
		"checkpoints": [
			{"id": "start", "position": [0.0, 1.0, 0.0], "size": [5.0, 2.0, 1.0]},
			{"id": "cp-1", "position": [0.0, 1.0, -10.0], "size": [5.0, 2.0, 1.0]},
		],
		"spawn_points": [
			Transform3D(Basis.IDENTITY, Vector3(0.0, 0.78, 0.0)),
		],
	}

func _physics_frames(count: int) -> void:
	for _index in range(count):
		await get_tree().physics_frame

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("Community content playable race test passed")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("TEST FAILURE: " + failure)
	get_tree().quit(1)
