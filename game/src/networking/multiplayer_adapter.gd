class_name MultiplayerAdapter
extends RefCounted

signal room_joined(room_id: String)
signal room_left(room_id: String)
signal racer_snapshot_received(peer_id: String, snapshot: Dictionary)
signal race_event_received(event: Dictionary)

func create_room(_options: Dictionary = {}) -> String:
	push_error("MultiplayerAdapter.create_room is not implemented")
	return ""

func join_room(_room_reference: String) -> bool:
	push_error("MultiplayerAdapter.join_room is not implemented")
	return false

func leave_room() -> void:
	pass

func publish_racer_snapshot(_snapshot: Dictionary) -> void:
	pass

func publish_race_event(_event: Dictionary) -> void:
	pass
