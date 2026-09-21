extends Node

const RESULT_PREFIX := "STARJUNK_PLAYABLE_JSON:"

var _race: PrototypeRace
var _frames := 0

func _ready() -> void:
	var packed := load("res://src/race/prototype_race.tscn") as PackedScene
	if packed == null:
		push_error("Unable to load PrototypeRace scene for browser playable smoke")
		get_tree().quit(1)
		return
	_race = packed.instantiate() as PrototypeRace
	if _race == null:
		push_error("Unable to instantiate PrototypeRace for browser playable smoke")
		get_tree().quit(1)
		return
	_race.input_enabled = false
	add_child(_race)

func _process(_delta: float) -> void:
	_frames += 1
	if _frames != 30:
		return

	var vehicle_ready := _race != null and _race.vehicle != null
	var result := {
		"profile": "playable",
		"renderer": RenderingServer.get_current_rendering_method(),
		"rendering_driver": RenderingServer.get_current_rendering_driver_name(),
		"frames": _frames,
		"vehicle_ready": vehicle_ready,
		"checkpoint_count": _race.checkpoint_count() if _race != null else 0,
		"lap": _race.current_lap() if _race != null else -1,
		"engine_version": Engine.get_version_info().get("string", "unknown"),
	}

	var payload := JSON.stringify(result)
	print(RESULT_PREFIX + payload)
	if OS.has_feature("web"):
		JavaScriptBridge.eval(
			"window.__STARJUNK_PLAYABLE_RESULT__ = %s;" % payload
		)
	else:
		get_tree().quit(0 if vehicle_ready else 1)
