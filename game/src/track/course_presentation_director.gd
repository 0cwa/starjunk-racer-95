class_name CoursePresentationDirector
extends Node

signal cue_fired(cue: Dictionary)
signal palette_requested(payload: Dictionary)
signal lighting_requested(payload: Dictionary)
signal particles_requested(payload: Dictionary)
signal scenery_requested(payload: Dictionary)
signal post_process_requested(payload: Dictionary)
signal beat_requested(payload: Dictionary)

const PERSISTENT_KINDS := [
	"palette",
	"lighting",
	"scenery",
	"post_process",
]

var _timeline := SongCueTimeline.new()
var _cue_set: Dictionary = {}
var _persistent_state: Dictionary = {}

func configure(cue_set: Dictionary) -> String:
	var error := _timeline.configure(cue_set)
	if not error.is_empty():
		return error
	_cue_set = cue_set.duplicate(true)
	_reset_persistent_state()
	_apply_initial_state()
	return ""

func advance_to(time_ms: int) -> Array[Dictionary]:
	var due := _timeline.advance_to(time_ms)
	for cue in due:
		_apply_cue(cue, true)
	return due

func seek_to(time_ms: int) -> String:
	if _cue_set.is_empty():
		return "presentation director is not configured"
	var error := _timeline.configure(_cue_set)
	if not error.is_empty():
		return error
	_reset_persistent_state()
	_apply_initial_state()
	var due := _timeline.advance_to(time_ms)
	for cue in due:
		_apply_cue(cue, false)
	return ""

func current_time_ms() -> int:
	return _timeline.current_time_ms()

func duration_ms() -> int:
	return _timeline.duration_ms()

func current_state(kind: String) -> Dictionary:
	if not _persistent_state.has(kind):
		return {}
	return _persistent_state[kind].duplicate(true)

func snapshot_state() -> Dictionary:
	return _persistent_state.duplicate(true)

func emit_current_state() -> void:
	for kind in PERSISTENT_KINDS:
		var payload: Dictionary = _persistent_state[kind]
		if not payload.is_empty():
			_emit_kind(kind, payload.duplicate(true))

func _reset_persistent_state() -> void:
	_persistent_state.clear()
	for kind in PERSISTENT_KINDS:
		_persistent_state[kind] = {}

func _apply_initial_state() -> void:
	var initial: Array[Dictionary] = []
	for cue in _cue_set.get("cues", []):
		if int(cue.get("time_ms", -1)) == 0:
			initial.append(cue)
	initial.sort_custom(_cue_before)
	for cue in initial:
		_apply_cue(cue, false)

func _apply_cue(cue: Dictionary, emit_signals: bool) -> void:
	var kind := str(cue["kind"])
	var payload: Dictionary = {}
	if cue.get("payload") is Dictionary:
		payload = cue["payload"].duplicate(true)

	if PERSISTENT_KINDS.has(kind):
		var state: Dictionary = _persistent_state[kind]
		state.merge(payload, true)
		_persistent_state[kind] = state

	if emit_signals:
		cue_fired.emit(cue.duplicate(true))
		_emit_kind(kind, payload)

func _emit_kind(kind: String, payload: Dictionary) -> void:
	match kind:
		"palette":
			palette_requested.emit(payload)
		"lighting":
			lighting_requested.emit(payload)
		"particles":
			particles_requested.emit(payload)
		"scenery":
			scenery_requested.emit(payload)
		"post_process":
			post_process_requested.emit(payload)
		"beat":
			beat_requested.emit(payload)

static func _cue_before(a: Dictionary, b: Dictionary) -> bool:
	var time_a := int(a["time_ms"])
	var time_b := int(b["time_ms"])
	if time_a == time_b:
		return str(a["id"]) < str(b["id"])
	return time_a < time_b
