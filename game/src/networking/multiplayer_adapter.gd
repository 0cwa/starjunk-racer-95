class_name MultiplayerAdapter
extends RefCounted

signal room_joined(room_id: String)
signal room_left(room_id: String)
signal racer_snapshot_received(peer_id: String, snapshot: Dictionary)
signal race_event_received(event: Dictionary)
signal race_event_published(event: Dictionary)
signal race_event_publish_failed(event: Dictionary, reason: String)
signal peer_joined(peer_id: String, metadata: Dictionary)
signal peer_left(peer_id: String)
signal content_reference_received(peer_id: String, content_reference: Dictionary)
signal connection_state_changed(state: StringName)

# This adapter is the game-facing seam. A Spritely implementation owns room
# capabilities/invitations; a separate realtime lane may carry validated
# RaceProtocol snapshots without exposing Goblins objects to gameplay code.

func create_room(_options: Dictionary = {}) -> String:
	push_error("MultiplayerAdapter.create_room is not implemented")
	return ""

func join_room(_room_reference: String, _racer_id: String = "") -> bool:
	push_error("MultiplayerAdapter.join_room is not implemented")
	return false

func leave_room() -> void:
	pass

func publish_racer_snapshot(_snapshot: Dictionary) -> void:
	pass

func publish_race_event(_event: Dictionary) -> void:
	pass
