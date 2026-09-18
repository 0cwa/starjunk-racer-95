class_name SongCueTimeline
extends RefCounted

const FORMAT := "starjunk95/cue-set/1"
const MAX_CUES := 4096
const MAX_DURATION_MS := 6 * 60 * 60 * 1000
const MAX_PAYLOAD_KEYS := 32
const ALLOWED_KINDS := [
	"palette",
	"lighting",
	"particles",
	"scenery",
	"post_process",
	"beat",
]

var _cues: Array[Dictionary] = []
var _duration_ms: int = 0
var _next_index: int = 0
var _time_ms: int = 0

func configure(cue_set: Dictionary) -> String:
	var error := validate(cue_set)
	if not error.is_empty():
		return error
	_duration_ms = int(cue_set["duration_ms"])
	_cues.clear()
	for cue in cue_set["cues"]:
		_cues.append(cue.duplicate(true))
	_cues.sort_custom(_cue_before)
	seek_to(0)
	return ""

func duration_ms() -> int:
	return _duration_ms

func current_time_ms() -> int:
	return _time_ms

func cue_count() -> int:
	return _cues.size()

func seek_to(time_ms: int) -> void:
	_time_ms = clampi(time_ms, 0, _duration_ms)
	_next_index = 0
	while _next_index < _cues.size() and int(_cues[_next_index]["time_ms"]) <= _time_ms:
		_next_index += 1

func advance_to(time_ms: int) -> Array[Dictionary]:
	var target := clampi(time_ms, 0, _duration_ms)
	if target < _time_ms:
		seek_to(target)
		return []
	var due: Array[Dictionary] = []
	while _next_index < _cues.size():
		var cue := _cues[_next_index]
		if int(cue["time_ms"]) > target:
			break
		due.append(cue.duplicate(true))
		_next_index += 1
	_time_ms = target
	return due

static func validate(cue_set: Dictionary) -> String:
	if str(cue_set.get("format", "")) != FORMAT:
		return "unsupported cue-set format"
	if not cue_set.get("duration_ms") is int:
		return "duration_ms must be an integer"
	var duration := int(cue_set["duration_ms"])
	if duration <= 0 or duration > MAX_DURATION_MS:
		return "duration_ms is outside the supported range"
	if cue_set.has("bpm"):
		var bpm = cue_set["bpm"]
		if not (bpm is int or bpm is float) or not is_finite(float(bpm)) or float(bpm) <= 0.0 or float(bpm) > 1000.0:
			return "bpm must be finite and within 0..1000"
	if not cue_set.get("cues") is Array:
		return "cues must be an array"
	var cues: Array = cue_set["cues"]
	if cues.size() > MAX_CUES:
		return "cue set has too many cues"
	var ids := {}
	for cue in cues:
		if not cue is Dictionary:
			return "cue must be an object"
		for key in ["id", "time_ms", "kind"]:
			if not cue.has(key):
				return "cue missing %s" % key
		var cue_id := str(cue["id"])
		if cue_id.is_empty() or cue_id.length() > 96:
			return "cue id has invalid length"
		if ids.has(cue_id):
			return "cue ids must be unique"
		ids[cue_id] = true
		if not cue["time_ms"] is int:
			return "cue time_ms must be an integer"
		var cue_time := int(cue["time_ms"])
		if cue_time < 0 or cue_time > duration:
			return "cue time_ms is outside track duration"
		if not ALLOWED_KINDS.has(str(cue["kind"])):
			return "unsupported cue kind"
		if cue.has("payload"):
			if not cue["payload"] is Dictionary:
				return "cue payload must be an object"
			if cue["payload"].size() > MAX_PAYLOAD_KEYS:
				return "cue payload has too many keys"
			var payload_error := _validate_json_value(cue["payload"], 0)
			if not payload_error.is_empty():
				return payload_error
	return ""

static func _validate_json_value(value: Variant, depth: int) -> String:
	if depth > 8:
		return "cue payload nesting is too deep"
	if value == null or value is bool or value is int or value is String:
		return ""
	if value is float:
		return "" if is_finite(value) else "cue payload contains non-finite number"
	if value is Array:
		if value.size() > 256:
			return "cue payload array is too large"
		for item in value:
			var error := _validate_json_value(item, depth + 1)
			if not error.is_empty():
				return error
		return ""
	if value is Dictionary:
		if value.size() > MAX_PAYLOAD_KEYS:
			return "cue payload object has too many keys"
		for key in value.keys():
			if not key is String:
				return "cue payload object keys must be strings"
			var error := _validate_json_value(value[key], depth + 1)
			if not error.is_empty():
				return error
		return ""
	return "cue payload contains unsupported value type"

static func _cue_before(a: Dictionary, b: Dictionary) -> bool:
	var time_a := int(a["time_ms"])
	var time_b := int(b["time_ms"])
	if time_a == time_b:
		return str(a["id"]) < str(b["id"])
	return time_a < time_b
