extends Node

const TEST_CONTENT_ID := "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

var _failures := PackedStringArray()

func _ready() -> void:
	_test_room_config()
	_test_snapshot()
	_test_control_events()
	_finish()

func _test_room_config() -> void:
	var valid := RaceProtocol.make_room_config(
		0.35,
		3,
		8,
		"ocapn://example.invalid/s/track-cap",
		TEST_CONTENT_ID
	)
	_check(RaceProtocol.validate_room_config(valid).is_empty(), "valid room config should pass")
	var bad_realism := valid.duplicate(true)
	bad_realism["realism"] = 1.5
	_check(not RaceProtocol.validate_room_config(bad_realism).is_empty(), "room realism must be bounded")
	var local_path := valid.duplicate(true)
	local_path["track_reference"] = "file:///tmp/track.json"
	_check(not RaceProtocol.validate_room_config(local_path).is_empty(), "network room track must use a capability reference")
	var mutable_identity := valid.duplicate(true)
	mutable_identity["track_content_id"] = "latest"
	_check(not RaceProtocol.validate_room_config(mutable_identity).is_empty(), "network room track must bind an immutable content ID")

func _test_snapshot() -> void:
	var snapshot := RaceProtocol.make_snapshot(
		12,
		950,
		Vector3(1.0, 2.0, 3.0),
		Quaternion.IDENTITY,
		Vector3(0.0, 0.0, -12.0),
		Vector3(0.0, 0.4, 0.0),
		0.8,
		0.0,
		-0.2
	)
	_check(RaceProtocol.validate_snapshot(snapshot).is_empty(), "valid realtime snapshot should pass")
	var bad_sequence := snapshot.duplicate(true)
	bad_sequence["sequence"] = -1
	_check(not RaceProtocol.validate_snapshot(bad_sequence).is_empty(), "negative snapshot sequence must fail")
	var nan_snapshot := snapshot.duplicate(true)
	nan_snapshot["position"] = [NAN, 0.0, 0.0]
	_check(not RaceProtocol.validate_snapshot(nan_snapshot).is_empty(), "non-finite state must fail")
	var bad_brake := snapshot.duplicate(true)
	bad_brake["controls"]["brake"] = 2.0
	_check(not RaceProtocol.validate_snapshot(bad_brake).is_empty(), "controls must be bounded")

func _test_control_events() -> void:
	var ready := RaceProtocol.make_event(
		RaceProtocol.EVENT_RACER_READY,
		1,
		"racer-95",
		{"ready": true}
	)
	_check(RaceProtocol.validate_event(ready).is_empty(), "ready event should pass")
	var checkpoint := RaceProtocol.make_event(
		RaceProtocol.EVENT_CHECKPOINT,
		2,
		"racer-95",
		{"checkpoint_id": "cp-03", "lap": 0}
	)
	_check(RaceProtocol.validate_event(checkpoint).is_empty(), "checkpoint event should pass")
	var content := RaceProtocol.make_event(
		RaceProtocol.EVENT_CONTENT_REFERENCE,
		3,
		"racer-95",
		{"kind": "car", "reference": "ocapn://example.invalid/s/car-cap", "content_id": TEST_CONTENT_ID}
	)
	_check(RaceProtocol.validate_event(content).is_empty(), "content capability event should pass")
	var unsafe_content := content.duplicate(true)
	unsafe_content["data"]["reference"] = "https://central.example/car.zip"
	_check(not RaceProtocol.validate_event(unsafe_content).is_empty(), "content authority must be represented by a capability reference")
	var missing_identity := content.duplicate(true)
	missing_identity["data"].erase("content_id")
	_check(not RaceProtocol.validate_event(missing_identity).is_empty(), "content references must bind immutable bytes")
	var uppercase_identity := content.duplicate(true)
	uppercase_identity["data"]["content_id"] = TEST_CONTENT_ID.to_upper()
	_check(not RaceProtocol.validate_event(uppercase_identity).is_empty(), "content IDs must use canonical lowercase hex")
	var unknown := ready.duplicate(true)
	unknown["type"] = "run_arbitrary_mod_code"
	_check(not RaceProtocol.validate_event(unknown).is_empty(), "unknown control events must fail closed")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("Race protocol tests passed")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("TEST FAILURE: " + failure)
	get_tree().quit(1)
