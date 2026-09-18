class_name RaceProtocol
extends RefCounted

const CONTROL_PROTOCOL := "starjunk95/race-control/1"
const REALTIME_PROTOCOL := "starjunk95/race-state/1"
const MAX_RACER_ID_BYTES := 96
const MAX_CAPABILITY_REFERENCE_BYTES := 4096
const MAX_EVENT_DATA_KEYS := 24
const MAX_RACERS := 16
const MAX_LAPS := 99

const EVENT_RACER_READY := "racer_ready"
const EVENT_CHECKPOINT := "checkpoint"
const EVENT_LAP_COMPLETE := "lap_complete"
const EVENT_FINISH := "finish"
const EVENT_CONTENT_REFERENCE := "content_reference"
const EVENT_REALTIME_LANE := "realtime_lane"

const ALLOWED_EVENT_TYPES := [
	EVENT_RACER_READY,
	EVENT_CHECKPOINT,
	EVENT_LAP_COMPLETE,
	EVENT_FINISH,
	EVENT_CONTENT_REFERENCE,
	EVENT_REALTIME_LANE,
]

static func make_room_config(
		realism: float,
		laps: int,
		max_racers: int,
		track_reference: String
) -> Dictionary:
	return {
		"protocol": CONTROL_PROTOCOL,
		"realism": realism,
		"laps": laps,
		"max_racers": max_racers,
		"track_reference": track_reference,
	}

static func validate_room_config(config: Dictionary) -> String:
	if str(config.get("protocol", "")) != CONTROL_PROTOCOL:
		return "unsupported control protocol"
	if not _finite_number(config.get("realism")):
		return "realism must be finite"
	var realism := float(config["realism"])
	if realism < 0.0 or realism > 1.0:
		return "realism must be within 0..1"
	if not _integer_in_range(config.get("laps"), 1, MAX_LAPS):
		return "laps must be within 1..%d" % MAX_LAPS
	if not _integer_in_range(config.get("max_racers"), 1, MAX_RACERS):
		return "max_racers must be within 1..%d" % MAX_RACERS
	return _validate_capability_reference("track_reference", config.get("track_reference"))

static func make_snapshot(
		sequence: int,
		physics_tick: int,
		position: Vector3,
		rotation: Quaternion,
		linear_velocity: Vector3,
		angular_velocity: Vector3,
		throttle: float,
		brake: float,
		steer: float
) -> Dictionary:
	return {
		"protocol": REALTIME_PROTOCOL,
		"sequence": sequence,
		"physics_tick": physics_tick,
		"position": [position.x, position.y, position.z],
		"rotation": [rotation.x, rotation.y, rotation.z, rotation.w],
		"linear_velocity": [linear_velocity.x, linear_velocity.y, linear_velocity.z],
		"angular_velocity": [angular_velocity.x, angular_velocity.y, angular_velocity.z],
		"controls": {
			"throttle": throttle,
			"brake": brake,
			"steer": steer,
		},
	}

static func validate_snapshot(snapshot: Dictionary) -> String:
	if str(snapshot.get("protocol", "")) != REALTIME_PROTOCOL:
		return "unsupported realtime protocol"
	if not _nonnegative_integer(snapshot.get("sequence")):
		return "sequence must be a nonnegative integer"
	if not _nonnegative_integer(snapshot.get("physics_tick")):
		return "physics_tick must be a nonnegative integer"
	if not _numeric_array(snapshot.get("position"), 3):
		return "position must contain three finite numbers"
	if not _numeric_array(snapshot.get("rotation"), 4):
		return "rotation must contain four finite numbers"
	if not _numeric_array(snapshot.get("linear_velocity"), 3):
		return "linear_velocity must contain three finite numbers"
	if not _numeric_array(snapshot.get("angular_velocity"), 3):
		return "angular_velocity must contain three finite numbers"
	var controls = snapshot.get("controls")
	if not controls is Dictionary:
		return "controls must be an object"
	for key in ["throttle", "steer"]:
		if not _finite_number(controls.get(key)) or absf(float(controls[key])) > 1.0:
			return "%s must be within -1..1" % key
	if not _finite_number(controls.get("brake")) or float(controls["brake"]) < 0.0 or float(controls["brake"]) > 1.0:
		return "brake must be within 0..1"
	return ""

