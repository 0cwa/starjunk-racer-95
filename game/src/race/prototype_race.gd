class_name PrototypeRace
extends Node3D

const TRACK_SEGMENTS := 64
const CHECKPOINTS := 8
const TRACK_RADIUS_X := 18.0
const TRACK_RADIUS_Z := 28.0
const SPAWN_ANGLE := -0.28

@export var input_enabled: bool = true
@export_range(0.0, 1.0, 0.01) var starting_realism: float = 0.35

var vehicle: RaycastVehicleController
var realism_slider: HSlider
var speed_label: Label
var lap_label: Label
var drift_label: Label
var realism_label: Label

var _camera: Camera3D
var _spawn_transform := Transform3D.IDENTITY
var _checkpoint_areas: Array[Area3D] = []
var _wheel_visuals: Array[Dictionary] = []
var _next_checkpoint := 0
var _lap := 0
var _camera_initialized := false

func _ready() -> void:
	DefaultInputBindings.ensure_defaults()
	_build_world()
	_build_track_visuals()
	_build_checkpoints()
	_build_vehicle()
	_build_camera()
	_build_hud()
	set_realism(starting_realism)

func _physics_process(_delta: float) -> void:
	if vehicle == null:
		return
	if input_enabled:
		var throttle := Input.get_action_strength("drive_throttle")
		var brake := Input.get_action_strength("drive_brake")
		var steer := (
			Input.get_action_strength("drive_steer_right")
			- Input.get_action_strength("drive_steer_left")
		)
		vehicle.set_controls(throttle, brake, steer)

		if Input.is_action_pressed("realism_decrease"):
			set_realism(vehicle.realism - 0.005)
		elif Input.is_action_pressed("realism_increase"):
			set_realism(vehicle.realism + 0.005)

	if vehicle.position.y < -6.0:
		reset_vehicle()

func _process(delta: float) -> void:
	_update_camera(delta)
	_update_wheel_visuals(delta)
	_update_hud()

func _unhandled_input(event: InputEvent) -> void:
	if input_enabled and event.is_action_pressed("race_reset"):
		reset_vehicle()

func set_realism(value: float) -> void:
	var clamped := clampf(value, 0.0, 1.0)
	starting_realism = clamped
	if vehicle != null:
		vehicle.realism = clamped
	if realism_slider != null and not is_equal_approx(realism_slider.value, clamped):
		realism_slider.set_value_no_signal(clamped)
	if realism_label != null:
		realism_label.text = "REALISM  %d%%" % int(round(clamped * 100.0))

func reset_vehicle() -> void:
	if vehicle == null:
		return
	vehicle.global_transform = _spawn_transform
	vehicle.linear_velocity = Vector3.ZERO
	vehicle.angular_velocity = Vector3.ZERO
	vehicle.set_controls(0.0, 0.0, 0.0)
	vehicle.reset_wheel_rotation_states(0.0)
	for entry in _wheel_visuals:
		var pivot: Node3D = entry["pivot"]
		pivot.rotation = Vector3.ZERO
	vehicle.sleeping = false
	_next_checkpoint = 0

func checkpoint_count() -> int:
	return _checkpoint_areas.size()

func current_lap() -> int:
	return _lap

func _build_world() -> void:
	var environment_node := WorldEnvironment.new()
	environment_node.name = "WorldEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.012, 0.006, 0.04)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.13, 0.08, 0.24)
	environment.ambient_light_energy = 1.1
	environment.glow_enabled = true
	environment.glow_intensity = 1.15
	environment_node.environment = environment
	add_child(environment_node)

	var sun := DirectionalLight3D.new()
	sun.name = "KeyLight"
	sun.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	add_child(sun)

	var floor := StaticBody3D.new()
	floor.name = "Floor"
	floor.position = Vector3(0.0, -0.5, 0.0)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(120.0, 1.0, 120.0)
	collision.shape = shape
	floor.add_child(collision)
	add_child(floor)

	var floor_mesh := MeshInstance3D.new()
	var floor_box := BoxMesh.new()
	floor_box.size = Vector3(120.0, 1.0, 120.0)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.008, 0.009, 0.018)
	floor_material.metallic = 0.18
	floor_material.roughness = 0.62
	floor_box.material = floor_material
	floor_mesh.mesh = floor_box
	floor.add_child(floor_mesh)

