extends Node

var _failures := PackedStringArray()

func _ready() -> void:
	var cue_set := {
		"format": "starjunk95/cue-set/1",
		"duration_ms": 120000,
		"bpm": 128.0,
		"cues": [
			{"id": "c-late", "time_ms": 3000, "kind": "scenery", "payload": {"phase": 2}},
			{"id": "b-same", "time_ms": 1000, "kind": "particles", "payload": {"burst": 12}},
			{"id": "a-same", "time_ms": 1000, "kind": "lighting", "payload": {"energy": 1.4}},
			{"id": "start", "time_ms": 0, "kind": "palette", "payload": {"name": "violet"}},
		],
	}
	_check(SongCueTimeline.validate(cue_set).is_empty(), "valid cue set should pass")
	var timeline := SongCueTimeline.new()
	_check(timeline.configure(cue_set).is_empty(), "valid cue set should configure")
	_check(timeline.cue_count() == 4, "all cues should be retained")

	# time 0 is treated as initial state and is not replayed after configuration.
	var due := timeline.advance_to(1000)
	_check(due.size() == 2, "two 1000ms cues should fire")
	if due.size() == 2:
		_check(str(due[0]["id"]) == "a-same" and str(due[1]["id"]) == "b-same", "equal-time cues should be deterministically ordered by id")

	_check(timeline.advance_to(2500).is_empty(), "no cue should fire in empty interval")
	var late := timeline.advance_to(3000)
	_check(late.size() == 1 and str(late[0]["id"]) == "c-late", "late cue should fire once")
	_check(timeline.advance_to(4000).is_empty(), "already fired cue must not repeat")

	timeline.seek_to(500)
	var after_seek := timeline.advance_to(1000)
	_check(after_seek.size() == 2, "seeking backward should allow future cues to fire again")

	var bad_kind := cue_set.duplicate(true)
	bad_kind["cues"][0]["kind"] = "change_vehicle_physics"
	_check(not SongCueTimeline.validate(bad_kind).is_empty(), "physics-affecting arbitrary cue kind must fail closed")

	var duplicate := cue_set.duplicate(true)
	duplicate["cues"][1]["id"] = "a-same"
	_check(not SongCueTimeline.validate(duplicate).is_empty(), "duplicate cue ids must fail")

	var nonfinite := cue_set.duplicate(true)
	nonfinite["cues"][0]["payload"] = {"energy": NAN}
	_check(not SongCueTimeline.validate(nonfinite).is_empty(), "non-finite payload numbers must fail")
	_finish()

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("Song cue timeline tests passed")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("TEST FAILURE: " + failure)
	get_tree().quit(1)
