class_name SpritelyBrowserBridgePort
extends RefCounted

signal join_completed(success: bool, room_reference: String, racer_id: String, error: String)
signal ready_completed(success: bool, error: String)

var _bridge: Variant = null
var _callbacks: Dictionary = {}
var _next_callback_id := 1

func _init(bridge: Variant = null) -> void:
	_bridge = bridge

func is_available() -> bool:
	var bridge := _resolve_bridge()
	if bridge == null:
		return false
	return str(bridge.controlProtocol) == RaceProtocol.CONTROL_PROTOCOL

func request_join(room_reference: String, racer_id: String) -> bool:
	var bridge := _resolve_bridge()
	if bridge == null or str(bridge.controlProtocol) != RaceProtocol.CONTROL_PROTOCOL:
		return false
	var callback_id := _allocate_callback_id()
	var resolved := JavaScriptBridge.create_callback(
		_on_join_resolved.bind(callback_id, room_reference, racer_id)
	)
	var rejected := JavaScriptBridge.create_callback(
		_on_join_rejected.bind(callback_id, room_reference, racer_id)
	)
	_callbacks[callback_id] = [resolved, rejected]
	var promise = bridge.joinRoom(room_reference, racer_id)
	if promise == null:
		_release_callbacks(callback_id)
		return false
	promise.then(resolved, rejected)
	return true

func release_room() -> bool:
	var bridge := _resolve_bridge()
	if bridge == null or str(bridge.controlProtocol) != RaceProtocol.CONTROL_PROTOCOL:
		return false
	return bool(bridge.leaveRoom())

func request_unready() -> bool:
	var bridge := _resolve_bridge()
	if bridge == null or str(bridge.controlProtocol) != RaceProtocol.CONTROL_PROTOCOL:
		return false
	var callback_id := _allocate_callback_id()
	var resolved := JavaScriptBridge.create_callback(
		_on_ready_resolved.bind(callback_id)
	)
	var rejected := JavaScriptBridge.create_callback(
		_on_ready_rejected.bind(callback_id)
	)
	_callbacks[callback_id] = [resolved, rejected]
	var promise = bridge.becomeUnready()
	if promise == null:
		_release_callbacks(callback_id)
		return false
	promise.then(resolved, rejected)
	return true

func request_ready(car_content_id: String, track_content_id: String) -> bool:
	var bridge := _resolve_bridge()
	if bridge == null or str(bridge.controlProtocol) != RaceProtocol.CONTROL_PROTOCOL:
		return false
	var callback_id := _allocate_callback_id()
	var resolved := JavaScriptBridge.create_callback(
		_on_ready_resolved.bind(callback_id)
	)
	var rejected := JavaScriptBridge.create_callback(
		_on_ready_rejected.bind(callback_id)
	)
	_callbacks[callback_id] = [resolved, rejected]
	var promise = bridge.becomeReady(car_content_id, track_content_id)
	if promise == null:
		_release_callbacks(callback_id)
		return false
	promise.then(resolved, rejected)
	return true

func _resolve_bridge() -> Variant:
	if _bridge == null and OS.has_feature("web"):
		_bridge = JavaScriptBridge.get_interface("StarjunkSpritely")
	return _bridge

func _allocate_callback_id() -> int:
	var callback_id := _next_callback_id
	_next_callback_id += 1
	return callback_id

func _release_callbacks(callback_id: int) -> void:
	_callbacks.erase(callback_id)

func _on_join_resolved(
		arguments: Array,
		callback_id: int,
		room_reference: String,
		racer_id: String
) -> void:
	_release_callbacks(callback_id)
	var returned_reference := ""
	if not arguments.is_empty():
		returned_reference = str(arguments[0])
	if returned_reference != room_reference:
		join_completed.emit(
			false,
			room_reference,
			racer_id,
			"browser bridge returned an unexpected room reference"
		)
		return
	join_completed.emit(true, room_reference, racer_id, "")

func _on_join_rejected(
		_arguments: Array,
		callback_id: int,
		room_reference: String,
		racer_id: String
) -> void:
	_release_callbacks(callback_id)
	join_completed.emit(false, room_reference, racer_id, "browser room join rejected")

func _on_ready_resolved(arguments: Array, callback_id: int) -> void:
	_release_callbacks(callback_id)
	var ready := not arguments.is_empty() and bool(arguments[0])
	ready_completed.emit(ready, "" if ready else "browser readiness was not acknowledged")

func _on_ready_rejected(_arguments: Array, callback_id: int) -> void:
	_release_callbacks(callback_id)
	ready_completed.emit(false, "browser readiness rejected")
