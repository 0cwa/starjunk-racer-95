extends Node

var _failures := PackedStringArray()
var _events: Array[String] = []

func _ready() -> void:
	var director := CoursePresentationDirector.new()
	add_child(director)
	director.palette_requested.connect(func(_payload): _events.append("palette"))
	director.lighting_requested.connect(func(_payload): _events.append("lighting"))
	director.particles_requested.connect(func(_payload): _events.append("particles"))
	director.scenery_requested.connect(func(_payload): _events.append("scenery"))
	director.post_process_requested.connect(func(_payload): _events.append("post_process"))
	director.beat_requested.connect(func(_payload): _events.append("beat"))

	var cue_set := {
		"format": "starjunk95/cue-set/1",
		"duration_ms": 10000,
		"cues": [
			{"id": "initial-light", "time_ms": 0, "kind": "lighting", "payload": {"energy": 0.8}},
			{"id": "initial-palette", "time_ms": 0, "kind": "palette", "payload": {"name": "violet"}},
			{"id": "light-rise", "time_ms": 1000, "kind": "lighting", "payload": {"energy": 1.5}},
			{"id": "spark-burst", "time_ms": 1000, "kind": "particles", "payload": {"burst": 24}},
			{"id": "light-color", "time_ms": 1500, "kind": "lighting", "payload": {"color": "#ff44dd"}},
			{"id": "beat-a", "time_ms": 2000, "kind": "beat", "payload": {"strength": 0.9}},
			{"id": "world-shift", "time_ms": 2500, "kind": "scenery", "payload": {"phase": 2}},
		]
	}

	_check(director.configure(cue_set).is_empty(), "director should configure valid cue set")
	_check(str(director.current_state("palette").get("name", "")) == "violet", "time-zero palette should seed persistent state")
	_check(is_equal_approx(float(director.current_state("lighting").get("energy", 0.0)), 0.8), "time-zero lighting should seed persistent state")
	_check(_events.is_empty(), "configuration should reconstruct initial state silently")

	var first := director.advance_to(1000)
	_check(first.size() == 2, "two cues should fire at 1000ms")
	_check(_events == ["lighting", "particles"], "equal-time cues should emit in deterministic id order")
	_check(is_equal_approx(float(director.current_state("lighting")["energy"]), 1.5), "lighting cue should update persistent state")
	_check(director.current_state("particles").is_empty(), "transient particles should not become persistent state")

	_events.clear()
	director.advance_to(1500)
	var lighting := director.current_state("lighting")
	_check(is_equal_approx(float(lighting["energy"]), 1.5), "partial lighting cue should preserve previous energy")
	_check(str(lighting["color"]) == "#ff44dd", "partial lighting cue should merge color")
	_check(_events == ["lighting"], "only lighting should emit at 1500ms")

	_events.clear()
	_check(director.seek_to(1250).is_empty(), "seeking should reconstruct state")
	_check(_events.is_empty(), "seeking should not replay transient/render signals")
	lighting = director.current_state("lighting")
	_check(is_equal_approx(float(lighting["energy"]), 1.5), "seek reconstruction should include crossed persistent cue")
	_check(not lighting.has("color"), "seek before color cue should not include future state")
	_check(str(director.current_state("palette")["name"]) == "violet", "seek reconstruction should preserve time-zero palette")

	director.emit_current_state()
	_check(_events == ["palette", "lighting"], "current persistent state should replay through render signals in stable order")

	_events.clear()
	director.advance_to(2600)
	_check(_events == ["lighting", "beat", "scenery"], "forward playback after seek should emit crossed cues")
	_check(int(director.current_state("scenery")["phase"]) == 2, "scenery should persist")
	_check(director.current_state("beat").is_empty(), "beats should remain transient")
	_finish()

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("Course presentation director tests passed")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("TEST FAILURE: " + failure)
	get_tree().quit(1)
