class_name RaceContentAgreement
extends RefCounted

var _content_service: CommunityContentService

func _init(content_service: CommunityContentService = null) -> void:
	_content_service = content_service if content_service != null else CommunityContentService.new()

func verify(room_config: Dictionary, car_reference_event: Dictionary) -> Dictionary:
	var room_error := RaceProtocol.validate_room_config(room_config)
	if not room_error.is_empty():
		return _error("room config: %s" % room_error)

	var event_error := RaceProtocol.validate_event(car_reference_event)
	if not event_error.is_empty():
		return _error("car reference event: %s" % event_error)
	if str(car_reference_event.get("type", "")) != RaceProtocol.EVENT_CONTENT_REFERENCE:
		return _error("car reference must be a content_reference event")

	var data: Dictionary = car_reference_event["data"]
	if str(data.get("kind", "")) != "car":
		return _error("content_reference must identify a car")

	var track_content_id := str(room_config["track_content_id"])
	var car_content_id := str(data["content_id"])

	var track := _content_service.verify_content(
		track_content_id,
		StarjunkPackageLoader.TRACK_FORMAT
	)
	if not bool(track.get("ok", false)):
		return _error("room track is not locally verified: %s" % str(track.get("error", "failed")))

	var car := _content_service.verify_content(
		car_content_id,
		StarjunkPackageLoader.CAR_FORMAT
	)
	if not bool(car.get("ok", false)):
		return _error("racer car is not locally verified: %s" % str(car.get("error", "failed")))

	return {
		"ok": true,
		"protocol": RaceProtocol.CONTROL_PROTOCOL,
		"track_reference": str(room_config["track_reference"]),
		"track_content_id": track_content_id,
		"car_reference": str(data["reference"]),
		"car_content_id": car_content_id,
		"track": track,
		"car": car,
	}

func make_ready_event(
		agreement: Dictionary,
		sequence: int,
		racer_id: String
) -> Dictionary:
	if not bool(agreement.get("ok", false)):
		return {}
	var event := RaceProtocol.make_racer_ready_event(
		sequence,
		racer_id,
		true,
		str(agreement.get("car_content_id", "")),
		str(agreement.get("track_content_id", ""))
	)
	if not RaceProtocol.validate_event(event).is_empty():
		return {}
	return event

func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