func _build_track_visuals() -> void:
	var road_mesh := BoxMesh.new()
	road_mesh.size = Vector3(7.0, 0.08, 4.2)
	var road_material := StandardMaterial3D.new()
	road_material.albedo_color = Color(0.055, 0.045, 0.09)
	road_material.metallic = 0.72
	road_material.roughness = 0.24
	road_material.emission_enabled = true
	road_material.emission = Color(0.08, 0.02, 0.22)
	road_material.emission_energy_multiplier = 0.8
	road_mesh.material = road_material

	var road_multimesh := MultiMesh.new()
	road_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	road_multimesh.instance_count = TRACK_SEGMENTS
	road_multimesh.mesh = road_mesh
	for index in range(TRACK_SEGMENTS):
		var angle := TAU * float(index) / float(TRACK_SEGMENTS)
		road_multimesh.set_instance_transform(index, _track_transform(angle, 0.02))
	var road_instance := MultiMeshInstance3D.new()
	road_instance.name = "Road"
	road_instance.multimesh = road_multimesh
	add_child(road_instance)

	var rail_mesh := BoxMesh.new()
	rail_mesh.size = Vector3(0.22, 0.22, 2.8)
	var rail_material := StandardMaterial3D.new()
	rail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rail_material.emission_enabled = true
	rail_material.emission = Color(0.75, 0.08, 1.8)
	rail_material.emission_energy_multiplier = 2.6
	rail_material.albedo_color = Color(0.9, 0.25, 1.0)
	rail_mesh.material = rail_material

	var rails := MultiMesh.new()
	rails.transform_format = MultiMesh.TRANSFORM_3D
	rails.instance_count = TRACK_SEGMENTS * 2
	rails.mesh = rail_mesh
	for index in range(TRACK_SEGMENTS):
		var angle := TAU * float(index) / float(TRACK_SEGMENTS)
		var outer := _ellipse_point(angle, TRACK_RADIUS_X + 4.0, TRACK_RADIUS_Z + 4.0)
		var inner := _ellipse_point(angle, TRACK_RADIUS_X - 4.0, TRACK_RADIUS_Z - 4.0)
		var tangent := _ellipse_tangent(angle, TRACK_RADIUS_X, TRACK_RADIUS_Z)
		var basis := Basis.looking_at(tangent, Vector3.UP)
		rails.set_instance_transform(index * 2, Transform3D(basis, outer + Vector3.UP * 0.22))
		rails.set_instance_transform(index * 2 + 1, Transform3D(basis, inner + Vector3.UP * 0.22))
	var rail_instance := MultiMeshInstance3D.new()
	rail_instance.name = "NeonRails"
	rail_instance.multimesh = rails
	add_child(rail_instance)

	var sparks := GPUParticles3D.new()
	sparks.name = "TrackSparkles"
	sparks.amount = 384
	sparks.lifetime = 3.5
	sparks.visibility_aabb = AABB(Vector3(-35.0, -3.0, -45.0), Vector3(70.0, 16.0, 90.0))
	sparks.use_fixed_seed = true
	sparks.seed = 95
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(24.0, 4.0, 34.0)
	process.initial_velocity_min = 0.05
	process.initial_velocity_max = 0.45
	process.gravity = Vector3(0.0, 0.12, 0.0)
	process.scale_min = 0.018
	process.scale_max = 0.055
	sparks.process_material = process
	var sparkle_mesh := QuadMesh.new()
	sparkle_mesh.size = Vector2(0.08, 0.08)
	var sparkle_material := StandardMaterial3D.new()
	sparkle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sparkle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sparkle_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sparkle_material.albedo_color = Color(0.9, 0.95, 1.0, 0.85)
	sparkle_material.emission_enabled = true
	sparkle_material.emission = Color(0.45, 1.0, 2.2)
	sparkle_material.emission_energy_multiplier = 2.2
	sparkle_mesh.material = sparkle_material
	sparks.draw_pass_1 = sparkle_mesh
	add_child(sparks)

