extends Node3D

const SCENARIO := "renderer_torture"
const SCENARIO_VERSION := 3
const DEFAULT_WARMUP := 180
const DEFAULT_FRAMES := 600

var _camera: Camera3D
var _car_proxy: MeshInstance3D
var _benchmarking := false
var _warmup_frames := DEFAULT_WARMUP
var _sample_frames := DEFAULT_FRAMES
var _output_path := ""
var _profile := "default"
var _frame_times_ms: Array[float] = []
var _process_times_ms: Array[float] = []
var _physics_times_ms: Array[float] = []
var _draw_calls: Array[float] = []
var _frame_index := 0
var _last_tick_usec := 0
var _scene_time := 0.0
var _pipeline_compilations_start := 0.0
var _instance_count := 512
var _light_count := 8
var _track_segment_count := 48
var _spark_particle_count := 4096
var _trail_particle_count := 96

func _ready() -> void:
	_configure_benchmark()
	_build_scene()
	_last_tick_usec = Time.get_ticks_usec()

func _process(delta: float) -> void:
	_scene_time += delta
	_animate_scene(delta)
	if not _benchmarking:
		return
	var now := Time.get_ticks_usec()
	var frame_ms := float(now - _last_tick_usec) / 1000.0
	_last_tick_usec = now
	_frame_index += 1
	if _frame_index <= _warmup_frames:
		if _frame_index == _warmup_frames:
			_pipeline_compilations_start = _pipeline_compilation_count()
		return
	_frame_times_ms.append(frame_ms)
	_process_times_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_physics_times_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	_draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	if _frame_times_ms.size() >= _sample_frames:
		_finish_benchmark()

func _configure_benchmark() -> void:
	var user_args := OS.get_cmdline_user_args()
	_benchmarking = OS.has_feature("starjunk_renderer_benchmark") or user_args.has("--benchmark")
	if OS.has_feature("starjunk_renderer_smoke"):
		_profile = "browser_smoke"
		_warmup_frames = 12
		_sample_frames = 24
		_instance_count = 96
		_light_count = 4
		_track_segment_count = 24
		_spark_particle_count = 512
		_trail_particle_count = 24
	for arg in user_args:
		if arg.begins_with("--warmup="):
			_warmup_frames = max(1, int(arg.trim_prefix("--warmup=")))
		elif arg.begins_with("--frames="):
			_sample_frames = max(1, int(arg.trim_prefix("--frames=")))
		elif arg.begins_with("--output="):
			_output_path = arg.trim_prefix("--output=")
	if _benchmarking and not OS.has_feature("headless"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

func _build_scene() -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.012, 0.006, 0.04)
	environment.glow_enabled = true
	environment.glow_intensity = 1.15
	environment_node.environment = environment
	add_child(environment_node)

	_camera = Camera3D.new()
	_camera.position = Vector3(0.0, 8.0, 18.0)
	_camera.fov = 68.0
	add_child(_camera)
	_camera.look_at(Vector3.ZERO)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -25.0, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)

	for i in range(_light_count):
		var light := OmniLight3D.new()
		var angle := TAU * float(i) / float(_light_count)
		light.position = Vector3(cos(angle) * 11.0, 2.4, sin(angle) * 11.0)
		light.omni_range = 9.0
		light.light_energy = 3.0
		light.light_color = Color.from_hsv(float(i) / 8.0, 0.85, 1.0)
		light.shadow_enabled = (i % 2) == 0
		add_child(light)

	_build_instanced_field()
	_build_track()
	_build_particles()
	_build_trail_particles()
	_build_car_proxy()

func _build_instanced_field() -> void:
	var multimesh_instance := MultiMeshInstance3D.new()
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.instance_count = _instance_count
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.35, 0.35, 0.35)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.12, 0.22, 0.95)
	material.emission_enabled = true
	material.emission = Color(0.1, 0.35, 2.5)
	material.emission_energy_multiplier = 2.0
	mesh.material = material
	multimesh.mesh = mesh
	for i in range(multimesh.instance_count):
		var ring := 13.0 + float(i % 17) * 0.55
		var angle := TAU * float(i) / float(multimesh.instance_count)
		var height := 1.0 + float((i * 7) % 19) * 0.34
		multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(cos(angle) * ring, height, sin(angle) * ring)))
	multimesh_instance.multimesh = multimesh
	add_child(multimesh_instance)

func _build_track() -> void:
	for i in range(_track_segment_count):
		var segment := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(2.0, 0.18, 2.0)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.04, 0.04, 0.08)
		material.metallic = 0.55
		material.roughness = 0.26
		material.emission_enabled = true
		material.emission = Color.from_hsv(float(i % 12) / 12.0, 0.92, 0.65)
		material.emission_energy_multiplier = 1.4
		mesh.material = material
		segment.mesh = mesh
		var angle := TAU * float(i) / float(_track_segment_count)
		segment.position = Vector3(cos(angle) * 8.5, 0.0, sin(angle) * 8.5)
		segment.rotation.y = -angle
		add_child(segment)

func _build_particles() -> void:
	var particles := GPUParticles3D.new()
	particles.amount = _spark_particle_count
	particles.lifetime = 2.8
	particles.visibility_aabb = AABB(Vector3(-24, -6, -24), Vector3(48, 20, 48))
	particles.use_fixed_seed = true
	particles.seed = 95
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(14.0, 3.5, 14.0)
	process.initial_velocity_min = 0.5
	process.initial_velocity_max = 2.5
	process.gravity = Vector3(0.0, 0.5, 0.0)
	process.scale_min = 0.015
	process.scale_max = 0.07
	particles.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.09)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_color = Color(0.85, 0.95, 1.0, 0.9)
	material.emission_enabled = true
	material.emission = Color(1.7, 0.7, 3.0)
	material.emission_energy_multiplier = 3.0
	quad.material = material
	particles.draw_pass_1 = quad
	add_child(particles)

