extends Node

const ROOM_REFERENCE := "ocapn://example.invalid/s/browser-room"
const RACER_ID := "racer-95"
const CAR_ID := "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
const TRACK_ID := "sha256:abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"

class FakeBridgePort:
	extends RefCounted

	signal join_completed(success: bool, room_reference: String, racer_id: String, error: String)
	signal ready_completed(success: bool, error: String)

	var available := true
	var join_requests: Array[Dictionary] = []
	var ready_requests: Array[Dictionary] = []
	var release_requests := 0

	func is_available() -> bool:
		return available

	func request_join(room_reference: String, racer_id: String) -> bool:
		if not available:
			return false
		join_requests.append({
			"room_reference": room_reference,
			"racer_id": racer_id,
		})
		return true

	func release_room() -> bool:
		release_requests += 1
		return available

	func request_ready(car_content_id: String, track_content_id: String) -> bool:
		if not available:
			return false
		ready_requests.append({
			"car_content_id": car_content_id,
			"track_content_id": track_content_id,
		})
		return true

var _failures := PackedStringArray()
var _joined := PackedStringArray()
var _left := PackedStringArray()
var _states: Array[StringName] = []
var _published: Array[Dictionary] = []
var _publish_failures: Array[Dictionary] = []

func _ready() -> void:
	_test_join_and_readiness()
	_test_fail_closed_paths()
	_finish()

func _test_join_and_readiness() -> void:
	var bridge := FakeBridgePort.new()
	var adapter := SpritelyMultiplayerAdapter.new(bridge)
	adapter.room_joined.connect(func(room_id: String) -> void:
		_joined.append(room_id)
	)
	adapter.room_left.connect(func(room_id: String) -> void:
		_left.append(room_id)
	)
	adapter.connection_state_changed.connect(func(state: StringName) -> void:
		_states.append(state)
	)
	adapter.race_event_published.connect(func(event: Dictionary) -> void:
		_published.append(event.duplicate(true))
	)
	adapter.race_event_publish_failed.connect(func(event: Dictionary, reason: String) -> void:
		_publish_failures.append({
			"event": event.duplicate(true),
			"reason": reason,
		})
	)

	_check(adapter.join_room(ROOM_REFERENCE, RACER_ID), "valid room join should start")
	_check(bridge.join_requests.size() == 1, "adapter should issue exactly one browser join")
	if bridge.join_requests.size() == 1:
		_check(
			str(bridge.join_requests[0]["room_reference"]) == ROOM_REFERENCE,
			"join should preserve opaque sturdyref"
		)
		_check(
			str(bridge.join_requests[0]["racer_id"]) == RACER_ID,
			"join should preserve racer id"
		)
	_check(
		not _states.is_empty() and _states[-1] == SpritelyMultiplayerAdapter.STATE_CONNECTING,
		"join should surface connecting state"
	)

	bridge.join_completed.emit(true, ROOM_REFERENCE, RACER_ID, "")
	_check(_joined.size() == 1 and _joined[0] == ROOM_REFERENCE, "successful join should emit room_joined")
	_check(
		not _states.is_empty() and _states[-1] == SpritelyMultiplayerAdapter.STATE_CONNECTED,
		"successful join should surface connected state"
	)

	var ready := RaceProtocol.make_racer_ready_event(
		4,
		RACER_ID,
		true,
		CAR_ID,
		TRACK_ID
	)
	adapter.publish_race_event(ready)
	_check(bridge.ready_requests.size() == 1, "positive readiness should cross browser port")
	if bridge.ready_requests.size() == 1:
		_check(
			str(bridge.ready_requests[0]["car_content_id"]) == CAR_ID,
			"ready request should preserve car content id"
		)
		_check(
			str(bridge.ready_requests[0]["track_content_id"]) == TRACK_ID,
			"ready request should preserve track content id"
		)

	bridge.ready_completed.emit(true, "")
	_check(_published.size() == 1, "acknowledged readiness should emit race_event_published")
	if _published.size() == 1:
		_check(_published[0] == ready, "published event should preserve validated payload")
	_check(_publish_failures.is_empty(), "successful readiness should not report publication failure")

	adapter.leave_room()
	_check(bridge.release_requests == 1, "leaving should release browser-held racer authority")
	_check(_left.size() == 1 and _left[0] == ROOM_REFERENCE, "leaving should emit room_left")
	_check(
		not _states.is_empty() and _states[-1] == SpritelyMultiplayerAdapter.STATE_DISCONNECTED,
		"successful authority release should surface disconnected state"
	)

func _test_fail_closed_paths() -> void:
	var bridge := FakeBridgePort.new()
	var adapter := SpritelyMultiplayerAdapter.new(bridge)
	var failures: Array[Dictionary] = []
	adapter.race_event_publish_failed.connect(func(event: Dictionary, reason: String) -> void:
		failures.append({"event": event.duplicate(true), "reason": reason})
	)

	_check(
		not adapter.join_room("https://central.example/room", RACER_ID),
		"non-OCapN room references must fail before browser authority"
	)
	_check(bridge.join_requests.is_empty(), "invalid room reference must not reach browser port")

	bridge.available = false
	_check(
		not adapter.join_room(ROOM_REFERENCE, RACER_ID),
		"unavailable browser bridge should reject join"
	)
	_check(bridge.join_requests.is_empty(), "unavailable bridge must not receive join")
	bridge.available = true

	_check(adapter.join_room(ROOM_REFERENCE, RACER_ID), "valid join should start after bridge recovers")
	bridge.join_completed.emit(true, ROOM_REFERENCE, RACER_ID, "")

	var wrong_racer := RaceProtocol.make_racer_ready_event(
		5,
		"other-racer",
		true,
		CAR_ID,
		TRACK_ID
	)
	adapter.publish_race_event(wrong_racer)
	_check(bridge.ready_requests.is_empty(), "another racer's event must not cross browser port")

	var unready := RaceProtocol.make_racer_ready_event(6, RACER_ID, false)
	adapter.publish_race_event(unready)
	_check(bridge.ready_requests.is_empty(), "unsupported unready event must fail closed")

	var invalid := RaceProtocol.make_event(
		RaceProtocol.EVENT_RACER_READY,
		7,
		RACER_ID,
		{"ready": true}
	)
	adapter.publish_race_event(invalid)
	_check(bridge.ready_requests.is_empty(), "invalid protocol event must not cross browser port")
	_check(failures.size() == 3, "wrong-racer, unready and invalid events should report failures")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("Spritely multiplayer adapter tests passed")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("TEST FAILURE: " + failure)
	get_tree().quit(1)
