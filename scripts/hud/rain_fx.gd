class_name RainFx
extends Node3D
## Wet-weather visuals (0.10.0): a camera-following rain volume plus wheel
## spray emitters on every car, scaled by the track wetness. Particle counts
## stay low on purpose — the mobile renderer and the desktop llvmpipe QA
## runs both have to handle them. No scene, no audio: pure Node3D factory.

var _wetness := 0.5
var _cars: Array = []
var _rain: GPUParticles3D
var _sprays: Array[GPUParticles3D] = []


## wetness: track wetness 0..1 (WeatherState); cars: live Car nodes the
## spray emitters attach to. The node itself follows the active camera.
func _init(wetness: float, cars: Array) -> void:
	_wetness = clampf(wetness, 0.05, 1.0)
	_cars = cars
	_rain = _make_rain()
	add_child(_rain)
	for car in cars:
		var spray := _make_spray()
		(car as Node3D).add_child(spray)
		_sprays.append(spray)


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		_rain.global_position = camera.global_position + Vector3(0, 13.0, 0)
	for i in range(mini(_sprays.size(), _cars.size())):
		var car := _cars[i] as Car
		if car != null:
			_sprays[i].emitting = car.linear_velocity.length() > 8.0


## Camera-following rain: a wide flat emission box high above the camera,
## drops fall fast enough to read as rain, not snow.
func _make_rain() -> GPUParticles3D:
	var rain := GPUParticles3D.new()
	rain.amount = int(70.0 + 260.0 * _wetness)
	rain.lifetime = 0.7
	rain.preprocess = 0.7
	rain.position = Vector3(0, 13.0, 0)
	rain.process_material = _particle_material(
		Vector3(0, -1, 0), 4.0, 4.0, 9.0, Vector3(0, -38, 0), Vector3(26, 2, 26)
	)
	rain.draw_pass_1 = _particle_mesh(Vector2(0.035, 0.42), Color(0.75, 0.8, 0.92, 0.5))
	return rain


## Rear-wheel spray: kicks up and back from the rear axle while the car
## moves; emitting is toggled per frame by the speed gate in _process.
func _make_spray() -> GPUParticles3D:
	var spray := GPUParticles3D.new()
	spray.amount = int(10.0 + 24.0 * _wetness)
	spray.lifetime = 0.45
	spray.position = Vector3(0, 0.2, 1.6)
	spray.process_material = _particle_material(
		Vector3(0, 1.0, 1.0), 22.0, 3.0, 8.0, Vector3(0, -9, 0), Vector3(0.75, 0.12, 0.35)
	)
	spray.draw_pass_1 = _particle_mesh(Vector2(0.22, 0.22), Color(0.82, 0.84, 0.88, 0.26))
	return spray


static func _particle_material(
	direction: Vector3,
	spread_deg: float,
	vel_min: float,
	vel_max: float,
	gravity: Vector3,
	extents: Vector3
) -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	pm.direction = direction
	pm.spread = spread_deg
	pm.initial_velocity_min = vel_min
	pm.initial_velocity_max = vel_max
	pm.gravity = gravity
	return pm


static func _particle_mesh(size: Vector2, color: Color) -> QuadMesh:
	var mesh := QuadMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = color
	mesh.material = mat
	return mesh
