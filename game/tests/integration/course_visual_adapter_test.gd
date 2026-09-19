extends Node

var _failures := PackedStringArray()
var _race: PrototypeRace

func _ready() -> void:
	var packed: PackedScene = load("res://src/race/prototype_race.tscn")
	_race = packed.instantiate()
	_race.input_enabled = false
	add_child(_race)
	await get_tree().process_frame

	var environment_node := _race.find_child("WorldEnvironment", true, false) as WorldEnvironment
	var key_light := _race.find_child("KeyLight", true, false) as DirectionalLight3D
	var sparkles := _race.find_child("TrackSparkles", true, false) as GPUParticles3D
	var rails := _race.find_child("NeonRails", true, false) as MultiMeshInstance3D
	_check(environment_node != null and environment_node.environment != null, "prototype should expose presentation environment")
	_check(key_light != null, "prototype should expose presentation key light")
	_check(sparkles != null, "prototype should expose presentation particle target")
	_check(rails != null and rails.multimesh != null and rails.multimesh.mesh != null, "prototype should expose presentation scenery material")
	if not _failures.is_empty():
		_finish()
		return

	var cue_set := {
		"format": "starjunk95/cue-set/1",
		"duration_ms": 5000,
		"cues": [
			{"id": "palette-0", "time_ms": 0, "kind": "palette", "payload": {
				"background_color": "#102040",
				"ambient_color": "#8040a0",
				"ambient_energy": 1.7
			}},
			{"id": "light-0", "time_ms": 0, "kind": "lighting", "payload": {
				"energy": 2.0,
				"color": "#ffeecc"
			}},
			{"id": "post-0", "time_ms": 0, "kind": "post_process", "payload": {
				"glow_intensity": 1.9
			}},
			{"id": "particles-1", "time_ms": 1000, "kind": "particles", "payload": {
				"intensity": 0.25,
				"restart": false
			}},
			{"id": "scenery-1", "time_ms": 1000, "kind": "scenery", "payload": {
				"emission_energy": 4.0
			}},
			{"id": "beat-1", "time_ms": 1200, "kind": "beat", "payload": {
				"strength": 1.0,
				"duration_ms": 200
			}},
		]
	}

	var configure_error := _race.configure_presentation(cue_set)
	_check(configure_error.is_empty(), "presentation cue set should configure: %s" % configure_error)
	var environment := environment_node.environment
	_check(environment.background_color.is_equal_approx(Color.from_string("#102040", Color.BLACK)), "palette should update background color")
	_check(environment.ambient_light_color.is_equal_approx(Color.from_string("#8040a0", Color.BLACK)), "palette should update ambient color")
	_check(absf(environment.ambient_light_energy - 1.7) < 0.001, "palette should update ambient energy")
	_check(absf(environment.glow_intensity - 1.9) < 0.001, "post-process cue should update glow intensity")
	_check(absf(key_light.light_energy - 2.0) < 0.001, "lighting cue should update key-light energy")
	_check(key_light.light_color.is_equal_approx(Color.from_string("#ffeecc", Color.BLACK)), "lighting cue should update key-light color")

	_race.advance_presentation_to(1000)
	_check(absf(sparkles.amount_ratio - 0.25) < 0.001, "particle cue should update bounded intensity")
	var rail_material := rails.multimesh.mesh.material as StandardMaterial3D
	_check(rail_material != null and absf(rail_material.emission_energy_multiplier - 4.0) < 0.001, "scenery cue should update allowlisted emission material")

	_race.advance_presentation_to(1200)
	_check(key_light.light_energy > 2.0, "beat cue should create a temporary render-only light pulse")
	_race.presentation_adapter._process(0.25)
	_check(absf(key_light.light_energy - 2.0) < 0.001, "beat pulse should decay back to persistent light energy")

	var seek_error := _race.seek_presentation_to(500)
	_check(seek_error.is_empty(), "presentation seek should succeed")
	_check(absf(key_light.light_energy - 2.0) < 0.001, "seek should clear transient beat pulse")
	_check(absf(sparkles.amount_ratio - 1.0) < 0.001, "seek should clear transient particle target back to its baseline")
	_check(absf(rail_material.emission_energy_multiplier - 2.6) < 0.001, "seek before scenery cue should restore baseline scenery state")
	_finish()

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("Course visual adapter integration test passed")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("TEST FAILURE: " + failure)
	get_tree().quit(1)