static func make_event(event_type: String, sequence: int, racer_id: String, data: Dictionary = {}) -> Dictionary:
	return {
		"protocol": CONTROL_PROTOCOL,
		"type": event_type,
		"sequence": sequence,
		"racer_id": racer_id,
		"data": data.duplicate(true),
	}

static func validate_event(event: Dictionary) -> String:
	if str(event.get("protocol", "")) != CONTROL_PROTOCOL:
		return "unsupported control protocol"
	var event_type := str(event.get("type", ""))
	if not ALLOWED_EVENT_TYPES.has(event_type):
		return "unknown event type"
	if not _nonnegative_integer(event.get("sequence")):
		return "sequence must be a nonnegative integer"
	var racer_error := _validate_identifier("racer_id", event.get("racer_id"))
	if not racer_error.is_empty():
		return racer_error
	var data = event.get("data")
	if not data is Dictionary:
		return "event data must be an object"
	if data.size() > MAX_EVENT_DATA_KEYS:
		return "event data has too many keys"

	match event_type:
		EVENT_RACER_READY:
			if not data.get("ready") is bool:
				return "racer_ready requires boolean ready"
		EVENT_CHECKPOINT:
			var checkpoint_error := _validate_identifier("checkpoint_id", data.get("checkpoint_id"))
			if not checkpoint_error.is_empty():
				return checkpoint_error
			if not _nonnegative_integer(data.get("lap")):
				return "checkpoint lap must be nonnegative"
		EVENT_LAP_COMPLETE:
			if not _integer_in_range(data.get("lap"), 1, MAX_LAPS):
				return "lap_complete lap is invalid"
			if not _nonnegative_integer(data.get("elapsed_ms")):
				return "lap_complete elapsed_ms must be nonnegative"
		EVENT_FINISH:
			if not _nonnegative_integer(data.get("elapsed_ms")):
				return "finish elapsed_ms must be nonnegative"
		EVENT_CONTENT_REFERENCE:
			if str(data.get("kind", "")) not in ["car", "track"]:
				return "content_reference kind must be car or track"
			var reference_error := _validate_capability_reference("reference", data.get("reference"))
			if not reference_error.is_empty():
				return reference_error
		EVENT_REALTIME_LANE:
			var lane_error := _validate_capability_reference("reference", data.get("reference"))
			if not lane_error.is_empty():
				return lane_error
			if str(data.get("transport", "")).is_empty():
				return "realtime_lane requires transport"
	return ""

static func _validate_capability_reference(label: String, value: Variant) -> String:
	if not value is String:
		return "%s must be a string" % label
	var reference := str(value)
	if reference.is_empty() or reference.length() > MAX_CAPABILITY_REFERENCE_BYTES:
		return "%s has invalid length" % label
	if not reference.begins_with("ocapn://"):
		return "%s must be an OCapN sturdyref" % label
	return ""

static func _validate_identifier(label: String, value: Variant) -> String:
	if not value is String:
		return "%s must be a string" % label
	var identifier := str(value)
	if identifier.is_empty() or identifier.length() > MAX_RACER_ID_BYTES:
		return "%s has invalid length" % label
	return ""

static func _numeric_array(value: Variant, expected_size: int) -> bool:
	if not value is Array or value.size() != expected_size:
		return false
	for component in value:
		if not _finite_number(component):
			return false
	return true

static func _finite_number(value: Variant) -> bool:
	return (value is int) or (value is float and is_finite(value))

static func _nonnegative_integer(value: Variant) -> bool:
	return value is int and int(value) >= 0

static func _integer_in_range(value: Variant, minimum: int, maximum: int) -> bool:
	return value is int and int(value) >= minimum and int(value) <= maximum
