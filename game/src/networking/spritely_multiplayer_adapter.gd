class_name SpritelyMultiplayerAdapter
extends MultiplayerAdapter

const STATE_DISCONNECTED: StringName = &"disconnected"
const STATE_CONNECTING: StringName = &"connecting"
const STATE_CONNECTED: StringName = &"connected"
const STATE_UNAVAILABLE: StringName = &"unavailable"

var _bridge_port: Variant
var _room_reference := ""
var _racer_id := ""
var _join_pending := false
var _joined := false
var _ready_pending := false
var _pending_ready_event: Dictionary = {}

func _init(bridge_port: Variant = null) -> void:
	_bridge_port = bridge_port if bridge_port != null else SpritelyBrowserBridgePort.new()
	if _bridge_port != null and _bridge_port.has_signal("join_completed"):
		_bridge_port.connect("join_completed", _on_join_completed)
	if _bridge_port != null and _bridge_port.has_signal("ready_completed"):
		_bridge_port.connect("ready_completed", _on_ready_completed)

func join_room(room_reference: String, racer_id: String = "") -> bool:
	if _join_pending or _joined:
		return false
	if not _valid_room_reference(room_reference) or not _valid_racer_id(racer_id):
		return false
	if not _bridge_available():
		connection_state_changed.emit(STATE_UNAVAILABLE)
		return false

	_room_reference = room_reference
	_racer_id = racer_id
	_join_pending = true
	connection_state_changed.emit(STATE_CONNECTING)
	if bool(_bridge_port.call("request_join", room_reference, racer_id)):
		return true

	_join_pending = false
	_room_reference = ""
	_racer_id = ""
	connection_state_changed.emit(STATE_UNAVAILABLE)
	return false

func leave_room() -> void:
	if not _joined and not _join_pending:
		return
	var previous_room := _room_reference
	var was_joined := _joined
	var authority_released := true
	if _bridge_port != null and _bridge_port.has_method("release_room"):
		authority_released = bool(_bridge_port.call("release_room"))
	_join_pending = false
	_joined = false
	_ready_pending = false
	_pending_ready_event.clear()
	_room_reference = ""
	_racer_id = ""
	if was_joined and not previous_room.is_empty():
		room_left.emit(previous_room)
	connection_state_changed.emit(
		STATE_DISCONNECTED if authority_released else STATE_UNAVAILABLE
	)

func publish_race_event(event: Dictionary) -> void:
	var event_copy := event.duplicate(true)
	var validation_error := RaceProtocol.validate_event(event_copy)
	if not validation_error.is_empty():
		race_event_publish_failed.emit(event_copy, validation_error)
		return
	if not _joined:
		race_event_publish_failed.emit(event_copy, "not joined to a room")
		return
	if str(event_copy.get("racer_id", "")) != _racer_id:
		race_event_publish_failed.emit(event_copy, "event racer does not match local racer")
		return
	if str(event_copy.get("type", "")) != RaceProtocol.EVENT_RACER_READY:
		race_event_publish_failed.emit(event_copy, "control event is not supported by browser bridge yet")
		return

	var data: Dictionary = event_copy["data"]
	if not bool(data.get("ready", false)):
		race_event_publish_failed.emit(event_copy, "unready publication is not supported by browser bridge yet")
		return
	if _ready_pending:
		race_event_publish_failed.emit(event_copy, "readiness publication already pending")
		return
	if not _bridge_available():
		race_event_publish_failed.emit(event_copy, "browser bridge is unavailable")
		return

	_ready_pending = true
	_pending_ready_event = event_copy
	if bool(_bridge_port.call(
		"request_ready",
		str(data["car_content_id"]),
		str(data["track_content_id"])
	)):
		return

	_ready_pending = false
	_pending_ready_event.clear()
	race_event_publish_failed.emit(event_copy, "browser bridge refused readiness request")

func _bridge_available() -> bool:
	return (
		_bridge_port != null
		and _bridge_port.has_method("is_available")
		and bool(_bridge_port.call("is_available"))
	)

func _valid_room_reference(room_reference: String) -> bool:
	return (
		not room_reference.is_empty()
		and room_reference.length() <= RaceProtocol.MAX_CAPABILITY_REFERENCE_BYTES
		and room_reference.begins_with("ocapn://")
	)

func _valid_racer_id(racer_id: String) -> bool:
	return not racer_id.is_empty() and racer_id.length() <= RaceProtocol.MAX_RACER_ID_BYTES

func _on_join_completed(
		success: bool,
		room_reference: String,
		racer_id: String,
		_error: String
) -> void:
	if not _join_pending:
		return
	if room_reference != _room_reference or racer_id != _racer_id:
		return
	_join_pending = false
	if not success:
		_room_reference = ""
		_racer_id = ""
		connection_state_changed.emit(STATE_DISCONNECTED)
		return
	_joined = true
	connection_state_changed.emit(STATE_CONNECTED)
	room_joined.emit(room_reference)

func _on_ready_completed(success: bool, error: String) -> void:
	if not _ready_pending:
		return
	var event := _pending_ready_event.duplicate(true)
	_ready_pending = false
	_pending_ready_event.clear()
	if success:
		race_event_published.emit(event)
		return
	race_event_publish_failed.emit(
		event,
		error if not error.is_empty() else "browser readiness failed"
	)