func _build_checkpoints() -> void:
	_checkpoint_areas.clear()
	for index in range(CHECKPOINTS):
		var angle := TAU * float(index) / float(CHECKPOINTS)
		var area := Area3D.new()
		area.name = "Checkpoint%02d" % index
		area.monitoring = true
		var point := _ellipse_point(angle, TRACK_RADIUS_X, TRACK_RADIUS_Z) + Vector3.UP * 1.2
		var basis := Basis.looking_at(_ellipse_tangent(angle, TRACK_RADIUS_X, TRACK_RADIUS_Z), Vector3.UP)
		area.transform = Transform3D(basis, point)
		var shape_node := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(9.0, 3.0, 2.5)
		shape_node.shape = shape
		area.add_child(shape_node)
		area.body_entered.connect(_on_checkpoint_body_entered.bind(index))
		add_child(area)
		_checkpoint_areas.append(area)

func _build_vehicle() -> void:
	_wheel_visuals.clear()
	var profile: VehiclePerformanceProfile = load("res://src/vehicle/profiles/prototype_balanced_01.tres")
	vehicle = RaycastVehicleController.new()
	vehicle.name = "PlayerCar"
	vehicle.performance_profile = profile
	vehicle.realism = starting_realism
	vehicle.can_sleep = false

	var collision := CollisionShape3D.new()
	var chassis_shape := BoxShape3D.new()
	chassis_shape.size = Vector3(1.45, 0.42, 2.75)
	collision.shape = chassis_shape
	vehicle.add_child(collision)

	var body_visual := MeshInstance3D.new()
	body_visual.name = "BodyVisual"
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(1.55, 0.48, 2.9)
	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = Color(0.78, 0.06, 0.95)
	body_material.metallic = 0.82
	body_material.roughness = 0.18
	body_material.emission_enabled = true
	body_material.emission = Color(0.42, 0.015, 0.9)
	body_material.emission_energy_multiplier = 1.2
	body_mesh.material = body_material
	body_visual.mesh = body_mesh
	body_visual.position.y = 0.12
	vehicle.add_child(body_visual)

	var half_track := profile.track_width_m * 0.5
	var half_wheelbase := profile.wheelbase_m * 0.5
	_add_wheel(Vector3(-half_track, 0.0, -half_wheelbase), true, false)
	_add_wheel(Vector3(half_track, 0.0, -half_wheelbase), true, false)
	_add_wheel(Vector3(-half_track, 0.0, half_wheelbase), false, true)
	_add_wheel(Vector3(half_track, 0.0, half_wheelbase), false, true)

	var spawn_point := _ellipse_point(SPAWN_ANGLE, TRACK_RADIUS_X, TRACK_RADIUS_Z) + Vector3.UP * 0.78
	var spawn_forward := _ellipse_tangent(SPAWN_ANGLE, TRACK_RADIUS_X, TRACK_RADIUS_Z)
	_spawn_transform = Transform3D(Basis.looking_at(spawn_forward, Vector3.UP), spawn_point)
	vehicle.transform = _spawn_transform
	add_child(vehicle)

func _add_wheel(position: Vector3, steerable: bool, driven: bool) -> void:
	var wheel := RaycastWheel3D.new()
	wheel.position = position
	wheel.steerable = steerable
	wheel.driven = driven
	vehicle.add_child(wheel)

	var visual_pivot := Node3D.new()
	visual_pivot.name = "WheelVisualPivot%02d" % _wheel_visuals.size()
	visual_pivot.position = position + Vector3.DOWN * 0.18
	vehicle.add_child(visual_pivot)

	var wheel_visual := MeshInstance3D.new()
	var wheel_mesh := CylinderMesh.new()
	wheel_mesh.top_radius = 0.31
	wheel_mesh.bottom_radius = 0.31
	wheel_mesh.height = 0.18
	var wheel_material := StandardMaterial3D.new()
	wheel_material.albedo_color = Color(0.018, 0.018, 0.025)
	wheel_material.metallic = 0.25
	wheel_material.roughness = 0.5
	wheel_mesh.material = wheel_material
	wheel_visual.mesh = wheel_mesh
	wheel_visual.rotation_degrees.z = 90.0
	visual_pivot.add_child(wheel_visual)
	_wheel_visuals.append({"wheel": wheel, "pivot": visual_pivot})

