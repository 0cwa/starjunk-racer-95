class_name CourseVisualAdapter
extends Node

const MAX_LIGHT_ENERGY := 16.0
const MAX_GLOW_INTENSITY := 8.0
const MAX_SCENERY_EMISSION := 8.0
const MAX_BEAT_DURATION_MS := 1000.0
const MAX_PARTICLE_AMOUNT_RATIO := 1.0

var _director: CoursePresentationDirector
var _environment: Environment
var _key_light: Light3D
var _particles: GPUParticles3D
var _scenery_materials: Array[StandardMaterial3D] = []

var _base_light_energy := 1.0
var _beat_strength := 0.0
var _beat_duration_seconds := 0.0
var _beat_remaining_seconds := 0.0

func connect_director(director: CoursePresentationDirector) -> void:
	if _director == director:
		return
	_disconnect_director()
	_director = director
	if _director == null:
		return
	_director.palette_requested.connect(_on_palette_requested)
	_director.lighting_requested.connect(_on_lighting_requested)
	_director.particles_requested.connect(_on_particles_requested)
	_director.scenery_requested.connect(_on_scenery_requested)
	_director.post_process_requested.connect(_on_post_process_requested)
	_director.beat_requested.connect(_on_beat_requested)

func set_targets(
		environment: Environment,
		key_light: Light3D,
		particles: GPUParticles3D = null,
		scenery_materials: Array[StandardMaterial3D] = []
) -> void:
	_environment = environment
	_key_light = key_light
	_particles = particles
	_scenery_materials = scenery_materials.duplicate()
	if _key_light != null:
		_base_light_energy = _key_light.light_energy
		_apply_light_energy()

func clear_transients() -> void:
	_beat_strength = 0.0
	_beat_duration_seconds = 0.0
	_beat_remaining_seconds = 0.0
	_apply_light_energy()

func _process(delta: float) -> void:
	if _beat_remaining_seconds <= 0.0:
		return
	_beat_remaining_seconds = maxf(_beat_remaining_seconds - maxf(delta, 0.0), 0.0)
	_apply_light_energy()

func _disconnect_director() -> void:
	if _director == null:
		return
	var bindings := [
		[_director.palette_requested, _on_palette_requested],
		[_director.lighting_requested, _on_lighting_requested],
		[_director.particles_requested, _on_particles_requested],
		[_director.scenery_requested, _on_scenery_requested],
		[_director.post_process_requested, _on_post_process_requested],
		[_director.beat_requested, _on_beat_requested],
	]
	for binding in bindings:
		var signal_value: Signal = binding[0]
		var callable_value: Callable = binding[1]
		if signal_value.is_connected(callable_value):
			signal_value.disconnect(callable_value)
	_director = null

func _on_palette_requested(payload: Dictionary) -> void:
	if _environment == null:
		return
	if payload.has("background_color"):
		_environment.background_color = _color_value(
			payload["background_color"],
			_environment.background_color
		)
	if payload.has("ambient_color"):
		_environment.ambient_light_color = _color_value(
			payload["ambient_color"],
			_environment.ambient_light_color
		)
	if payload.has("ambient_energy"):
		_environment.ambient_light_energy = clampf(
			float(payload["ambient_energy"]),
			0.0,
			MAX_LIGHT_ENERGY
		)

func _on_lighting_requested(payload: Dictionary) -> void:
	if _key_light == null:
		return
	if payload.has("energy"):
		_base_light_energy = clampf(float(payload["energy"]), 0.0, MAX_LIGHT_ENERGY)
	if payload.has("color"):
		_key_light.light_color = _color_value(payload["color"], _key_light.light_color)
	_apply_light_energy()

func _on_particles_requested(payload: Dictionary) -> void:
	if _particles == null:
		return
	if payload.has("intensity"):
		_particles.amount_ratio = clampf(
			float(payload["intensity"]),
			0.0,
			MAX_PARTICLE_AMOUNT_RATIO
		)
	if bool(payload.get("restart", true)):
		_particles.restart()

func _on_scenery_requested(payload: Dictionary) -> void:
	if not payload.has("emission_energy"):
		return
	var energy := clampf(
		float(payload["emission_energy"]),
		0.0,
		MAX_SCENERY_EMISSION
	)
	for material in _scenery_materials:
		if material != null:
			material.emission_energy_multiplier = energy

func _on_post_process_requested(payload: Dictionary) -> void:
	if _environment == null:
		return
	if payload.has("glow_intensity"):
		_environment.glow_intensity = clampf(
			float(payload["glow_intensity"]),
			0.0,
			MAX_GLOW_INTENSITY
		)

func _on_beat_requested(payload: Dictionary) -> void:
	if _key_light == null:
		return
	_beat_strength = clampf(float(payload.get("strength", 0.0)), 0.0, 1.0)
	var duration_ms := clampf(
		float(payload.get("duration_ms", 120.0)),
		16.0,
		MAX_BEAT_DURATION_MS
	)
	_beat_duration_seconds = duration_ms / 1000.0
	_beat_remaining_seconds = _beat_duration_seconds
	_apply_light_energy()

func _apply_light_energy() -> void:
	if _key_light == null:
		return
	var pulse := 0.0
	if _beat_remaining_seconds > 0.0 and _beat_duration_seconds > 0.0:
		pulse = _beat_strength * (_beat_remaining_seconds / _beat_duration_seconds)
	_key_light.light_energy = clampf(
		_base_light_energy * (1.0 + pulse * 0.8),
		0.0,
		MAX_LIGHT_ENERGY
	)

func _color_value(value: Variant, fallback: Color) -> Color:
	if value is String:
		return Color.from_string(value, fallback)
	if value is Array and value.size() in [3, 4]:
		var components: Array = value
		var alpha := float(components[3]) if components.size() == 4 else 1.0
		return Color(
			clampf(float(components[0]), 0.0, 1.0),
			clampf(float(components[1]), 0.0, 1.0),
			clampf(float(components[2]), 0.0, 1.0),
			clampf(alpha, 0.0, 1.0)
		)
	return fallback
