extends Node3D

var _frames := 0

func _ready() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 1.5, 4.0)
	add_child(camera)
	camera.look_at(Vector3.ZERO)

	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.15, 0.35, 0.95)
	material.emission_enabled = true
	material.emission = Color(0.2, 0.5, 2.0)
	material.emission_energy_multiplier = 1.5
	mesh.material = material
	mesh_instance.mesh = mesh
	add_child(mesh_instance)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, -30.0, 0.0)
	add_child(light)

func _process(_delta: float) -> void:
	_frames += 1
	if _frames != 8:
		return
	var rendering_device: RenderingDevice = RenderingServer.get_rendering_device()
	var rendering_api := ""
	if rendering_device != null:
		rendering_api = rendering_device.get_device_api_name()
	var result := {
		"profile": "boot",
		"renderer": RenderingServer.get_current_rendering_method(),
		"rendering_driver": RenderingServer.get_current_rendering_driver_name(),
		"rendering_api": rendering_api,
		"frames": _frames,
		"engine_version": Engine.get_version_info().get("string", "unknown"),
	}
	print("STARJUNK_WEBGPU_BOOT_JSON:" + JSON.stringify(result))
	if OS.has_feature("web"):
		JavaScriptBridge.eval(
			"window.__STARJUNK_BOOT_RESULT__ = %s;" % JSON.stringify(result)
		)
	else:
		get_tree().quit(0)