func _build_trail_particles() -> void:
	var particles := GPUParticles3D.new()
	particles.amount = _trail_particle_count
	particles.lifetime = 2.2
	particles.trail_enabled = true
	particles.trail_lifetime = 0.75
	particles.visibility_aabb = AABB(Vector3(-20, -5, -20), Vector3(40, 16, 40))
	particles.use_fixed_seed = true
	particles.seed = 1995
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 6.0
	process.direction = Vector3(1.0, 0.15, 0.0)
	process.spread = 180.0
	process.initial_velocity_min = 2.0
	process.initial_velocity_max = 5.0
	process.gravity = Vector3.ZERO
	particles.process_material = process
	var ribbon := RibbonTrailMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.use_particle_trails = true
	material.albedo_color = Color(0.95, 0.25, 1.0, 0.7)
	material.emission_enabled = true
	material.emission = Color(2.2, 0.2, 3.0)
	material.emission_energy_multiplier = 2.2
	ribbon.material = material
	particles.draw_pass_1 = ribbon
	add_child(particles)

func _build_car_proxy() -> void:
	_car_proxy = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.6, 0.45, 3.1)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.75, 0.08, 0.95)
	material.metallic = 0.8
	material.roughness = 0.2
	material.emission_enabled = true
	material.emission = Color(0.45, 0.02, 0.9)
	material.emission_energy_multiplier = 1.2
	mesh.material = material
	_car_proxy.mesh = mesh
	_car_proxy.position = Vector3(0.0, 0.55, -8.5)
	add_child(_car_proxy)

func _animate_scene(_delta: float) -> void:
	var t := _scene_time
	if _camera:
		_camera.position = Vector3(cos(t * 0.13) * 18.0, 7.0 + sin(t * 0.2), sin(t * 0.13) * 18.0)
		_camera.look_at(Vector3(0.0, 1.3, 0.0))
	if _car_proxy:
		var angle := t * 0.72
		_car_proxy.position = Vector3(cos(angle) * 8.5, 0.55, sin(angle) * 8.5)
		_car_proxy.rotation.y = -angle + PI * 0.5

func _finish_benchmark() -> void:
	_benchmarking = false
	_frame_times_ms.sort()
	_process_times_ms.sort()
	_physics_times_ms.sort()
	_draw_calls.sort()
	var viewport_size := get_viewport().get_visible_rect().size
	var version_info := Engine.get_version_info()
	var result := {
		"schema_version": 1,
		"scenario": SCENARIO,
		"scenario_version": SCENARIO_VERSION,
		"profile": _profile,
		"renderer": RenderingServer.get_current_rendering_method(),
		"rendering_driver": RenderingServer.get_current_rendering_driver_name(),
		"runner_id": OS.get_environment("STARJUNK_RUNNER_ID"),
		"engine_version": version_info.get("string", "unknown"),
		"engine_hash": version_info.get("hash", ""),
		"viewport_width": int(viewport_size.x),
		"viewport_height": int(viewport_size.y),
		"settings_hash": _settings_hash(),
		"sample_frames": _frame_times_ms.size(),
		"frame_ms_mean": _mean(_frame_times_ms),
		"frame_ms_p50": _percentile(_frame_times_ms, 0.50),
		"frame_ms_p95": _percentile(_frame_times_ms, 0.95),
		"frame_ms_p99": _percentile(_frame_times_ms, 0.99),
		"process_ms_p95": _percentile(_process_times_ms, 0.95),
		"physics_ms_p95": _percentile(_physics_times_ms, 0.95),
		"draw_calls_p95": _percentile(_draw_calls, 0.95),
		"pipeline_compilations_during_sample": maxf(0.0, _pipeline_compilation_count() - _pipeline_compilations_start),
		"objects_last": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"primitives_last": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"video_memory_bytes": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
		"texture_memory_bytes": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),
		"buffer_memory_bytes": Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED)
	}
	var payload := JSON.stringify(result)
	print("STARJUNK_PERF_JSON:" + payload)
	if not _output_path.is_empty():
		var file := FileAccess.open(_output_path, FileAccess.WRITE)
		if file:
			file.store_string(payload + "\n")
	if OS.has_feature("web"):
		var bridge_script = load("res://tests/perf/renderer_torture/web_result_bridge.gd")
		var bridge = bridge_script.new()
		bridge.publish(result)
	if not OS.has_feature("web"):
		get_tree().quit()

func _mean(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += value
	return total / float(values.size())

func _percentile(values: Array[float], percentile: float) -> float:
	if values.is_empty():
		return 0.0
	var index := int(round((values.size() - 1) * percentile))
	return values[clamp(index, 0, values.size() - 1)]

func _pipeline_compilation_count() -> float:
	return (
		Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_CANVAS)
		+ Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_MESH)
		+ Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE)
		+ Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW)
		+ Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SPECIALIZATION)
	)

func _settings_hash() -> String:
	if _profile == "browser_smoke":
		return "rt-v3-smoke-96i-4l-512p-24t-24s-1280x720"
	return "rt-v3-full-512i-8l-4096p-96t-48s-1280x720"