func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "ChaseCamera"
	_camera.fov = 68.0
	_camera.current = true
	add_child(_camera)

func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "HUD"
	add_child(canvas)

	var panel := PanelContainer.new()
	panel.position = Vector2(18.0, 18.0)
	panel.custom_minimum_size = Vector2(350.0, 0.0)
	canvas.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 5)
	margin.add_child(stack)

	var title := Label.new()
	title.text = "STARJUNK RACER 95  //  PROTOTYPE"
	stack.add_child(title)

	speed_label = Label.new()
	speed_label.text = "0 km/h"
	stack.add_child(speed_label)

	lap_label = Label.new()
	lap_label.text = "LAP 1"
	stack.add_child(lap_label)

	drift_label = Label.new()
	drift_label.text = "SLIP 0.0°"
	stack.add_child(drift_label)

	realism_label = Label.new()
	stack.add_child(realism_label)

	realism_slider = HSlider.new()
	realism_slider.name = "RealismSlider"
	realism_slider.min_value = 0.0
	realism_slider.max_value = 1.0
	realism_slider.step = 0.01
	realism_slider.value = starting_realism
	realism_slider.custom_minimum_size = Vector2(320.0, 24.0)
	realism_slider.value_changed.connect(set_realism)
	stack.add_child(realism_slider)

	var controls := Label.new()
	controls.text = "W/RT throttle   S/LT brake   A/D or stick steer\nR reset   [ / ] realism"
	stack.add_child(controls)

func _update_camera(delta: float) -> void:
	if vehicle == null or _camera == null:
		return
	var basis := vehicle.global_transform.basis.orthonormalized()
	var desired := vehicle.global_position + basis.z * 7.5 + Vector3.UP * 3.2
	if not _camera_initialized:
		_camera.global_position = desired
		_camera_initialized = true
	else:
		var blend := 1.0 - exp(-7.0 * maxf(delta, 0.0))
		_camera.global_position = _camera.global_position.lerp(desired, blend)
	_camera.look_at(vehicle.global_position + Vector3.UP * 0.7)

func _update_wheel_visuals(delta: float) -> void:
	for entry in _wheel_visuals:
		var wheel: RaycastWheel3D = entry["wheel"]
		var pivot: Node3D = entry["pivot"]
		pivot.rotation.x = wrapf(
			pivot.rotation.x + wheel.wheel_angular_speed_rad_s * delta,
			-PI,
			PI
		)

func _update_hud() -> void:
	if vehicle == null:
		return
	if speed_label != null:
		speed_label.text = "%03d km/h" % int(round(vehicle.linear_velocity.length() * 3.6))
	if lap_label != null:
		lap_label.text = "LAP %d   //   CP %d/%d" % [_lap + 1, _next_checkpoint, CHECKPOINTS]
	if drift_label != null:
		var total_slip := 0.0
		var grounded := 0
		for sample in vehicle.last_wheel_samples:
			if bool(sample.get("grounded", false)):
				total_slip += absf(rad_to_deg(float(sample.get("slip_angle_rad", 0.0))))
				grounded += 1
		var mean_slip := total_slip / float(grounded) if grounded > 0 else 0.0
		drift_label.text = "SLIP %.1f°" % mean_slip

func _on_checkpoint_body_entered(body: Node3D, checkpoint_index: int) -> void:
	if body != vehicle or checkpoint_index != _next_checkpoint:
		return
	_next_checkpoint += 1
	if _next_checkpoint >= CHECKPOINTS:
		_next_checkpoint = 0
		_lap += 1

func _track_transform(angle: float, height: float) -> Transform3D:
	return Transform3D(
		Basis.looking_at(_ellipse_tangent(angle, TRACK_RADIUS_X, TRACK_RADIUS_Z), Vector3.UP),
		_ellipse_point(angle, TRACK_RADIUS_X, TRACK_RADIUS_Z) + Vector3.UP * height
	)

func _ellipse_point(angle: float, radius_x: float, radius_z: float) -> Vector3:
	return Vector3(cos(angle) * radius_x, 0.0, sin(angle) * radius_z)

func _ellipse_tangent(angle: float, radius_x: float, radius_z: float) -> Vector3:
	return Vector3(-sin(angle) * radius_x, 0.0, cos(angle) * radius_z).normalized()
